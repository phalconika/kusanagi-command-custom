if [  'ja' = $WPLANG  ]; then
	DL_URL='https://ja.wordpress.org/latest-ja.tar.gz';
else
	DL_URL='https://wordpress.org/latest.tar.gz';
fi

wget -q -O /dev/null --spider $DL_URL
ret=$?

if [ $ret -eq 0 ] ; then
	mkdir /tmp/wp
	cd /tmp/wp
	wget -O 'wordpress.tar.gz' $DL_URL
	tar xzf ./wordpress.tar.gz
	mv ./wordpress/* $TARGET_DIR/DocumentRoot
	rm -rf /tmp/wp

    cp -p /usr/lib/kusanagi/resource/wp-config-sample/$WPLANG/wp-config-sample.php $TARGET_DIR/DocumentRoot/
else
    cp -r /usr/lib/kusanagi-wp/* $TARGET_DIR/DocumentRoot
    cp -p /usr/lib/kusanagi/resource/wp-config-sample/en_US/wp-config-sample.php $TARGET_DIR/DocumentRoot/
fi

#PREFIX=`cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 8 | head -n 1 | uniq`
cd $TARGET_DIR/DocumentRoot
#/usr/bin/wp db create
#/usr/bin/wp core config --dbname="${DBNAME}" --dbuser="${DBUSER}" --dbpass="${DBPASS}" --dbhost=localhost --dbprefix="${PREFIX}_"
#/usr/bin/wp core install --url="${FDQN}" --title="${BLOGNAME}" --admin_user="${BLOGADMIN}" --admin_password="${BLOGPASS}" --admin_email="${BLOGMAIL}"
cp -rp /usr/lib/kusanagi/resource/DocumentRoot/* $TARGET_DIR/DocumentRoot/
cp -p /usr/lib/kusanagi/resource/DocumentRoot/.htaccess $TARGET_DIR/DocumentRoot/
cp -rp /usr/lib/kusanagi/resource/settings $TARGET_DIR/
cp -rp /usr/lib/kusanagi/resource/tools $TARGET_DIR/

if [ -d /home/kusanagi/.kusanagi/resources/mu-kusanagi-business-edition ]; then
    cp -rp /home/kusanagi/.kusanagi/resources/mu-kusanagi-business-edition/* /home/kusanagi/$PROFILE/DocumentRoot/wp-content/mu-plugins/
    chown -R kusanagi.kusanagi /home/kusanagi/$PROFILE/DocumentRoot/wp-content/mu-plugins/
fi

# get Wordpress plugin
function get_wp_plugin {
	local PLUGIN_NAME=$1
	local JSON_URL="https://api.wordpress.org/plugins/info/1.0/${PLUGIN_NAME}.json"
	local WORK=/tmp/plugins.$$
	local PREVDIR=`pwd`
	mkdir $WORK
	cd $WORK
	wget -q -O /dev/null --spider $JSON_URL
	local PLUGIN_VER=
	if [ $? -eq 0 ]  ; then
		# get plugin download_link/version info from wordpress.org 
		local WORKFILE="plugin.json"
		wget -q -O ${WORKFILE} ${JSON_URL} 2> /dev/null
		local URL=`php -r 'echo json_decode(fgets(STDIN))->download_link;' < ${WORKFILE}`
		PLUGIN_VER=`php -r 'echo json_decode(fgets(STDIN))->version;' < ${WORKFILE}`
		ZIP=`basename $URL`
		wget -q -O /dev/null --spider $URL
		if [ $? -eq 0 ] ; then
			wget -q -O $ZIP $URL
			unzip -q $ZIP
			rm $ZIP
			# move ZIP file to PROFILE's plugin directory
			if [ -d $PLUGIN_NAME ] ; then
				mv $PLUGIN_NAME $TARGET_DIR/DocumentRoot/wp-content/plugins
			else
				PLUGIN_VER=
			fi
			rm $WORKFILE
		fi
	fi
	cd $PREVDIR
	rmdir $WORK

	# echo empty string when cannot get plugins
	echo $PLUGIN_VER
}

# WooCommerce plugin
if [ $OPT_WOO ] ; then
	# get WooCommerce plugin
	WOOCOMMERCE_VERSION=`get_wp_plugin woocommerce`
	if [ -n $WOOCOMMERCE_VERSION ] ; then
		ACTIVE_PLUGINS="woocommerce/woocommerce.php"
		echo $(eval_gettext "Install WooCommerce plugin")

		KUSANAGI_DEFAULT_INI=$TARGET_DIR/settings/kusanagi-default.ini

		# get Storefront theme
                SF_URL=http://api.wordpress.org/themes/info/1.0/
		SF_POST='action=theme_information&request=O:8:"stdClass":1:{s:4:"slug";s:10:"storefront";}'
		IS_SF_THEME=
		wget -q -O /dev/null --spider --post-data $SF_POST $SF_URL
		if [ $? -eq 0 ] ; then
			# get version info
			SF_DOWNLOAD=`wget -q -O - --post-data $SF_POST $SF_URL | \
			  php -r 'echo unserialize(fgets(STDIN))->download_link;'`
			SF_ZIP=storefront.zip
			wget -q -O /dev/null $SF_DOWNLOAD
			if [ $? -eq 0 ] ; then
				wget -O $SF_ZIP $SF_DOWNLOAD
				unzip -q $SF_ZIP
				rm $SF_ZIP
				mv storefront $TARGET_DIR/DocumentRoot/wp-content/themes/
				echo $(eval_gettext "Install Storefront Theme")
				IS_SF_THEME=1
			fi
		fi
		if [ $IS_SF_THEME -ne 1 ] ; then
			echo $(eval_gettext "Cannot install Storefront Theme")
		fi

		cd

		if [  'ja' = $WPLANG  ]; then
			# get WooCommerce-for-japan plugin
			WCFJ_VERSION=`get_wp_plugin woocommerce-for-japan`
			if [ -n $WCFJ_VERSION ] ; then
				echo $(eval_gettext "Install WooCommerce for japan plugin")
				ACTIVE_PLUGINS="woocommerce-for-japan/woocommerce-for-japan.php $ACTIVE_PLUGINS"
			else
				echo $(eval_gettext "Cannot install WooCommerce for japan plugin")
			fi

			# get WooCommerce launguage pack when WPLANG=ja
			WOOCOMMERCE_JA_URL=https://downloads.wordpress.org/translation/plugin/woocommerce/${WOOCOMMERCE_VERSION}/ja.zip
			wget -q -O /dev/null --spider $WOOCOMMERCE_JA_URL
			if [ $? -eq 0 ] ; then
				WORK=/tmp/woo-language.$$
				mkdir $WORK
				cd $WORK
				wget $WOOCOMMERCE_JA_URL
				unzip -q ja.zip
				rm ja.zip
				mv ./* $TARGET_DIR/DocumentRoot/wp-content/languages/plugins
				cd
				rmdir $WORK
				echo $(eval_gettext "Install WooCommerce japanese language file(\${WOOCOMMERCE_VERSION})")
			else
				echo $(eval_gettext "Cannot install WooCommerce japanese language file(\${WOOCOMMERCE_VERSION})")
			fi
			# install GMO payment plugins
			GMOPLUGIN="/usr/lib/kusanagi/resource/plugins/wc4jp-gmo-pg.1.2.0.zip"
			if [ -e $GMOPLUGIN ] ; then
				WORK=/tmp/gmo.$$
				mkdir $WORK
				cd $WORK
				unzip -q $GMOPLUGIN
				mv wc4jp-gmo-pg $TARGET_DIR/DocumentRoot/wp-content/plugins/
				# rm -rf __MACOSX
				cd
				rm -rf $WORK
				ACTIVE_PLUGINS="wc4jp-gmo-pg/wc4jp-gmo-pg.php $ACTIVE_PLUGINS"
				echo $(eval_gettext "Install WooCommerce For GMO PG.")
			else
				echo $(eval_gettext "Cannot install WooCommerce For GMO PG.")
			fi
		fi

		# add initial install plugins setting to kusanagi-default.ini
		if [ -f $KUSANAGI_DEFAULT_INI ] ; then
			if [ "${ACTIVE_PLUGINS}" != "" ] ; then
				(echo -n active_plugins = \' 
				 echo -n ${ACTIVE_PLUGINS} | php -r 'echo serialize(explode(" ", fgets(STDIN)));' 
				 echo \' ) >> $KUSANAGI_DEFAULT_INI
			fi
			# for Storefront theme
			if [ $IS_SF_THEME -eq 1 ] ; then
				(echo "template = storefront"
				 echo "stylesheet = storefront") >> $KUSANAGI_DEFAULT_INI
			fi
		fi
	else
		echo $(eval_gettext "Cannot install WooCommerce plugin(\${WOOCOMMERCE_VERSION})")
	fi

fi

chown -R kusanagi.kusanagi $TARGET_DIR
chmod 0777 $TARGET_DIR/DocumentRoot
chmod 0777 $TARGET_DIR/DocumentRoot/wp-content
chmod 0777 $TARGET_DIR/DocumentRoot/wp-content/uploads
if [ ! -d $TARGET_DIR/DocumentRoot/wp-content/languages/plugins ]; then
        mkdir -p $TARGET_DIR/DocumentRoot/wp-content/languages/plugins
fi
if [ ! -d $TARGET_DIR/DocumentRoot/wp-content/languages/themes ]; then
        mkdir -p $TARGET_DIR/DocumentRoot/wp-content/languages/themes
fi

chmod 0777 -R $TARGET_DIR/DocumentRoot/wp-content/languages
chmod 0777 -R $TARGET_DIR/DocumentRoot/wp-content/plugins
sed -i "s/fqdn/$FQDN/g" $TARGET_DIR/tools/bcache.clear.php
