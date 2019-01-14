TARGET_NAME=`echo $TARGET_DIR | awk -F "/" '{ print $NF }'`
TARGET_PARENT=`dirname $TARGET_DIR`

cd $TARGET_PARENT

if ! k_kusanagi_user_exec "${KUSANAGI_COMPOSER_BIN} create-project -n concrete5/composer ${TARGET_NAME}" ; then
	return 1
fi

APP_BASE_DIR=$TARGET_DIR

servers=(nginx httpd)
for server in ${servers[@]}; do
	if [ ! -d ${APP_BASE_DIR}/log/${server} ]; then
		mkdir -p ${APP_BASE_DIR}/log/${server}
	fi
done

cp -r /usr/lib/kusanagi/skel/etc $TARGET_DIR/etc

chown -R kusanagi.kusanagi $APP_BASE_DIR

cd $TARGET_DIR/public

mkdir application/languages
for file in application/languages application/config application/files packages
do
	chown -R httpd.www ${file}
	chmod -R g+w ${file}
done
