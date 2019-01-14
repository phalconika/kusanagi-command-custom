## virt.sh

ITEMS=("etc/monit.d/fqdn_httpd.conf" "etc/monit.d/fqdn_nginx.conf" "etc/nginx/conf.d/fqdn_http.conf" "etc/nginx/conf.d/fqdn_ssl.conf" "etc/httpd/conf.d/fqdn_http.conf etc/httpd/conf.d/fqdn_ssl.conf")
#PROFILE="www"
#FQDN="test.com"

local IS_ROOT_DOMAIN=$(is_root_domain $FQDN;echo $?)
local ADDFQDN=
if  [ "$IS_ROOT_DOMAIN" -eq 0 ]  ; then
	ADDFQDN="www.${KUSANAGI_FQDN}"
elif [ "$IS_ROOT_DOMAIN" -eq 1 ] ; then
	ADDFQDN=`echo $KUSANAGI_FQDN | cut -c 5-`
fi
for ITEM in ${ITEMS[@]} ; do
	local RESOURCE="/usr/lib/kusanagi/resource"
	TARGET="/"`echo $ITEM | sed "s/fqdn/$PROFILE/"`
	if [ -f "$RESOURCE/${ITEM}.${APP}" ] ; then
		SOURCE="$RESOURCE/${ITEM}.${APP}"
	else
		SOURCE="$RESOURCE/${ITEM}"
	fi
	# if [ -e $TARGET ]; then
	# 	cp $TARGET ${TARGET}.bak
	# fi
	echo $ITEM | grep -e httpd/conf.d -e nginx/conf.d 2>&1 > /dev/null
	local RET=$?
	local PROV="# Common specific setting"
	cp $SOURCE $TARGET
	if [ $RET -eq 0 ]; then
		if [ -f "$RESOURCE/${ITEM}.${APP}.common" ] ; then
			sed -i "/^$PROV start/r /dev/stdin" $TARGET < $RESOURCE/${ITEM}.${APP}.common
			sed -i "/$PROV/d" $TARGET
		elif [ -f "$RESOURCE/${ITEM}.common" ] ; then
			sed -i "/^$PROV start/r /dev/stdin" $TARGET < $RESOURCE/${ITEM}.common
			sed -i "/$PROV/d" $TARGET
		fi
		if [ "$APP" = "Rails" ] ; then
			sed -i -e "s/secret_key_base/`/usr/local/bin/ruby -rsecurerandom -e 'puts SecureRandom.hex(64)'`/" $TARGET 
		fi
	fi

	# WAF settings
	local WAF_TYPE='general'
	case "${APP}" in
		'WordPress') WAF_TYPE='wordpress' ;;
	esac

	# replace placeholder
	TARGET_DIR_ESCAPED=$(echo $TARGET_DIR | sed -e 's/\//\\\//g');
	sed -i -e "s/\/home\/kusanagi\/profile/$TARGET_DIR_ESCAPED/g" -e "s/fqdn/$KUSANAGI_FQDN/g"  -e "s/{waf_type}/$WAF_TYPE/g" $TARGET
	# replace placeholder again for monit
	sed -i -e "s/profile/$PROFILE/g" $TARGET

	if [ -n "$ADDFQDN" ] ; then
		if [[ $ITEM =~ ^etc/nginx/conf.d/ ]] ; then
			sed -i -e "s/^\(\s*server_name\s\+.*\);/\1 ${ADDFQDN};/" \
				-e "/# SSL ONLY/a\	# rewrite ^(.*)$ https:\/\/$ADDFQDN\$request_uri permanent; # SSL ONLY" $TARGET
		elif [[ $ITEM =~ ^etc/httpd/conf.d/ ]] ; then
			sed -i "/^\s\+ServerName\s/a\	ServerAlias ${ADDFQDN}" $TARGET
		fi
	fi
done

if [ "$APP" != "Rails" ] && [ "$APP" != "concrete5" ]; then
	mkdir -p $TARGET_DIR/DocumentRoot
	mkdir -p $TARGET_DIR/log/nginx
	mkdir -p $TARGET_DIR/log/httpd
fi

if [ \! -e /usr/lib/kusanagi/lib/deploy-$APP.sh ] ; then
	echo $(eval_gettext "Cannot deploy \$APP")
	return 1
fi

if ! source /usr/lib/kusanagi/lib/deploy-$APP.sh ; then
	return 1
fi

sed -i "s/^\(127.0.0.1.*\)\$/\1 $FQDN $ADDFQDN/" /etc/hosts || \
 (sed "s/\(^127.0.0.1.*$\)/\1 $FQDN $ADDFQDN/" /etc/hosts > /tmp/hosts.$$ && \
  cat /tmp/hosts.$$ > /etc/hosts && /usr/bin/rm /tmp/hosts.$$)

RET=0
# setting ssl cert files
if [ "" != "$MAILADDR" ] && [ -e $CERTBOT ]; then
	# restart nginx or httpd server
	k_restart nginx httpd

	# enable ssl
	source $LIBDIR/ssl.sh
	enable_ssl  $PROFILE $MAILADDR $FQDN
	RET=$?
	if [ $RET -eq 0 ] ; then
		k_autorenewal --auto on
	fi
fi

if [ $RET -eq 0 ] ; then
	# reload services
	k_reload nginx httpd monit
	sleep 1
	k_monit_reloadmonitor
fi

