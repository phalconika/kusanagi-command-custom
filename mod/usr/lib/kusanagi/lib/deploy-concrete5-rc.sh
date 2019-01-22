cd /home/kusanagi

if ! ${KUSANAGI_COMPOSER_BIN} create-project -n concrete5/composer ${PROFILE} ; then
	return 1
fi

APP_BASE_DIR=$TARGET_DIR

servers=(nginx httpd)
for server in ${servers[@]}; do
	if [ ! -d ${APP_BASE_DIR}/log/${server} ]; then
		mkdir -p ${APP_BASE_DIR}/log/${server}
	fi
done

chown -R kusanagi.kusanagi $APP_BASE_DIR

cd ${PROFILE}/public

mkdir application/languages
for file in application/languages application/config application/files packages
do
	chown -R httpd.www ${file}
	chmod -R g+w ${file}
done
