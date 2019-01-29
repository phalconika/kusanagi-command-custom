#!

function k_readkey_yn() {
	local MSG="$@"
	while :
	do
		echo -n $MSG" " 1>&2
		read usekey
		if [ -z "$usekey" ] ; then
			:
		elif [ ${usekey,,} = 'y' ] ; then
			echo 1
			break
		elif [ ${usekey,,} = 'n' ] ; then
			break
		fi
	done
}

function k_remove () {
	shift
	_k_remove $@
}

function _k_remove() {
	local YESFLAG=
	local TARGET=
	for OPT in "$@"
	do
		case "$OPT" in
			'-y')
				YESFLAG=1
			;;
			'--*')
				echo $(eval_gettext "Cannot use option \$OPT")
				return 1
			;;
			*)
				if [ -z "${TARGET}" ] ; then
					TARGET=$OPT
				fi
			;;
		esac
	done

	if [ -z $TARGET ] ; then
		TARGET=$PROFILE
	fi
	k_read_profile $TARGET

	# select delete modules
	local REMOVE_CONTENT=
	local REMOVE_CONFIG=
	local REMOVE_DATABASE=
	if [ $YESFLAG ] ; then
		REMOVE_CONTENT=1
		REMOVE_CONFIG=1
		[ -n "$KUSANAGI_DBNAME" ] && REMOVE_DATABASE=1
	else
		REMOVE_CONFIG=$(k_readkey_yn $(eval_gettext "Remove \$TARGET config files ? [y/n] "))
		REMOVE_CONTENT=$(k_readkey_yn $(eval_gettext "Remove directory \$KUSANAGI_DIR ? [y/n] "))
		[ -n "$KUSANAGI_DBNAME" ] && REMOVE_DATABASE=$(k_readkey_yn $(eval_gettext "Remove \$TARGET database ? [y/n] "))
	fi

	# remove config file
	if [ $REMOVE_CONFIG ] ; then
		# remove files
		for file in $NGINX_HTTP $NGINX_HTTPS $HTTPD_HTTP $HTTPD_HTTPS \
				"/etc/monit.d/${TARGET}_nginx.conf" "/etc/monit.d/${TARGET}_httpd.conf"
		do
			[ -f $file ] && rm $file
		done
		local IS_ROOT_DOMAIN=$(is_root_domain $KUSANAGI_FQDN;echo $?)
		local ADDFQDN=
		if  [ "$IS_ROOT_DOMAIN" -eq 0 ]  ; then
			ADDFQDN="www.${KUSANAGI_FQDN}"
		elif [ "$IS_ROOT_DOMAIN" -eq 1 ] ; then
			ADDFQDN=`echo $KUSANAGI_FQDN | cut -c 5-`
		fi
		# hosts
		sed -i "s/\s\+$KUSANAGI_FQDN\(\s*\)/\1/g" /etc/hosts
		if [ -n "$ADDFQDN" ] ; then
			sed -i "s/\s\+$ADDFQDN\(\s*\)/\1/g" /etc/hosts
		fi
	fi

	# remove content
	if [ $REMOVE_CONTENT ] && [ -d $KUSANAGI_DIR ]; then
		rm -rf $KUSANAGI_DIR
	fi

	# remove db
	if [ $REMOVE_DATABASE ] ; then
		if [ -z "$KUSANAGI_MARIADB" ] || [ "$KUSANAGI_MARIADB" = yes ]; then
			local DB_ROOT_PASS=$(get_db_root_password)
			echo "drop database \`$KUSANAGI_DBNAME\`;" | mysql -uroot -p"$DB_ROOT_PASS"
			echo "delete from mysql.user where User = '$KUSANAGI_DBUSER';" | mysql -uroot -p"$DB_ROOT_PASS"
		fi
		if [ "$KUSANAGI_PSQL" = yes ]; then
			su - postgres -c "dropdb --username=postgres $KUSANAGI_DBNAME"
			su - postgres -c "dropuser --username=postgres $KUSANAGI_DBUSER"
		fi
	fi

	# remove profile
	if [ -n "${TARGET}" ] ; then
		k_write_profile $TARGET '' remove
		if [ -f /etc/kusanagi.conf ] && \
				[ 0 -eq $(grep $TARGET /etc/kusanagi.conf 2>&1 > /dev/null; echo $?) ] ; then
			local LAST=$(awk '/^\[/ {gsub(/^\[|\]$/, ""); a=$0} END {print a}' /etc/kusanagi.d/profile.conf)
			echo "PROFILE=\"$LAST\"" > /etc/kusanagi.conf
		fi
	fi
}
