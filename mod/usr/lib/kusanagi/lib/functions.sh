# ---
# KUSANAGI functions
# /usr/bin/kusanagi 専用ライブラリ
# ---
# 2015/07/21 Ver. 1.0.3

PROFILECONF=/etc/kusanagi.d/profile.conf
CERTBOT=/usr/local/certbot/certbot-auto

# help command
function k_help () {
		cat << EOD
///////////////////////////////////////////////////
High-Performance WordPress VirtualMachine
///////////////////////////////////////////////////
     __ ____  _______ ___    _   _____   __________
    / //_/ / / / ___//   |  / | / /   | / ____/  _/
   / ,< / / / /\__ \/ /| | /  |/ / /| |/ / __ / /
  / /| / /_/ /___/ / ___ |/ /|  / ___ / /_/ // /
 /_/ |_\____//____/_/  |_/_/ |_/_/  |_\____/___/

///////////////////////////////////////////////////
///       C     U     S     T     O     M       ///
///////////////////////////////////////////////////

CLI Subcommand inforamtion
Manual : http://en.kusanagi.tokyo/document/command/ or type "man kusanagi"
---------------------
- help -
# kusanagi [-h | --help | help]
show this snippet.
---------------------
- configuration -
init [options]
	[--tz TZ] [--lang [ja|en]] [--keyboard [ja|en]]
	[--passwd PASSWD] [--phrase PHRASE|--no-phrase]
	[--dbrootpass DBPASS]
	[--nginx|--httpd] [--hhvm|--php7|--php5|--ruby24]
setting [--fqdn domainname]
ssl [options] profile
	[--email email@example.com] [--cert file --key file]
	[--https [redirect|noredirect]]
	[--hsts  {on|off}]
	[--auto  [on|off]]
	[--ct  [on|off] [--no-register|--noregister]]
provision [options] profile
	[--WordPress [--woo|--WooCommerce] [--wplang en_US|ja]|--lamp|--concrete5|--drupal|--rails|--phpMyAdmin]
	[--email mail_address|--no-email]
	[--dbskip|[--dbname dbname] [--dbuser username] [--dbpass password]]
	[--dst-dir destination_directory]
https [redirect|noredirect]		*obsolete
autorenewal [on|off]		* obsolete
remove [-y] [profile]
dbinit [mariadb|psql]
---------------------
- status -
[-V|--version]
warm-up
target [profile]
update [plugin [-y] |cert] [profile]
restart
upgrade [mariadb] [--force]
---------------------
- middleware -
nginx
httpd
php7
php-fpm
hhvm
ruby2.4
---------------------
- cache -
bcache [on|off|clear [path [--dryrun]]]
fcache [on|off|clear [path [--dryrun]]]
---------------------
- manage -
configure
images [--jpg|--jpeg|--png] [--verbose] [--dir|--directory dirname]
	[--quality [0-100]] [--resize [1280x1024]] [--color [0-256]] [--strip]
	[--owner user[:group]] [--mode 0644] [profile]
addon install|remove ADDON
	ADDON is one of:
	* mroonga (http://mroonga.org/)
	* go (https://golang.org/)
	* vuls (https://vuls.io/)
	* tripwire (https://github.com/Tripwire/tripwire-open-source)
	* suricata (https://suricata-ids.org/)
---------------------
- security -
waf {on|off}
selinux {on [--strict]|off [--permanent]}
---------------------
- expart -
monit [on|off|config|reload]
zabbix [on|off]
----------------------
EOD
}

# force wp commands to run as the kusanagi user
function wp () {
	sudo -u kusanagi -i -- /usr/local/bin/wp "$@"
}

function check_status() {
	# 直前のコマンドの戻り値により、'Done.'または'Failed.'を表示する。
	# デーモンの起動など行った際にはコールすること。
	# ${_RETURN}は、exitの引数に付けてください。 
	if [ "$?" -eq 0 ]; then
		_RETURN=0
		echo $(eval_gettext "Done.")
	else
		_RETURN=1
		echo $(eval_gettext "Failed.")
	fi
}

function check_profile() {
	if [ "$PROFILE" = "" ]; then
		echo $(eval_gettext "No Profile exists.")
	else
		k_read_profile $PROFILE
	fi
}

function k_read_profile() {
	PROFILE=$1
	local DONTWRITE=${2:-}
	local INIFILE=${3:-$PROFILECONF}
	if [ -f $INIFILE ] ; then
		# load from inifile
		eval $(awk "/^\[.+\]/ {p = 0 } /^\[$PROFILE\]/ { p = 1 } p == 1" $INIFILE | \
			awk '$1 ~ /^.+=.+$/ {print $1} ')
	fi

	# set uninitialized value
	local IS_WRITABLE=0
	if [[ ! -v KUSANAGI_DIR ]] ; then
		KUSANAGI_DIR=/home/kusanagi/$PROFILE
		if [ ! -d $KUSANAGI_DIR ] ; then
			echo -n  $(eval_gettext "Target profile(\$PROFILE) not found.") >&2
			echo $(eval_gettext "\$KUSANAGI_DIR not found") >&2
			exit 1
		fi
		IS_WRITABLE=1
	fi

	if [[ ! -v KUSANAGI_FQDN ]] ; then
		KUSANAGI_FQDN=$(k_get_fqdn $PROFILE)
		if [ "$KUSANAGI_FQDN" = "" ] ; then
			echo -n  $(eval_gettext "Target profile(\$PROFILE) not found.") >&2
			echo $(eval_gettext "FQDN cannot get") >&2
			exit 1
		fi
		IS_WRITABLE=1
	fi
	if [[ ! -v KUSANAGI_TYPE ]] ; then
		KUSANAGI_TYPE=WordPress
		IS_WRITABLE=1
	fi

	NGINX_HTTP="/etc/nginx/conf.d/${PROFILE}_http.conf"
	NGINX_HTTPS="/etc/nginx/conf.d/${PROFILE}_ssl.conf"
	HTTPD_HTTP="/etc/httpd/conf.d/${PROFILE}_http.conf"
	HTTPD_HTTPS="/etc/httpd/conf.d/${PROFILE}_ssl.conf"

	# TARGET_DIR=/home/kusanagi/$PROFILE
	TARGET_DIR=$KUSANAGI_DIR
	if [ "$KUSANAGI_TYPE" = "WordPress" ] ; then
		if [ -e $(dirname `realpath $TARGET_DIR/DocumentRoot`)/wp-config.php ]; then
			WPCONFIG=$(dirname `realpath $TARGET_DIR/DocumentRoot`)/wp-config.php
		elif [ -e $TARGET_DIR/DocumentRoot/wp-config.php ]; then
			WPCONFIG="$TARGET_DIR/DocumentRoot/wp-config.php"
		else
			WPCONFIG=""
		fi
	fi

	if [ -z $DONTWRITE ] && [ $IS_WRITABLE -eq 1 ] ; then
		k_write_profile $PROFILE
	fi
}

function k_write_profile() {
	local PROFILE=$1
	local INIFILE=${2:-$PROFILECONF}
	local REMOVE=${3:-no} # unless set no(default), remove PROFILE

	local WORK=$(mktemp)
	if [ -f $PROFILECONF ] ; then
		awk "BEGIN { p = 1 } /^\[.+\]/ { p = 1 } /^\[$PROFILE\]/ { p = 0 } p == 1" $PROFILECONF > $WORK
	fi

	# do not remove $PROFILE
	if [ "$REMOVE" = "no" ] ; then
		echo "[${PROFILE}]" >> $WORK
		for c in PROFILE \
			KUSANAGI_TYPE KUSANAGI_FQDN KUSANAGI_DIR \
			KUSANAGI_DBNAME KUSANAGI_DBUSER KUSANAGI_DBPASS \
			WPLANG OPT_WOO \
			KUSANAGI_MARIADB KUSANAGI_PSQL ; do
			if [[ -v $c ]]; then
				echo "$c=\"${!c}\"" >> $WORK
			fi
		done
	fi

	[ -d ${PROFILECONF%/*} ] || mkdir ${PROFILECONF%/*}
	cat $WORK > $PROFILECONF
	chmod 600 $PROFILECONF
	rm $WORK
}

function k_is_active() {
	# active=0, other=1
	[ -n "$1" ] && systemctl is-active $1.service 2> /dev/null | grep ^active > /dev/null ; echo $?
}

function k_is_enabled() {
	# enable=0, disabled=1
	[ -n "$1" ] && systemctl is-enabled $1.service 2> /dev/null | grep ^enabled > /dev/null ; echo $?
}

function k_yum_install () {
	if rpm -q "$1" > /dev/null 2>&1 ; then
		return 0
	else
		yum -y install "$1" > /dev/null
		return $?
	fi
}

# show current kusanagi status
function k_status() {

	shift

	ARG1="$1"

	local RET
	[[ -n "$PROFILE" ]] && echo "Profile: $PROFILE"
	[[ -v KUSANAGI_FQDN ]] && echo FQDN: "$KUSANAGI_FQDN"
	[[ -v KUSANAGI_TYPE ]] && echo Type: "$KUSANAGI_TYPE"
	cat /etc/kusanagi
	echo

	# sytemd daemons
	declare -A local SERVICES
	SERVICES=(
		 ["nginx"]="nginx"
		 ["Apache2"]="httpd"
		 ["HHVM"]="hhvm"
		 ["php-fpm"]="php-fpm"
		 ["php7-fpm"]="php7-fpm"
		 ["PostgreSQL"]="postgresql-9.6"
		 ["MariaDB"]="mysql"
		 ["Pgpool-II"]="pgpool"
	)	

	local STATUS

	for SERVICE in ${!SERVICES[@]};
	do
		STATUS=`systemctl status ${SERVICES[$SERVICE]} 2> /dev/null`
		RET=$?
		if [[ $RET -ne 0 ]]; then
			if [[ ${SERVICES[$SERVICE]} = "mysql" ]]; then
				_STATUS=`systemctl status mariadb 2> /dev/null`
				RET=$?
				if [[ $RET -ne 0 ]]; then
					if [[ "$ARG1" = '--all' ]]; then
						echo "*** (not active) ${SERVICE} ***"
					fi
				else
					k_print_green "*** (active) ${SERVICE} ***"
				fi
			else
				if [[ "$ARG1" = '--all' ]]; then
					echo "*** (not active) ${SERVICE} ***"
				fi
			fi
		else
			k_print_green "*** (active) ${SERVICE} ***"
		fi
		if [[ $RET -eq 0 ]] || [[ $ARG1 = '--all' ]]; then
			echo "${STATUS}" | head -n 1
			echo "${STATUS}" | grep -E '(Loaded:|Active:)'
			echo
		fi
	done

	echo "*** ruby ***"
	if [ -f /usr/local/bin/ruby ]; then
		/usr/local/bin/ruby --version
	else
		echo 'KUSANAGI Ruby is not installed yet'
	fi

	echo

	echo "*** add-on ***"
	if is_mroonga_activated ; then
		k_print_green "(active) Mroonga"
	fi
	if is_go_installed ; then
		k_print_green "(install) Go"
	fi
	if is_vuls_installed ; then
		k_print_green "(install) Vuls"
	fi
	if is_tripwire_installed ; then
		k_print_green "(install) Open Source Tripwire"
	fi
	if is_suricata_activated ; then
		k_print_green "(active) Suricata"
	fi

	echo

	if [[ -n $PROFILE ]]; then
		echo "*** Cache Status ***"
		if [ "$WPCONFIG" ]; then
			RET=`grep -e "^[[:space:]]*define[[:space:]]*([[:space:]]*'WP_CACHE'" $WPCONFIG | grep 'true'`
			if [ "$RET" ]; then
				k_print_green "bcache on"
			else
				echo "bcache off"
			fi
		fi
		RET=`grep -e "set[[:space:]]*\\$do_not_cache[[:space:]]*0[[:space:]]*;[[:space:]]*##[[:space:]]*page[[:space:]]*cache" $NGINX_HTTP`
		if [ "$RET" ]; then
			k_print_green "fcache on"
		else
			echo "fcache off"
		fi

		echo
	fi

	echo "*** WAF ***"
		if k_is_waf_activated ; then
			k_print_green "on"
		else
			echo "off"
		fi
	echo

	echo "*** SELinux ***"
		if k_is_selinux_activated ; then
			if __k_is_selinux_strict_security ; then
				k_print_green "on (strict)"
			else
				k_print_green "on"
			fi
		else
			if selinuxenabled ; then
				echo "off"
			else
				echo "off (permanent)"
			fi
		fi
	echo
}

function k_nginx() {
	echo $(eval_gettext "use nginx")
	if [ 0 -eq $(k_is_enabled httpd) ] ; then
		systemctl stop httpd && systemctl disable httpd
	fi
	systemctl restart nginx && systemctl enable nginx
	k_monit_reloadmonitor
}

function get_db_root_password() {
	if [ -e /root/.my.cnf ];then
		TMP=`grep password /root/.my.cnf | head -1`
		TMP=`echo $TMP | sed 's/^.*=\s*"//' | sed 's/"\s*$//'`
		echo $TMP
		TMP=""
	fi
}

function check_db_root_password() {
	local passwd=$1
	if [[ "$passwd" =~ ^[a-zA-Z0-9\.\!\#\%\+\_\-]{8,}$ ]]; then
		echo 0
	else
		echo 1
	fi
}

# set or change Mariadb password for root.
function set_db_root_password() {
	local oldpass=$1
	local newpass=$2
	TMP=`echo "show databases" | mysql -uroot -p"$oldpass" 2>&1 | grep information`
	# check password( Use [a-zA-Z0-9.!#%+_-] 8 characters minimum ).
	if [ "$TMP" = "" ] || [ 1 -eq $(check_db_root_password $newpass) ] ; then
		echo $(eval_gettext "Failed.")
		return 1
	fi
	echo "SET PASSWORD = PASSWORD('$newpass')" | mysql -uroot -p"$oldpass"
	sed -i "s/^\s*password\s*=.*$/password = \"$newpass\"/" /root/.my.cnf
	echo $(eval_gettext "Password has changed.")
}

# set or change PostgreSQL password for postgres user.
function set_db_postgres_password () {
	local newpass=$1

	if su - postgres -c "psql --username=postgres --command=\"Alter role postgres with password '$newpass'\"" ; then
		echo $(eval_gettext "Password has changed.")
	else
		echo $(eval_gettext "Failed.")
		return 1
	fi
}

# re-run setup configuration after the system change.
function k_configure() {

	local MY_CONF PG_CONF
	local DB_SYSTEMS=`get_running_db_service`

	if [ -z "$DB_SYSTEMS" ]; then
		echo $(eval_gettext "database daemon is not running.")
		echo $(eval_gettext "Use 'kusanagi dbinit' to activate the database daemon.")
		return 1
	fi

	## initialize database system.
	k_shutdown_all_db > /dev/null

	# set allocated buffer variables
	k_set_buffer_variable

	# MariaDB conf
	if [ -f /etc/my.cnf.d/server.cnf ]; then
		MY_CONF=/etc/my.cnf.d/server.cnf
	fi

	# PostgreSQL conf
	if [ -f /var/lib/pgsql/9.6/data/postgresql.conf ]; then
		PG_CONF=/var/lib/pgsql/9.6/data/postgresql.conf
	fi

	# Pgpool-II conf
	if [ -f /etc/pgpool-II/pgpool.conf ]; then
		PG_POOL_CONF=/etc/pgpool-II/pgpool.conf
	fi

	local DB_SYSTEM
	for DB_SYSTEM in $(echo "$DB_SYSTEMS")
	do
		case "$DB_SYSTEM" in
			'mariadb')
				echo $(eval_gettext "innodb_buffer_pool_size = \${INNODB_BUFFER}M")
				echo $(eval_gettext "query_cache_size = \${QUERY_CACHE}M")
				# MariaDB
				sed -i "s/^\s*innodb_buffer_pool_size\s*=.*$/innodb_buffer_pool_size = ${INNODB_BUFFER}M/" $MY_CONF
				sed -i "s/^\s*query_cache_size\s*=.*$/query_cache_size = ${QUERY_CACHE}M/"  $MY_CONF

				k_activate_mariadb

				;;
			'psql')
				# PostgreSQL

				echo $(eval_gettext "shared_buffers = \${PSQL_SHARED_BUFFERS}MB")
				sed -i -E "s/^[ #]*shared_buffers\s*=.*$/shared_buffers = ${PSQL_SHARED_BUFFERS}MB/" $PG_CONF

				echo $(eval_gettext "work_mem = \${PSQL_WORKMEM_BUFFERS}MB")
				sed -i -E "s/^[ #]*work_mem\s*=.*$/work_mem = ${PSQL_WORKMEM_BUFFERS}MB/" $PG_CONF

				# Pgpool-II
				echo $(eval_gettext "Pgpool-II num_init_children = \${PSQL_PGPOOL_CHILDREN}")
				sed -i -E "s/^[ #]*num_init_children\s*=.*$/num_init_children = ${PSQL_PGPOOL_CHILDREN}/" $PG_POOL_CONF

				echo $(eval_gettext "Pgpool-II memqcache_max_num_cache = \${PSQL_PGPOOL_QUERY_CACHE}")
				sed -i -E "s/^[ #]*memqcache_max_num_cache\s*=.*$/memqcache_max_num_cache = ${PSQL_PGPOOL_QUERY_CACHE}/" $PG_POOL_CONF

				k_activate_psql

				;;
			*)
				;;
		esac
	done

	# php7 configuration value
	_k_set_directive_num 'max_execution_time' 120 ${PHP7_INI} '<100'
	_k_set_directive_num 'request_terminate_timeout' 180 ${PHP7_FPM_CONF} '<100'
	k_restart_php_daemon
}

# set buffer memory variables for DB
function k_set_buffer_variable () {

	sleep 5

	local RET=`free -m | grep -e '^Mem:' | awk '{ print $2 }'`
	if [ "$RET" -gt 7200 ]; then
		INNODB_BUFFER=3072
		QUERY_CACHE=320
		PSQL_SHARED_BUFFERS=3072
		PSQL_WORKMEM_BUFFERS=16
		PSQL_PGPOOL_CHILDREN=200
		PSQL_PGPOOL_QUERY_CACHE=7000000
	elif [ "$RET" -gt 3600 ]; then
		INNODB_BUFFER=1536
		QUERY_CACHE=256
		PSQL_SHARED_BUFFERS=1536
		PSQL_WORKMEM_BUFFERS=8
		PSQL_PGPOOL_CHILDREN=200
		PSQL_PGPOOL_QUERY_CACHE=5600000
	elif [ "$RET" -gt 1800 ]; then
		INNODB_BUFFER=768
		QUERY_CACHE=192
		PSQL_SHARED_BUFFERS=768
		PSQL_WORKMEM_BUFFERS=8
		PSQL_PGPOOL_CHILDREN=200
		PSQL_PGPOOL_QUERY_CACHE=4200000
	elif [ "$RET" -gt 900 ]; then
		INNODB_BUFFER=384
		QUERY_CACHE=128
		PSQL_SHARED_BUFFERS=384
		PSQL_WORKMEM_BUFFERS=4
		PSQL_PGPOOL_CHILDREN=200
		PSQL_PGPOOL_QUERY_CACHE=2800000
	else
		INNODB_BUFFER=128
		QUERY_CACHE=64
		PSQL_SHARED_BUFFERS=128
		PSQL_WORKMEM_BUFFERS=2
		PSQL_PGPOOL_CHILDREN=32
		PSQL_PGPOOL_QUERY_CACHE=1400000
	fi
}

function k_ver_compare() {
	 /usr/bin/php -r '$a = version_compare( "'$1'", "'$2'", ">" ); if ( $a ) { exit( 1 ); } else { exit( 0 ); }'
}

function k_get_fqdn() {
	local PROFILE=$1
	local FQDN=
	if [[ -v KUSANAGI_FQDN ]] ; then
		FQDN=$KUSANAGI_FQDN
	elif [ ! -z $PROFILE ] && [ -f /etc/nginx/conf.d/${PROFILE}_http.conf ] ; then
		FQDN=$(awk -F'[ \t;]+' '/^[ \t]+server_name/ {printf "%s", $3}' /etc/nginx/conf.d/${PROFILE}_http.conf)
	fi
	echo $FQDN
}

function k_httpd() {
	echo $(eval_gettext "use TARGET") | sed "s|TARGET|$1|"
	if [ 0 -eq $(k_is_enabled nginx) ] ; then
		systemctl stop nginx && systemctl disable nginx
	fi
	systemctl restart httpd && systemctl enable httpd
	k_monit_reloadmonitor
}

function k_phpfpm() {
	echo $(eval_gettext "use TARGET") | sed "s|TARGET|$1|"
	local CHANGE=0
	if [ 0 -eq $(k_is_enabled hhvm) ] ; then
		systemctl stop hhvm && systemctl disable hhvm
		CHANGE=1
	fi
	if [ 0 -eq $(k_is_enabled php7-fpm) ] ; then
		systemctl stop php7-fpm && systemctl disable php7-fpm
		CHANGE=1
	fi
	systemctl restart php-fpm && systemctl enable php-fpm

	_k_change_php_bin $CHANGE
}

function k_php7() {
	echo $(eval_gettext "use TARGET") | sed "s|TARGET|$1|"
	local CHANGE=0
	if [ 0 -eq $(k_is_enabled hhvm) ] ; then
		systemctl stop hhvm && systemctl disable hhvm
		CHANGE=1
	fi
	if [ 0 -eq $(k_is_enabled php-fpm) ] ; then
		systemctl stop php-fpm && systemctl disable php-fpm
		CHANGE=1
	fi
	systemctl restart php7-fpm && systemctl enable php7-fpm

	_k_change_php_bin $CHANGE
}

function k_hhvm() {
	echo $(eval_gettext "use TARGET") | sed "s|TARGET|$1|"
	local CHANGE=0
	if [ 0 -eq $(k_is_enabled php7-fpm) ] ; then
		systemctl stop php7-fpm && systemctl disable php7-fpm
		CHANGE=1
	fi
	if [ 0 -eq $(k_is_enabled php-fpm) ] ; then
		systemctl stop php-fpm && systemctl disable php-fpm
		CHANGE=1
	fi
	systemctl restart hhvm && systemctl enable hhvm

	_k_change_php_bin $CHANGE
}

function k_ruby24() {
	echo $(eval_gettext "use TARGET") | sed "s|TARGET|$1|"
	local RUBY_VERSION="2.4"
	# Executable Ruby files
	local RUBY_EXECFILES=(ruby rdoc ri erb gem irb rake)
	for R_EXE in ${RUBY_EXECFILES[@]} ; do
		if [ -L /usr/local/bin/${R_EXE} ]; then
			unlink /usr/local/bin/${R_EXE}
		fi
		ln -s /bin/${R_EXE}${RUBY_VERSION} /usr/local/bin/${R_EXE}
	done
}

function k_ruby_init() {

	local rubyversion OPT_RUBY
	while :
	do
		echo $(eval_gettext "Then, Please tell me your ruby version.")
		echo $(eval_gettext "1) Ruby2.4")
		echo
		echo -n $(eval_gettext "Which you using?(1): ")
		read rubyversion
		case "$rubyversion" in
		""|"1" )
			echo
			echo $(eval_gettext "You choose: Ruby2.4")
			OPT_RUBY=ruby24
			break
			;;
		* )
			;;
		esac
	done

	case "$OPT_RUBY" in
	'ruby24')
		kusanagi ruby24
		;;
	*)
		;;
	esac
}

function k_composer () {
	shift

	case "$1" in
	'init')
		k_composer_init
		;;
	*)
		k_print_usage "kusanagi composer init"
		;;
	esac
}

function k_composer_init () {

	if which composer > /dev/null 2>&1 ; then
		if ! k_is_reinstall "composer" ; then
			return 0;
		fi
	fi

	local PHP_BIN=
	if [[ $(k_is_active php7-fpm) -eq 0 ]] ; then
		PHP_BIN=/bin/php7
		PHP_BIN_OPT_R="${PHP_BIN} -r"
	elif [[ $(k_is_active hhvm) -eq 0 ]] ; then
		PHP_BIN=/bin/hhvm
		PHP_BIN_OPT_R="${PHP_BIN} --php -r"
	elif [[ $(k_is_active php-fpm) -eq 0 ]] ; then
		PHP_BIN=/bin/php
		PHP_BIN_OPT_R="${PHP_BIN} -r"
	fi

	local EXPECTED_SIGNATURE="$(wget -q -O - https://composer.github.io/installer.sig)"
	${PHP_BIN_OPT_R} "copy('https://getcomposer.org/installer', 'composer-setup.php');"
	local ACTUAL_SIGNATURE="$(${PHP_BIN_OPT_R} "echo hash_file('SHA384', 'composer-setup.php');")"

	if [ "$EXPECTED_SIGNATURE" != "$ACTUAL_SIGNATURE" ]
	then
		>&2 k_print_result 'ERROR: Invalid installer signature'
		rm composer-setup.php
		exit 1
	fi

	local COMPOSER_INSTALL_DIR=/bin
	local COMPOSER_ALIAS_DIR=/usr/local/bin
	local COMPOSER_BIN_NAME=composer
	${PHP_BIN} composer-setup.php --filename=${COMPOSER_BIN_NAME} --install-dir=${COMPOSER_INSTALL_DIR}
	RESULT=$?
	rm composer-setup.php

	# make a symbolic link to a file in the local directory.
	ln -fs ${COMPOSER_INSTALL_DIR}/${COMPOSER_BIN_NAME} ${COMPOSER_ALIAS_DIR}/${COMPOSER_BIN_NAME} 
	return $RESULT
}

function k_rails_init() {
	export RAILS_DB='mysql'

	if [ `yum repolist all | grep passenger | wc -l` -eq 0 ]; then
		curl --fail -sSLo /etc/yum.repos.d/passenger.repo https://oss-binaries.phusionpassenger.com/yum/definitions/el-passenger.repo
	fi
	# depend on mod_passenger
	yum install -y mod_passenger
	yum install -y kusanagi-passenger
	yum install -y nodejs

	if [ ! -f /etc/httpd/modules/mod_passenger.so ]; then
		ln -s /usr/lib64/httpd/modules/mod_passenger.so /etc/httpd/modules/mod_passenger.so
	fi
	sed -i -e 's;/usr/lib64/httpd/modules/mod_passenger.so;modules/mod_passenger.so;' /etc/httpd/conf.modules.d/10-passenger.conf
	yum -y install libxml2 libxslt libxml2-devel libxslt-devel gmp-devel
}

# install or remove kusanagi addon
function k_addon () {
	shift
	case "${1}" in
		"install" | "remove")
			EXISTS_FUNC="k_addon_${1}_${2}"
			if k_is_fuction_exists ; then
				if k_addon_${1}_${2} ; then
					k_print_info "add-on ${1} was successful"
				else
					k_print_error "add-on ${1} was aborted"
					exit 1
				fi
			else
				k_print_error "${2} is invalid add-on name"
				k_print_error "Please specify a valid add-on name"
				exit 1
			fi
			;;
		*)
			k_print_notice "Please specify either 'install' or 'remove'"
			exit 1
			;;
	esac
}

function k_upgrade () {
	local FORCE_UPGRADE

	shift
	if [ "${2}" = '--force' ]; then
		FORCE_UPGRADE=true
	else
		FORCE_UPGRADE=false
	fi

	case "${1}" in
		"mariadb")
			k_mariadb_upgrade ${FORCE_UPGRADE}
		;;
		*)
			echo $(eval_gettext "Please the name you want to upgrade.")
			exit 1
		;;
	esac
}

# upgrade MariaDB
function k_mariadb_upgrade() {

	local is_force

	is_force=$1

	if is_upgraded_mariadb ; then
		echo $(eval_gettext "MariaDB is already upgraded.")
		return 0
	else
		echo $(eval_gettext "Upgrade MariaDB.")
		echo
	fi

	local MY_CONF_DIR=/etc/my.cnf.d

	# if current version 10.0
	if [ `get_mariadb_version` = '10.0' ] ; then

		if ! ${is_force} ; then
			echo $(eval_gettext "Did you take a backup before upgrading from MariaDB 10.0 to MariaDB 10.1 ? [y/N]")
			if ! k_is_yes ; then
				echo $(eval_gettext "see https://mariadb.com/kb/en/library/upgrading-from-mariadb-100-to-mariadb-101/.")
				exit 1
			fi

			echo
			echo $(eval_gettext "Is MariaDB Galera Cluster running ? [y/N]")
			if k_is_yes ; then
				echo
				echo $(eval_gettext "Did you check the following steps ? [y/N]")
				echo $(eval_gettext "https://mariadb.com/kb/en/library/upgrading-from-mariadb-galera-cluster-100-to-mariadb-101/")
				if ! k_is_yes ; then
					echo
					echo $(eval_gettext "Please see the above URL.")
					exit 1
				fi
			fi
		fi

		# check whether the postfix is currently up or down.
		local RUN_POSTFIX
		if systemctl is-active postfix > /dev/null  ; then
			RUN_POSTFIX=true
		else
			RUN_POSTFIX=false
		fi

		k_monit monit off

		yum remove -y 'MariaDB*' galera

		# upgrade repo file.
		sed -i -e 's/10.0/10.1/g' ${MARIADB_REPO_FILE}

		yum clean all > /dev/null

		yum install -y MariaDB-devel MariaDB-client MariaDB-server

		# restore mariadb files.
		RESTORE_CONF=${MY_CONF_DIR}
		restore_rpm_conf_files
		RESTORE_CONF='/etc/logrotate.d/mysql'
		restore_rpm_conf_files

		systemctl restart mysql

		k_monit monit on

		upgrade_existing_mariadb_tables

		yum -y install postfix
		RESTORE_CONF='/etc/postfix'
		restore_rpm_conf_files
		if $RUN_POSTFIX ; then
			systemctl start postfix
		fi
	fi

	if is_mroonga_activated ; then
		# Choosing whether to upgrade Mroonga.
		echo -n $(eval_gettext "Do you want to upgrade Mroonga ?: [y/N]")
		if k_is_yes ; then
			upgrade_mroonga
		else
			# Choosing whether to uninstall Mroonga.
			echo -n $(eval_gettext "Do you want to uninstall Mroonga ?: [y/N]")
			if k_is_yes ; then
				remove_mroonga
			fi
		fi
	else
		# Choosing whether to install Mroonga.
		echo -n $(eval_gettext "Do you want to install Mroonga ?: [y/N]")
		if k_is_yes ; then
			if install_mroonga ; then
				echo -n $(eval_gettext "Mroonga installation has succeeded.")
			else
				echo -n $(eval_gettext "Mroonga installation has failed.")
			fi
			echo
		fi
	fi
}

function is_upgraded_mariadb () {
	if [ `get_mariadb_version` = "${MARIADB_LATEST_VERSION}" ] ; then
		return 0
	else
		return 1
	fi
}

function upgrade_existing_mariadb_tables () {
	ROOTPATH=`get_db_root_password`
	mysql_upgrade -u root -p${ROOTPATH}
}

function get_mariadb_version () {
	local version
	version=`mysql -V | grep -oE '10.[0-9]'`
	echo ${version}
}

# install mroonga plugin
function k_addon_install_mroonga () {

	if ! is_upgraded_mariadb ; then
		echo $(eval_gettext "Please upgrade MariaDB. Try running 'kusanagi upgrade mariadb'")
		return 1
	fi

	local RET
	yum install -y https://packages.groonga.org/centos/groonga-release-1.3.0-1.noarch.rpm
	yum install -y mariadb-10.1-mroonga groonga-tokenizer-mecab
	systemctl restart mysql

	if ! is_mroonga_activated ; then
		# http://mroonga.org/ja/docs/install/centos.html#centos-7-with-mariadb-10-1-package
		ROOTPATH=`get_db_root_password`
		mysql -u root -p${ROOTPATH} < /usr/share/mroonga/install.sql
		RET=$?

		return ${RET}
	fi

	return 0
}

# uninstall mroonga plugin
function k_addon_remove_mroonga () {
	local RET
	if is_mroonga_activated ; then
		if is_mroonga_wp_plugin_activated ; then
			RET=1
		else
			# http://mroonga.org/ja/docs/install/centos.html#centos-7-with-mariadb-10-1-package
			ROOTPATH=`get_db_root_password`
			mysql -u root -p${ROOTPATH} < /usr/share/mroonga/uninstall.sql
			RET=$?
		fi

		return ${RET}
	fi

	return 0
}

# check if the mroonga plugin is activated
function is_mroonga_activated () {
	local RESULT
	ROOTPATH=`get_db_root_password`
	RESULT=`mysql -u root -p${ROOTPATH} -e 'SHOW PLUGINS' 2> /dev/null | grep -i Mroonga | awk '{print $2}'`
	if [ "${RESULT}" = 'ACTIVE' ]; then
		return 0;
	else
		return 1;
	fi
}

# check if the WordPress mroonga plugin is activated
function is_mroonga_wp_plugin_activated () {

	local _profile RET
	readonly local MROONGA_EXISTS=2

	for _profile in $(cd /home/kusanagi; ls)
	do
		(
			k_read_profile $_profile dont 2> /dev/null
			if [[ $KUSANAGI_TYPE = 'WordPress' ]]; then
				if wp plugin status mroonga --path=$KUSANAGI_DIR/DocumentRoot 2> /dev/null | grep -Ei 'Status:\s*Active'  > /dev/null ; then
					echo $(eval_gettext "Mroonga WordPress plugin is activated.") >&2
					echo $(eval_gettext "Please deactivate mroonga plugin from '$_profile' Profile.") >&2
					exit ${MROONGA_EXISTS}
				fi
			fi
		)
		RET=$?
		if [[ $RET -eq $MROONGA_EXISTS ]]; then
			return 0
		fi
	done

	# not activated mroonga
	return 1
}

# upgrade mroonga plugin
function upgrade_mroonga () {
	systemctl restart mysql
	ROOTPATH=`get_db_root_password`
	mysql -u root -p${ROOTPATH} < /usr/share/mroonga/uninstall.sql
	mysql -u root -p${ROOTPATH} < /usr/share/mroonga/install.sql
}

# check if go is installed
function is_go_installed () {
	if [[ -d /usr/local/go ]]; then
		return 0
	else
		return 1
	fi
}

# install go
function k_addon_install_go () {

	local DO_INSTALL=1

	if is_go_installed ; then
		if ! k_is_reinstall "go" ; then
			DO_INSTALL=0
		fi
	fi

	if [[ $DO_INSTALL -eq 1 ]]; then
		if [[ -d /usr/local/src/go ]]; then
			\rm -rf /usr/local/src/go
		fi

		mkdir /usr/local/src/go
		cd /usr/local/src/go

		yum -y install sqlite git gcc make wget > /dev/nyll
		if ! wget https://dl.google.com/go/go${GO_LATEST_VERSION}.linux-amd64.tar.gz ; then
			return 1
		fi
		tar -C /usr/local -xzf go${GO_LATEST_VERSION}.linux-amd64.tar.gz
		if [[ ! -f "${GO_ENV}" ]]; then
			cat <<- '_EOT_' > ${GO_ENV}
			export GOROOT=/usr/local/go
			export GOPATH=$HOME/go
			export PATH=$PATH:$GOROOT/bin:$GOPATH/bin
			_EOT_
		fi
		
		source ${GO_ENV}

		if [[ ! -d "${GOPATH}" ]]; then
			mkdir "$GOPATH"
		fi
	fi

	k_print_go_usage
}

# uninstall go
function k_addon_remove_go () {
	if [[ -d "${GOROOT}" ]]; then
		\rm -rf ${GOROOT}
	fi

	if [[ -d "${GOPATH}" ]]; then
		\rm -rf "$GOPATH"
	fi

	if [[ -f "${GO_ENV}" ]]; then
		\rm ${GO_ENV}
	fi
}

# check if vuls is installed
function is_vuls_installed () {
	if which vuls > /dev/null 2>&1 ; then
		return 0
	else
		return 1
	fi
}

# install vuls
function k_addon_install_vuls () {

	if is_vuls_installed ; then
		if ! k_is_reinstall "vuls" ; then
			k_print_vuls_usage
			return 0
		fi
	fi

	# depends on go lang.
	if ! k_addon_install_go ; then
		return 1
	fi

	local DO_INSTALL=1

	if which go-cve-dictionary > /dev/null 2>&1 ; then
		if ! k_is_reinstall "go-cve-dictionary" ; then
			DO_INSTALL=0
		fi
	fi

	local VULS_WORK_DIR=$GOPATH/src/github.com/future-architect
	local VULS_PKG_DIR=$GOPATH/pkg/linux_amd64/github.com/future-architect/vuls/
	local VULS_DEP_WORK_DIR=$GOPATH/src/github.com/kotakanbe

	if [[ ! -d $VULS_WORK_DIR ]]; then
		mkdir -p $VULS_WORK_DIR
	fi

	if [[ ! -d $VULS_DEP_WORK_DIR ]]; then
		mkdir -p $VULS_DEP_WORK_DIR
	fi

	if [[ $DO_INSTALL -eq 1 ]]; then
		if [[ ! -d "$VULS_LOG_DIR" ]]; then
			mkdir "$VULS_LOG_DIR"
			chmod 700 "$VULS_LOG_DIR"
		fi
		if [[ -d $VULS_DEP_WORK_DIR/go-cve-dictionary ]]; then
			\rm -rf $VULS_DEP_WORK_DIR/go-cve-dictionary
		fi
		cd $VULS_DEP_WORK_DIR
		git clone https://github.com/kotakanbe/go-cve-dictionary.git
		cd go-cve-dictionary
		make install
	fi

	DO_INSTALL=1

	if which goval-dictionary > /dev/null 2>&1 ; then
		if ! k_is_reinstall "goval-dictionary" ; then
			DO_INSTALL=0
		fi
	fi

	if [[ $DO_INSTALL -eq 1 ]]; then
		if [[ -d $VULS_DEP_WORK_DIR/goval-dictionary ]]; then
			\rm -rf $VULS_DEP_WORK_DIR/goval-dictionary
		fi
		cd $VULS_DEP_WORK_DIR
		git clone https://github.com/kotakanbe/goval-dictionary.git
		cd goval-dictionary
		make install
	fi

	if [[ -d $VULS_WORK_DIR/vuls ]]; then
		\rm -rf $VULS_WORK_DIR/vuls
	fi

	if [[ -d $VULS_PKG_DIR ]]; then
		\rm -rf $VULS_PKG_DIR
	fi

	cd $VULS_WORK_DIR
	git clone https://github.com/future-architect/vuls.git
	cd vuls
	make install

	cd $HOME

	# for fast scan
	k_yum_install 'yum-utils'
	# for deep scan
	k_yum_install 'yum-plugin-changelog'

	if [[ ! -f $VULS_CONF ]]; then
		cat <<- '_EOT_' > $VULS_CONF
		[servers]

		[servers.localhost]
		host = "127.0.0.1"
		port = "local"

		[email]
		smtpAddr      = "localhost"
		smtpPort      = "25"
		from          = "from@example.com"
		to            = ["to@example.com"]
		subjectPrefix = "[vuls]"

		_EOT_
	fi

	cd $HOME

	# fetch cve database
	go-cve-dictionary fetchnvd -last2y

	if echo $LANG | grep 'ja_JP' > /dev/null ; then
		 go-cve-dictionary fetchjvn -latest
	fi

	# fetch redhat oval
	goval-dictionary fetch-redhat 7

	k_print_vuls_usage
}

# uninstall vuls
function k_addon_remove_vuls () {

	if [[ -d "$VULS_LOG_DIR" ]]; then
		\rm -rf "$VULS_LOG_DIR"
	fi

	if [[ -d $VULS_DEP_WORK_DIR/go-cve-dictionary ]]; then
		\rm -rf $VULS_DEP_WORK_DIR/go-cve-dictionary
	fi

	if [[ -d $VULS_DEP_WORK_DIR/goval-dictionary ]]; then
		\rm -rf $VULS_DEP_WORK_DIR/goval-dictionary
	fi

	if [[ -d $VULS_WORK_DIR/vuls ]]; then
		\rm -rf $VULS_WORK_DIR/vuls
		\rm -rf $VULS_PKG_DIR
	fi

	if [[ -f $HOME/cve.sqlite3 ]]; then
		\rm -f $HOME/cve.sqlite3
	fi

	if [[ -f $HOME/oval.sqlite3 ]]; then
		\rm -f $HOME/oval.sqlite3
	fi

	local BIN
	for BIN in goval-dictionary go-cve-dictionary vuls
	do
		if [[ -f $GOPATH/bin/$BIN ]]; then
			\rm -f $GOPATH/bin/$BIN
		fi
	done

	if [[ -f $VULS_CONF ]]; then
		rm $VULS_CONF
	fi
}

# install tripwire
function is_tripwire_installed () {
	if rpm -q "tripwire" > /dev/null 2>&1 ; then
		return 0
	else
		return 1
	fi
}

# check if tripwire is installed
function k_addon_install_tripwire () {

	k_yum_install "tripwire"

	tripwire-setup-keyfiles

	ku-tripwire-optimize

	twadmin --create-polfile --site-keyfile $TRIPWIRE_SITE_KEY $TRIPWIRE_POL_FILE

	tripwire --init

	k_print_tripwire_usage
}

# uninstall tripwire
function k_addon_remove_tripwire () {
	yum -y remove tripwire
}

# check if suricata is installed
function is_suricata_installed () {
	if rpm -q "suricata" > /dev/null 2>&1 ; then
		return 0
	else
		return 1
	fi
}

# check if suricata is activated
function is_suricata_activated () {
	if [[ $(k_is_active suricata) -eq 0 ]] ; then
		return 0
	else
		return 1
	fi
}

# install suricata
function k_addon_install_suricata () {

	k_yum_install "suricata"
	k_yum_install "jq"

	local IFACES=$(ls /sys/class/net)
	local IFACE_COUNTS=$(echo "${IFACES}" | wc -l)

	# current interface to sniff packets
	local CURRENT_IFACE=$(cat ${SURICATA_SYS_CONF} | grep 'OPTIONS=' | grep -oE '\-i[[:blank:]]+[[:alnum:]]+' | awk '{print $2}')

	while :
	do
		k_print_yellow "Please tell me the interface card you would like to use to sniff packets from. [1-${IFACE_COUNTS}]"
		local IFACE_ARR=()
		local IFACE
		local IDX=1
		for IFACE in ${IFACES}
		do
			IFACE_ARR+=( ${IFACE} )
			if [[ "$CURRENT_IFACE" = "${IFACE}" ]]; then
				k_print_green "($IDX) : ${IFACE} (current)"
			else
				echo "($IDX) : ${IFACE} "
			fi
			IDX=$((++IDX))
		done
		local NUMBER
		read NUMBER
		if [[ $NUMBER -gt 0 ]] && [[ $NUMBER -le $IFACE_COUNTS ]]; then
			local CHOOSE_IDX=$(( NUMBER - 1 ))
			echo "You choose: ${IFACE_ARR[${CHOOSE_IDX}]}"
			sed -i "s;OPTIONS=\"-i[ \t]\+[^ \t]\+\(.*\);OPTIONS=\"-i ${IFACE_ARR[${CHOOSE_IDX}]}\1;" ${SURICATA_SYS_CONF}

			ku-suricata-optimize

			if systemctl restart suricata ; then
				if ! systemctl is-enabled suricata ; then
					systemctl enable suricata
				fi
			fi
			break
		fi
	done

	k_print_suricata_usage
}

# uninstall sucicata
function k_addon_remove_suricata () {
	yum -y remove suricata
}

function k_print_go_usage () {
	k_print_yellow "
	If you cannot use golang in the current shell,
	run the following command.

	$ source ${GO_ENV}
	"
}

function k_print_vuls_usage () {
	k_print_yellow "
	For more information about Vuls, please refer to the link below
	https://vuls.io/
	"
}

function k_print_tripwire_usage () {
	k_print_yellow "

	If you run the following command, check the file or directory integrity.
	$ tripwire --check

	For more information about Open Source Tripwire, please refer to the link below
	https://github.com/Tripwire/tripwire-open-source
	"
}

function k_print_suricata_usage () {
	k_print_yellow "
	For more information about Suricata, please refer to the link below
	https://suricata.readthedocs.io/en/latest/
	"
}


# backup file to the user's home directory
function backup_file () {
	local BK_SAVENAME

	if [ -n "${BACKUP_FILE}" ]; then
		if [ -f "${BACKUP_FILE}" ]; then
			BK_SAVENAME=`echo ${BACKUP_FILE}.org | tr '/' '-' | sed -e 's/^-//'`
			cp -p ${BACKUP_FILE} ~/${BK_SAVENAME}
		else
			echo $(eval_gettext "backup target does not exist.")
		fi
	else
		echo $(eval_gettext "backup target is not specified.")
	fi

	BACKUP_FILE=''
}

# the following configuration files are restored from .rpmsave
function restore_rpm_conf_files () {
	local DIRNAME ORG_BASENAME SAVE_BASENAME BK_SAVENAME

	if [ -n "${RESTORE_CONF}" ]; then

		if [ -d "${RESTORE_CONF}" ]; then
			DIRNAME=${RESTORE_CONF}
		elif [ -f "${RESTORE_CONF}" ]; then
			DIRNAME=$(dirname ${RESTORE_CONF})
		fi

		# ensure training slash
		DIRNAME=${DIRNAME%/}/

		for f in $(ls ${DIRNAME})
		do
			if echo ${f} | grep '\.rpmsave' > /dev/null; then
				ORG_BASENAME=$(basename ${f%.rpmsave})
				SAVE_BASENAME=$(basename ${f})
				# save *.rpmsave files to the user's home directory.
				BK_SAVENAME=`echo ${DIRNAME}${ORG_BASENAME}.org | tr '/' '-' | sed -e 's/^-//'`

				if [ -f "${DIRNAME}${ORG_BASENAME}" ]; then
					cp -p "${DIRNAME}${ORG_BASENAME}" ~/${BK_SAVENAME}
					mv -f ${DIRNAME}${SAVE_BASENAME} ${DIRNAME}${ORG_BASENAME}
				else
					# in the case of deleted original file.
					mv -f ${DIRNAME}${SAVE_BASENAME} ~/${BK_SAVENAME}
				fi

			fi

		done
	else
		echo $(eval_gettext "restore target is not specified.")
	fi
	RESTORE_CONF=''
}

# initialize database system
function k_db_init () {

	local DB_SYSTEM=$1
	local KUSANAGI_DBPASS=$2
	local VERSION=$3

	if [ -z "$DB_SYSTEM" ]; then
		local DB
		while :
		do
			echo $(eval_gettext "Then, Please tell me your Database system.")
			echo $(eval_gettext "1) MariaDB(Default)")
			echo $(eval_gettext "2) PostgreSQL")
			echo
			echo -n $(eval_gettext "Which you using?(1): ")
			read DB
			case "$DB" in
				""|"1" )
					echo
					echo $(eval_gettext "You choose: MariaDB")
					DB_SYSTEM=mariadb
					break
					;;
				"2" )
					echo
					echo $(eval_gettext "You choose: PostgreSQL")
					DB_SYSTEM=psql
					break
					;;
				* )
					;;
			esac
		done
	fi

	case "$DB_SYSTEM" in
		'mariadb')
			if ! k_mariadb_init "$KUSANAGI_DBPASS" ; then
				return 1
			fi
			# Upgrade MariaDB to 10.1
			k_mariadb_upgrade "true"
			;;
		'psql')
			if ! k_psql_init "$KUSANAGI_DBPASS" "$VERSION" ; then
				return 1
			fi
			;;
		*)
			echo $(eval_gettext "Invalid name for a database system.")
			return 1
			;;
	esac

	# buffer settings for Database
	if ! k_configure ; then
		return 1
	fi
}

# initialize MariaDB
function k_mariadb_init() {

	local RET DB_ROOT_PASSWORD PASS1 PASS2
	local KUSANAGI_DBPASS=$1

	DB_ROOT_PASSWORD=`get_db_root_password`
	if [ "$DB_ROOT_PASSWORD" = "" ]; then
		echo $(eval_gettext "Can't get DB root password.")
		return 1
	fi

	# deactivate other database systems.
	k_deactivate_psql

	# activate MariaDB
	if k_activate_mariadb ; then
		if [ -z "$KUSANAGI_DBPASS" ] ; then
			RET=""
			while [ "$RET" = "" ]; do
				echo
				echo $(eval_gettext "Enter MySQL root password. Use [a-zA-Z0-9.!#%+_-] 8 characters minimum.")
				read -s PASS1
				echo $(eval_gettext "Re-type MySQL root password.")
				read -s PASS2
				if [ "$PASS1" = "$PASS2" ] && \
					[ 0 -eq $(check_db_root_password "$PASS1") ] ; then
					KUSANAGI_DBPASS="$PASS1"
					break
				fi
			done
		fi
		RET=$(set_db_root_password "$DB_ROOT_PASSWORD" "$KUSANAGI_DBPASS")
		echo $RET
		if [ "$RET" = "Failed." ]; then
			return 1
		fi
		echo $(eval_gettext "Change MySQL root password.")
	else
		return 1;
	fi
}

# initialize PostgreSQL
function k_psql_init() {

	local KUSANAGI_DBPASS=$1
	local VERSION=$2

	if [ -z "$VERSION" ]; then
		local VERSION
		while :
		do
			echo $(eval_gettext "Then, Please tell me your PostgreSQL version.")
			echo $(eval_gettext "1) PostgreSQL9.6")
			echo
			echo -n $(eval_gettext "Which you using?(1): ")
			read VERSION
			case "$VERSION" in
				"1" )
					echo
					echo $(eval_gettext "You choose: PostgreSQL9.6")
					VERSION=psql96
					break
					;;
				* )
					;;
			esac
		done
	fi

	case "$VERSION" in
		'psql96')
			if ! k_psql96_init "$KUSANAGI_DBPASS" ; then
				return 1
			fi
			;;
		*)
			echo $(eval_gettext "Invalid name for the PostgreSQL version.")
			return 1
			;;
		*)
	esac
}

# Initialize PostgreSQL9.6
function k_psql96_init() {

	local RET DB_ROOT_PASSWORD PASS1 PASS2
	local KUSANAGI_DBPASS=$1

	yum clean all > /dev/null

	if ! rpm -q pgdg-centos96 > /dev/null ; then
		cd /usr/local/src
		if ! curl --retry 3 --fail -sSLo pgdg-centos96-9.6-3.noarch.rpm https://download.postgresql.org/pub/repos/yum/9.6/redhat/rhel-7-x86_64/pgdg-centos96-9.6-3.noarch.rpm ; then
			echo $(eval_gettext "Download Error!")
			return 1;
		else
			yum -y install pgdg-centos96-9.6-3.noarch.rpm
		fi
	fi

	if ! rpm -q postgresql96-server > /dev/null ; then
		yum -y install postgresql96-server
	fi

	local PG_DATA_DIR=/var/lib/pgsql/9.6/data
	local PG_BIN_DIR=/usr/pgsql-9.6/bin

	if [ ! -f ${PG_DATA_DIR}/PG_VERSION ]; then
		export PGSETUP_INITDB_OPTIONS="--encoding=UTF-8 --no-locale"
		if ! $PG_BIN_DIR/postgresql96-setup initdb ; then
			return 1
		fi
	fi

	# change ident authentication into md5
	sed -i'.org' -E '/ident$/s/ident/md5/g' ${PG_DATA_DIR}/pg_hba.conf

	# server config
	sed -i -E 's/synchronous_commit.*/synchronous_commit = off/' ${PG_DATA_DIR}/postgresql.conf
	# max_connections should be greater than max_pool * num_init_children
	sed -i -E 's/max_connections.*/max_connections = 900/' ${PG_DATA_DIR}/postgresql.conf

	# install pg-pool2
	if ! rpm -q pgpool-II-pg10 > /dev/null ; then
		yum install -y http://www.pgpool.net/yum/rpms/3.7/redhat/rhel-7-x86_64/pgpool-II-pg10-3.7.2-1pgdg.rhel7.x86_64.rpm
	fi

	local PG_POOL_CONF=/etc/pgpool-II/pgpool.conf

	if [ ! -f ${PG_POOL_CONF} ]; then
		echo $(eval_gettext "Could not find ${PG_POOL_CONF}")
		return 1;
	fi

	local PG_POOL_LOG_DIR=/var/log/pgpool
	mkdir -p ${PG_POOL_LOG_DIR}
	chown postgres:postgres ${PG_POOL_LOG_DIR}

	# pg pool settings
	sed -i -E 's/memory_cache_enabled.*/memory_cache_enabled = on/' ${PG_POOL_CONF}
	sed -i    's;/tmp;/var/run/postgresql;g' ${PG_POOL_CONF}
	sed -i -E 's/num_init_children.*/num_init_children = 100/' ${PG_POOL_CONF}
	sed -i -E 's/child_life_time.*/child_life_time = 0/' ${PG_POOL_CONF}
	sed -i -E 's/serialize_accept.*/serialize_accept = on/' ${PG_POOL_CONF}

	# deactivate other database systems.
	k_deactivate_mariadb

	# activate PostgreSQL
	if k_activate_psql ; then
		ln -fs $PG_BIN_DIR/pgbench /usr/local/bin/pgbench
		if [ -z "$KUSANAGI_DBPASS" ] ; then
			RET=""
			while [ "$RET" = "" ]; do
				echo
				echo $(eval_gettext "Enter PostgreSQL postgres password. Use [a-zA-Z0-9.!#%+_-] 8 characters minimum.")
				read -s PASS1
				echo $(eval_gettext "Re-type PostgreSQL postgres password.")
				read -s PASS2
				if [ "$PASS1" = "$PASS2" ] && \
					[ 0 -eq $(check_db_root_password "$PASS1") ] ; then
					KUSANAGI_DBPASS="$PASS1"
					break
				fi
			done
		fi
		set_db_postgres_password "$KUSANAGI_DBPASS"
	else
		return 1
	fi
}

function k_target() {
	if [ -z "${2}" ]; then
		k_print_green "$PROFILE"
		if [ -f $PROFILECONF ] ; then
			local line _PROFILE
			cat ${PROFILECONF} | while read line
			do
				_PROFILE=
				if [[ "${line}" =~ ^\[([^\]]+)\] ]]; then
					_PROFILE=${BASH_REMATCH[1]}
				fi
				if [ -n "$_PROFILE" ] && [ "$_PROFILE" != "$PROFILE" ]; then
					echo ${_PROFILE}
				fi
			done
		fi
	elif [[ "$2" =~ ^[a-zA-Z0-9._-]{3,24}$ ]]; then
		PROFILE=$2
		k_read_profile $PROFILE dont
		#KUSANAGI_DIR="/home/kusanagi/$2"
		case $KUSANAGI_TYPE in
			"WordPress")
				# config file check
				[ -e $KUSANAGI_DIR/DocumentRoot/wp-config.php ] || [ -e $KUSANAGI_DIR/wp-config.php ] || return
				;;
			"concrete5")
				# config file check
				 [ -d $KUSANAGI_DIR/public/concrete ] || return
				;;
			"drupal8")
				# config file is nothing
				[ -e $KUSANAGI_DIR/DocumentRoot/sites/default/settings.php ] || return
				;;
			"Rails")
				# public directry check
				[ -e $KUSANAGI_DIR/public ] || return
				;;
			"lamp")
				# DocumentRoot check
				[ -e $KUSANAGI_DIR/DocumentRoot ] || return
				;;
			*)
				return
		esac
		# change profile
		echo 'PROFILE="'$2'"' > /etc/kusanagi.conf
		echo $(eval_gettext "Target is changed to TARGET") | sed "s|TARGET|$2|"
		k_read_profile $PROFILE
	fi
}

function k_warmup() {

	local RET1=`grep 'server_name' $NGINX_HTTP | head -1 | sed 's/^\s*server_name\s*//' | sed 's/^.* //' | sed 's/\s*;\s*$//'`
	local RET2=`grep '^127.0.0.1 ' /etc/hosts | grep "$RET1"`
	if [ "$RET2" != "" ]; then
		if [ "$2" = "--extreme" ] && [ $(k_is_enabled hhvm)  -eq "0" ] ; then
			echo $(eval_gettext "Creating Byte Code. It takes a lot of time. Please wait.")
			echo $(eval_gettext "If this feauture doesn't works well, Try without '--extreme' option.")
			echo $(eval_gettext "And... If you change PHP files, Please run this command again.")
			/usr/bin/hhvm-repo-mode enable $KUSANAGI_DIR/DocumentRoot/
		else
			/usr/bin/hhvm-repo-mode disable
			echo -n "http://$RET1/	"
			for i in `seq 12`; do
				echo -n "#"
				curl "http://$RET1/" 1> /dev/null 2> /dev/null
			done
			echo
		fi
	fi
}


function k_update() {
	local ARGS=() YESFLAG= i=
	shift
	for i in "$@"
	do
		if [ "$i" = '-y' ] ; then
			YESFLAG=1
		else
			ARGS=("${ARGS[@]}" "$i")
		fi
	done

	case "${ARGS[0]}" in

	plugin)

		if [ -e $KUSANAGI_DIR/DocumentRoot/wp-content/mu-plugins/wp-kusanagi.php ] && \
			[ -e $KUSANAGI_DIR/DocumentRoot/wp-content/mu-plugins/kusanagi-wp-configure.php ]; then

			local MU_PLUGINS_DIR="$KUSANAGI_DIR/DocumentRoot/wp-content/mu-plugins"
			local RESOURCE_DIR="/usr/lib/kusanagi/resource/DocumentRoot/wp-content/mu-plugins"

			local CUR_PLUGIN_VER=`grep -e "Version: [0-9.]" $MU_PLUGINS_DIR/wp-kusanagi.php | sed -e "s/Version: \([0-9.]\)/\1/"`
			local LAT_PLUGIN_VER=`grep -e "Version: [0-9.]" $RESOURCE_DIR/wp-kusanagi.php | sed -e "s/Version: \([0-9.]\)/\1/"`
			local RET_PLUGIN=$(k_ver_compare $LAT_PLUGIN_VER $CUR_PLUGIN_VER; echo $?)

			local CUR_CONFIG_VER=`grep -e "Version: [0-9.]" $MU_PLUGINS_DIR/kusanagi-wp-configure.php | sed -e "s/Version: \([0-9.]\)/\1/"`
			local LAT_CONFIG_VER=`grep -e "Version: [0-9.]" $RESOURCE_DIR/kusanagi-wp-configure.php | sed -e "s/Version: \([0-9.]\)/\1/"`
			local RET_CONFIG=$(k_ver_compare $LAT_CONFIG_VER $CUR_CONFIG_VER; echo $?)

			if [ 1 -eq "$RET_PLUGIN" -o 1 -eq "$RET_CONFIG" ] && [ -z "$YESFLAG" ] ; then
				echo "Target: $PROFILE"
				echo -n $(eval_gettext "Upgrade ok?[y/N]: ")" "
				read is_upgrade
				case $is_upgrade in

				y)
					break
				;;
				*)
						echo $(eval_gettext "Abort.")
					exit 1
					break
				;;
				esac
			fi

			if [ 1 -eq "$RET_PLUGIN" ]; then
				echo $(eval_gettext "Update KUSANAGI plugin \$CUR_PLUGIN_VER to \$LAT_PLUGIN_VER")

				/bin/cp -f $RESOURCE_DIR/wp-kusanagi.php $MU_PLUGINS_DIR/wp-kusanagi.php
				chown kusanagi.kusanagi $MU_PLUGINS_DIR/wp-kusanagi.php
				/bin/cp -rpf $RESOURCE_DIR/kusanagi-core $MU_PLUGINS_DIR
				chown -R kusanagi.kusanagi $MU_PLUGINS_DIR/kusanagi-core
				/bin/cp -f /usr/lib/kusanagi/resource/tools/bcache.clear.php $KUSANAGI_DIR/tools/bcache.clear.php
				chown -R kusanagi.kusanagi $KUSANAGI_DIR/tools/bcache.clear.php
			else
				echo $(eval_gettext "KUSANAGI plugin is already latest version.")
			fi

			if [ 1 -eq "$RET_CONFIG" ]; then
				echo $(eval_gettext "Update KUSANAGI configure plugin \$CUR_CONFIG_VER to \$LAT_CONFIG_VER")

				/bin/cp -f $RESOURCE_DIR/kusanagi-wp-configure.php $MU_PLUGINS_DIR/kusanagi-wp-configure.php
				chown kusanagi.kusanagi $MU_PLUGINS_DIR/kusanagi-wp-configure.php
			else
				echo $(eval_gettext "KUSANAGI configure plugin is already latest version.")
			fi

		else
			echo $(eval_gettext "Plugin files not found. Noting to do.")
		fi

	;;
	cert)
		if [ -e $CERTBOT ]; then
			local CMD="$CERTBOT renew --quiet --renew-hook /usr/bin/ct-submit.sh "
			for i in nginx httpd
			do
				if [ 0 -eq $(k_is_enabled $i) ] ; then
					$CMD --post-hook "systemctl reload $i"
					k_monit_reloadmonitor
					return
				fi
			done
		fi
	;;
	*)
	break;;

	esac
}

function k_fcache() {

	##############################
	#                            #
	# do not use shell wild card #
	#                            #
	##############################

	case "${2}" in

	on)
		echo $(eval_gettext "Turning on")
		sed -i "s/set\s*\$do_not_cache\s*1\s*;\s*#\+\s*page\s*cache/set \$do_not_cache 0; ## page cache/" $NGINX_HTTP && sed -i "s/set\s*\$do_not_cache\s*1\s*;\s*#\+\s*page\s*cache/set \$do_not_cache 0; ## page cache/" $NGINX_HTTPS
	;;
	off)
		echo $(eval_gettext "Turning off")
		sed -i "s/set\s*\$do_not_cache\s*0\s*;\s*#\+\s*page\s*cache/set \$do_not_cache 1; ## page cache/" $NGINX_HTTP
		sed -i "s/set\s*\$do_not_cache\s*0\s*;\s*#\+\s*page\s*cache/set \$do_not_cache 1; ## page cache/" $NGINX_HTTPS
	;;
	clear)
		if [ -d $NGINX_CACHE_DIR ]; then
			OWNER=`ls -dl $NGINX_CACHE_DIR | awk '{ print $3}'`
			NUM_DIR=`ls -dl $NGINX_CACHE_DIR | wc -l`
			if [ "$OWNER" = "httpd" ] && [ "$NUM_DIR" = "1" ]; then
				local CACHE_PATH="$3"
				local MULTI_BYTES=`echo $CACHE_PATH | grep -o -P "[^\x00-\x7F]"`
				if [ -n "${MULTI_BYTES}" ]; then
					for MULTI_BYTE in $(echo ${MULTI_BYTES}); do
						local ENCODED=`echo ${MULTI_BYTE} | nkf -WwMQ | tr = %`
						CACHE_PATH=`echo "${CACHE_PATH}" | sed -e "s/${MULTI_BYTE}/${ENCODED}/g"`
					done
				fi
				if [ -n "$CACHE_PATH" ]; then
					local IFS=$'\n'
					local MODE="$4"
					if [[ -n $MODE ]] && [[ $MODE != '--dryrun' ]]; then
						echo $(eval_gettext "cache clear path option only '--dryrun'")
						return 1
					fi
					for match in $(grep -i -a -r -m 1 -E "^KEY.*:https?://${KUSANAGI_FQDN}${CACHE_PATH}" ${NGINX_CACHE_DIR}); do
						local CACHE_INFO=`echo ${match} | sed -e 's/:KEY://'`
						local CACHE_URL=`echo ${CACHE_INFO} | awk '{ print substr($0,index($0," ")+1)}'`
						local CACHE_FILE=`echo ${CACHE_INFO} | awk '{ print $1}'`
						if [[ $MODE = '--dryrun' ]]; then
							echo $(eval_gettext "INFO: ${CACHE_URL} will be deleted")
						else
							rm -f ${CACHE_FILE}
							RET_VAL=$?
							if [ ${RET_VAL} -eq 0 ]; then
								echo $(eval_gettext "SUCCESS: ${CACHE_URL} cache could be deleted")
							else
								echo $(eval_gettext "FAILURE: ${CACHE_URL} cache could not be deleted")
							fi
						fi
					done
				else
					# all clear
					for dir in $(find $NGINX_CACHE_DIR -maxdepth 1 -not -path $NGINX_CACHE_DIR); do
						rm -rf ${dir}
					done
					echo $(eval_gettext "Clearing cache")
				fi
			fi
			return
		else
			echo $(eval_gettext "Nginx cache directory(\$NGINX_CACHE_DIR) is not found.")
			return 1
		fi
	;;
	*)
		local RET=`grep -e "set[[:space:]]*\\$do_not_cache[[:space:]]*0[[:space:]]*;[[:space:]]*##[[:space:]]*page[[:space:]]*cache" $NGINX_HTTP`
		if [ "$RET" ]; then
			echo $(eval_gettext "fcache is on")
		else
			echo $(eval_gettext "fcache is off")
		fi
		return
	;;
	esac
	# restart nginx when nginx is enabled
	if [ 0 -eq $(k_is_enabled nginx) ] ; then
		k_nginx
	else
		echo $(eval_gettext "Nginx is disable and nginx do not restart.")
		return 1
	fi
}


function k_bcache() {

	##############################
	#                            #
	# do not use shell wild card #
	#                            #
	##############################

	if [ -z "$WPCONFIG" ]; then
		echo $(eval_gettext "WordPress isn't installed. Nothing to do.")
		return
	fi
	case ${2} in

	on)
		if [ -e $WPCONFIG ]; then

			echo $(eval_gettext "Turning on")
			RET=`grep -i 'WP_CACHE' $WPCONFIG | wc -l`
			if [ "$RET" = "1" ]; then
				sed -i "s/^\s*define\s*(\s*'WP_CACHE'.*$/define('WP_CACHE', true);/" $WPCONFIG
				sed -i "s/^\s*[#\/]\+\s*define\s*(\s*'WP_CACHE'.*$/define('WP_CACHE', true);/" $WPCONFIG
			else
				echo $(eval_gettext "Failed. Constant WP_CACHE defined multiple.")
			fi

		fi
	;;
	off)
		if [ -e $WPCONFIG ]; then
			echo $(eval_gettext "Turning off")
			local RET=`grep -i 'WP_CACHE' $WPCONFIG | wc -l`
			if [ "$RET" = "1" ]; then
				sed -i "s/^\s*define\s*(\s*'WP_CACHE'.*$/#define('WP_CACHE', true);/" $WPCONFIG
			else
				echo $(eval_gettext "Failed. Constant WP_CACHE defined multiple.")
			fi
		fi
	;;
	clear)
		local CACHE_PATH="$3"
		local MODE="$4"
		echo $(eval_gettext "Clearing cache")
		cd $TARGET_DIR/tools
		php ./bcache.clear.php "$CACHE_PATH" "$MODE"
	;;
	*)
		local RET=`grep -e "^[[:space:]]*define[[:space:]]*([[:space:]]*'WP_CACHE'" $WPCONFIG | grep 'true'`
		if [ "$RET" ]; then
			echo $(eval_gettext "bcache is on")
		else
			echo $(eval_gettext "bcache is off")
		fi
	;;
	esac
}

function k_zabbix() {
	case ${2} in
	on)
		echo $(eval_gettext "Try to start zabbix-agent")
		systemctl restart zabbix-agent &&systemctl enable zabbix-agent &&systemctl status zabbix-agent | head -3
	;;
	off)
		echo $(eval_gettext "Try to stop zabbix-agent")
		systemctl stop zabbix-agent &&systemctl disable zabbix-agent &&systemctl status zabbix-agent | head -3
	;;
	*)
		if [ 0 -eq $(k_is_active zabbix-agent) ] ; then
			echo $(eval_gettext "zabbix is on")
		else
			echo $(eval_gettext "zabbix is off")
		fi
	;;
	esac
}

function k_restart() {
	local _RET=0
	for service in $@ ; do
		if [ 0 -eq $(k_is_enabled $service) ] ; then
			systemctl restart $service
			_RET=$?
		else
			:
		fi
	done
	return $_RET
}

function k_reload() {
	local _RET=0
	for service in $@ ; do
		if [ 0 -eq $(k_is_enabled $service) ] ; then
			systemctl reload $service
			_RET=$?
		else
			:
		fi
	done
	return $_RET
}

function k_monit_reloadmonitor() {
	if [ 0 -ne $(k_is_enabled monit) ] ; then
		:
	elif [ 0 -eq $(k_is_enabled nginx) ]; then
		monit -g httpd unmonitor all
		monit -g nginx monitor all
	elif [ 0 -eq $(k_is_enabled httpd) ]; then
		monit -g nginx unmonitor all
		monit -g httpd monitor all
	fi
}

function k_monit() {
	local ENABLE_MONIT=$(k_is_enabled monit)
	local opt="${2,,}"
	if [ "$opt" = "on" ]; then	# comparison in lowercase.
		# start monit if monit is down.
		if [ 1 -eq $ENABLE_MONIT ]; then
			systemctl start monit && systemctl enable monit
			if [ $? -eq 0 ]; then
				echo $(eval_gettext "monit on")
				k_monit_reloadmonitor
			else
				echo $(eval_gettext "monit cannot be on")
				return 1
			fi
		else
			echo $(eval_gettext "monit is already on. Nothing to do.")
		fi
	elif [ "$opt" = "off" ]; then
		# stop monit if monit is updown.
		if [ 0 -eq $ENABLE_MONIT ]; then
			monit -g httpd unmonitor all
			monit -g nginx unmonitor all
			systemctl stop monit && systemctl disable monit && \
			echo $(eval_gettext "monit off") || echo $(eval_gettext "monit cannot be off")
		else
			echo $(eval_gettext "monit is already off. Nothing to do.")
		fi
	elif [ "$opt" = "config" ]; then
		k_read_profile ${3:-$PROFILE}
		for ITEM in "etc/monit.d/fqdn_httpd.conf" "etc/monit.d/fqdn_nginx.conf"; do
			local TARGET="/"`echo $ITEM | sed "s/fqdn/$PROFILE/"`
			local SOURCE="/usr/lib/kusanagi/resource/$ITEM"
			local BACKUPDIR="/etc/monit.d/backup"
			if [ -f $TARGET ]; then		# backup old configure file
				if [ \! -d $BACKUPDIR ] ; then
					mkdir -p $BACKUPDIR
				fi
				# ex. 2016-05-16_12:31:55
				local DATESTR=$(stat -c '%y' $TARGET | awk -F. '{print $1}'|sed 's/ /_/')
				mv ${TARGET} ${BACKUPDIR}/${TARGET##*/}.${DATESTR}
			fi
			cat $SOURCE | sed "s/profile/$PROFILE/g" > $TARGET
		done
	elif [ "$opt" = "reload" ] ; then
		echo $(eval_gettext "monit is reloaded.")
		systemctl reload monit
		if [ $? -eq 0 ] ; then
			sleep 1
			k_monit_reloadmonitor
		else
			echo $(eval_gettext "monit cannot reload")
			return 1
		fi
	else
		if [ 0 -eq $(k_is_active monit) ]; then
			echo $(eval_gettext "monit is on")
		else
			echo $(eval_gettext "monit is off")
		fi
	fi
}

function is_root_domain() {
	#USING: init,ssl option. DON'T REMOVE THIS. THIS CODE USING AND CLEANING CODE.
	#Arg: domain
	local domain=$1
	local APEX=
	echo $domain | grep "^www\." >/dev/null 2>&1
	if [ "$?" -eq 0 ] ; then
		APEX=`echo $domain | cut -c 5-` #<<<<<<< BREAK POINT >>>>>>>
		dig $APEX a | grep ".*IN.*[^SO]A.*[0-9.]\{7,15\}" >/dev/null 2>&1
		if [ "$?" -eq 1 ] ; then
			return 2
		else
			WITH_WWW=0
		fi
	else
		dig www.$domain a | grep ".*IN.*[^SO]A.*[0-9.]\{7,15\}" >/dev/null 2>&1
		if [ "$?" -eq 1 ] ; then
			return 2
		else
			APEX="$domain"
			WITH_WWW=1
		fi
	fi
	whois $APEX | grep "^NOT FOUND\|^No match" >/dev/null 2>&1
	if [ "$?" -eq 1 ] ; then
		# Apex Domain.
		if [ "$WITH_WWW" -eq 1 ] ; then
			# Pure Apex Domain.
			return 0
		else
			#With www but Remove, Apex Domain.
			return 1
		fi
	else
		# Non-Apex Domain
		return 2
	fi
}

function shrink_str() {
	local LINE=
	local CHAR=
	local s=0

	read LINE && echo $LINE
	read LINE && echo $LINE
	while read -s -N 1 CHAR
	do 
		if [ "." = "$CHAR" ] || [ "+" = "$CHAR" ] ; then
			s=$((s+1))
			if [ 0 -eq $(($s % 10)) ] ; then
				echo -n $CHAR 
			fi
		fi
	done
}

function k_generate_seckey() {
	local shrink=${1:-}
	if [ ! -d /etc/kusanagi.d/ssl ] ; then
		mkdir -p /etc/kusanagi.d/ssl
	fi
	if [ ! -e /etc/kusanagi.d/ssl/ssl_sess_ticket.key ] ; then
		openssl rand 48 > /etc/kusanagi.d/ssl_sess_ticket.key
	fi
	if [ ! -e /etc/kusanagi.d/ssl/dhparam.key ] ; then
		echo $(eval_gettext "Generating 2048bit DHE key for security") 1>&2
		if [ -n "$shrink" ] ; then
			openssl dhparam -out /etc/kusanagi.d/ssl/dhparam.key 2048 2>&1 | shrink_str
		else
			openssl dhparam -out /etc/kusanagi.d/ssl/dhparam.key 2048
		fi
		echo $(eval_gettext "Finish.") 1>&2
	fi
}

# check the user input yes or no.
function k_is_yes () {
	local input
	read -t 5 input
	case "$input" in
		 [yY][eE][sS]|[yY])
			return 0;
		;;
		*)
			return 1;
		;;
	esac
}

# check EXISTS_FUNC(shell variable) function has been defined
function k_is_fuction_exists () {
	local RET
	if [ "$(type -t ${EXISTS_FUNC})" = 'function' ] ; then
		RET=0
	else
		RET=1
	fi
	EXISTS_FUNC=''
	return ${RET}
}

# check the current KUSANAGI version.
function k_version () {
	for i in "$@" ; do
		case ${i} in
			-V|--version)
				sed -n 1p /etc/kusanagi
				return 0
			;;
		esac
	done
}

# activate MariaDB daemon
function k_activate_mariadb () {

	if ! systemctl is-enabled mariadb.service > /dev/null; then
		systemctl enable mariadb.service
	fi

	if ! systemctl is-enabled mysql.service > /dev/null; then
		systemctl enable mysql.service
	fi

	if ! systemctl restart mariadb.service ; then
		if ! systemctl restart mysql.service ; then
			echo $(eval_gettext "Can not Start MariaDB!")
			return 1
		else
			echo $(eval_gettext "Restarted the MariaDB.")
		fi
	else
		echo $(eval_gettext "Restarted the MariaDB.")
	fi
}

# deactivate MariaDB daemon
function k_deactivate_mariadb () {
	if systemctl is-enabled mysql.service > /dev/null; then
		systemctl disable mysql.service
	fi
	if systemctl is-active mysql.service > /dev/null; then
		systemctl stop mysql.service
	fi
	if systemctl is-enabled mariadb.service > /dev/null; then
		systemctl disable mariadb.service
	fi
	if systemctl is-active mariadb.service > /dev/null; then
		systemctl stop mariadb.service
	fi
}

# activate PostgreSQL daemon
function k_activate_psql () {

	local PSQL=$(systemctl list-unit-files --type=service | grep postgresql | awk '{print $1}')
	if [ -n "$PSQL" ]; then
		local SERVICE
		for SERVICE in ${PSQL}
		do
			if ! systemctl is-enabled ${SERVICE} > /dev/null; then
				systemctl enable ${SERVICE}
			fi

			if ! systemctl restart ${SERVICE} ; then
				echo $(eval_gettext "Can not Start PostgreSQL!")
				return 1
			else
				echo $(eval_gettext "Restarted the PostgreSQL server.")
			fi
		done
	fi

	if ! systemctl is-enabled pgpool.service > /dev/null; then
		systemctl enable pgpool.service
	fi

	if ! systemctl restart pgpool.service ; then
		echo $(eval_gettext "Can not Start Pgpool-II!")
		return 1
	else
		echo $(eval_gettext "Restarted the Pgpool-II.")
	fi
}

# deactivate PostgreSQL daemon
function k_deactivate_psql () {

	local PSQL=$(systemctl list-unit-files --type=service | grep postgresql | awk '{print $1}')

	if [ -n "$PSQL" ]; then
		local SERVICE
		for SERVICE in ${PSQL}
		do
			if systemctl is-enabled ${SERVICE} > /dev/null; then
				systemctl disable ${SERVICE}
			fi

			if systemctl is-active ${SERVICE} > /dev/null; then
				systemctl stop ${SERVICE}
			fi
		done
		if systemctl is-enabled pgpool.service > /dev/null; then
			systemctl disable pgpool.service
		fi

		if systemctl is-active pgpool.service > /dev/null; then
			systemctl stop pgpool.service
		fi
	fi
}

# activate auditd daemon
function k_activate_auditd () {
	if ! systemctl is-active auditd.service > /dev/null; then
		systemctl start auditd.service
		if ! systemctl is-enabled auditd.service > /dev/null; then
			systemctl enable auditd.service
		fi
	fi
}

# deactivate auditd daemon
function k_deactivate_auditd () {
	if systemctl is-active auditd.service > /dev/null; then
		# see https://bugzilla.redhat.com/show_bug.cgi?id=1026648
		service auditd stop
	fi

	if systemctl is-enabled auditd.service > /dev/null; then
		systemctl disable auditd.service
	fi
}

# get the running database daemons
function get_running_db_service () {

	if systemctl list-units --type=service --state=active 2>/dev/null | grep postgre > /dev/null 2>&1 ; then
		echo psql
	fi

	if systemctl list-units --type=service --state=active 2>/dev/null |  grep -E '(mysql|mariadb)' > /dev/null 2>&1 ; then
		echo mariadb
	fi
}

# waf method called by kusanagi command
function k_waf () {
	shift
	_k_waf $@
}

# internal waf method
function _k_waf () {
	local conf
	case "${1}" in
		"on")
			k_comment_in_all_line "${KUSANAGI_NGINX_WAF_ROOT_CONF}"
			for conf in $(k_get_provisioned_nginx_conf)
			do
				sed -i 's;#[ \t]*include[ \t]\+\(naxsi\.d/*\);include \1;g' "$conf"
			done

			# install mod_security modules
			if k_install_httpd_waf_modules ; then
				k_comment_in_all_line "${KUSANAGI_APACHE_WAF_ROOT_CONF}"
				for conf in $(k_get_provisioned_httpd_conf)
				do
					sed -i 's;#[ \t]*IncludeOptional[ \t]\+\(modsecurity\.d/.*\);IncludeOptional \1;g' "$conf"
					sed -i 's;#[ \t]*SecAuditLog[ \t]\+\(.*\);SecAuditLog \1;g' "$conf"
				done
			fi

			k_restart_web_server
		;;
		"off")
			k_comment_out_all_line "${KUSANAGI_NGINX_WAF_ROOT_CONF}"
			for conf in $(k_get_provisioned_nginx_conf)
			do
				sed -i 's;\([^#]\+\)include[ \t]\+\(naxsi\.d/.*\);\1#include \2;g' "$conf"
			done
			k_comment_out_all_line "${KUSANAGI_APACHE_WAF_ROOT_CONF}"
			for conf in $(k_get_provisioned_httpd_conf)
			do
				sed -i 's;\([^#]\+\)IncludeOptional[ \t]\+\(modsecurity\.d/.*\);\1#IncludeOptional \2;g' "$conf"
				sed -i 's;\([^#]\+\)SecAuditLog[ \t]\+\(.*\);\1#SecAuditLog \2;g' "$conf"
			done
			k_restart_web_server
		;;
		* )
			k_print_usage "kusanagi waf {on|off}"
		;;
	esac
}

function k_install_httpd_waf_modules () {
	local RET
	k_yum_install "kusanagi-httpd-waf"
	RET=$?
	k_yum_install "mod_security"
	k_yum_install "mod_security_crs"

	local CRS_CONF=/etc/httpd/modsecurity.d/modsecurity_crs_10_config.conf

	if [[ -f ${CRS_CONF} ]]; then
		sed -i "s;HTTP/0.9 HTTP/1.0 HTTP/1.1';HTTP/0.9 HTTP/1.0 HTTP/1.1 HTTP/2.0';g" ${CRS_CONF}
	fi

	if [[ -d /var/lib/mod_security ]]; then
		chown httpd.root /var/lib/mod_security
	fi

	if [[ ! -f /var/lib/mod_security/global ]]; then
		touch /var/lib/mod_security/global
	fi

	if [[ ! -f /var/lib/mod_security/ip ]]; then
		touch /var/lib/mod_security/ip
	fi

	return $RET
}

function k_is_waf_activated () {
	if [[ $(k_is_active nginx) -eq 0 ]] && [[ -f "${KUSANAGI_NGINX_WAF_ROOT_CONF}" ]] && ! k_is_comment_out ${KUSANAGI_NGINX_WAF_ROOT_CONF} ; then
		return 0
	elif [[ $(k_is_active httpd) -eq 0 ]] && [[ -f "${KUSANAGI_APACHE_WAF_ROOT_CONF}" ]] && ! k_is_comment_out ${KUSANAGI_APACHE_WAF_ROOT_CONF} ; then
		return 0
	fi
	return 1
}

# selinux method called by kusanagi command
function k_selinux () {
	shift
	_k_selinux $@
}

# internal selinux method
function _k_selinux () {

	local SE_LINUX_CONF=/etc/selinux/config

	sed -i "s/^\s*SELINUXTYPE\s*=.*$/SELINUXTYPE=targeted/" $SE_LINUX_CONF

	k_activate_auditd

	case "${1}" in
		"on")

			if ! selinuxenabled ; then
				sed -i "s/^\s*SELINUX\s*=.*$/SELINUX=permissive/" $SE_LINUX_CONF
				k_print_notice $(eval_gettext "SELinux is currently 'disabled'. Please reboot this machine. And then, run 'kusanagi selinux on' command again.")
				return 1
			fi

			if [[ $(k_is_active php7-fpm) -ne 0 ]] ; then
				k_print_notice $(eval_gettext "php7 must be enabled to enable the SELinux.")
				return 1
			fi

			echo $(eval_gettext "Enabling SELinux...")

			# module policy dir
			local SE_LINUX_MOD_DIR=/etc/selinux/targeted/modules/active/modules
			k_yum_install "selinux-policy-devel"
			k_yum_install "policycoreutils-python"

			# nginx and apache and php-fpm
			setsebool -P httpd_setrlimit 1
			setsebool -P httpd_execmem 1
			setsebool -P httpd_can_network_connect 1
			setsebool -P httpd_can_network_connect_db 1
			setsebool -P httpd_enable_homedirs 1
			setsebool -P httpd_graceful_shutdown 1
			setsebool -P httpd_can_sendmail 1
			setsebool -P httpd_builtin_scripting 1
			setsebool -P httpd_can_connect_ldap 1

			# kusanagi dir
			semanage fcontext -a -t httpd_sys_content_t "/home/kusanagi(/.*)?"
			semanage fcontext -a -t httpd_log_t "/home/kusanagi/[^/]+/log(/.*)?"
			semanage fcontext -a -t httpd_sys_rw_content_t "/home/kusanagi/[^/]+/DocumentRoot"
			semanage fcontext -a -t httpd_sys_rw_content_t "/home/kusanagi/[^/]+/DocumentRoot/wp-content"
			semanage fcontext -a -t httpd_sys_rw_content_t "/home/kusanagi/[^/]+/DocumentRoot/wp-content/uploads(/.*)?"
			semanage fcontext -a -t httpd_sys_rw_content_t "/home/kusanagi/[^/]+/DocumentRoot/wp-content/advanced-cache.php"
			semanage fcontext -a -t httpd_sys_rw_content_t "/home/kusanagi/[^/]+/DocumentRoot/wp-content/replace-class.php"
			restorecon -R -v /home/kusanagi

			#nginx cache dir
			semanage fcontext -a -t httpd_sys_rw_content_t "/var/cache/nginx(/.*)?"
			restorecon -R -v /var/cache/nginx

			if [[ -n "${2}" ]] && [[ "${2}" = '--strict' ]]; then
				# allow aftpd
				setsebool -P ftpd_full_access 0
			else
				setsebool -P ftpd_full_access 1
			fi

			# php7-fpm
			semanage fcontext -a -t httpd_exec_t '/usr/local/php7/sbin/php-fpm'
			restorecon -R -v '/usr/local/php7/sbin/php-fpm'
			semanage fcontext -a -t httpd_log_t "/var/log/php7-fpm(/.*)?"
			restorecon -R -v /var/log/php7-fpm

			# logrotate
			if [[ ! -f "$SE_LINUX_MOD_DIR/kusanagi_logrotate.pp" ]]; then
				( cd $SE_LINUX_MOD_DIR; make -f /usr/share/selinux/devel/Makefile )
			fi
			semodule -i "$SE_LINUX_MOD_DIR/kusanagi_logrotate.pp"

			setenforce 1
			sed -i "s/^\s*SELINUX\s*=.*$/SELINUX=enforcing/" $SE_LINUX_CONF
			k_print_info $(eval_gettext "SELinux has been enabled.")
		;;
		"off")
			setenforce 0
			if [[ -n "${2}" ]] && [[ "${2}" = '--permanent' ]]; then
				sed -i "s/^\s*SELINUX\s*=.*$/SELINUX=disabled/" $SE_LINUX_CONF
				k_deactivate_auditd
				k_print_notice k_print_info $(eval_gettext "If you ensure that the changes take effect, Please reboot this machine.")
			else
				sed -i "s/^\s*SELINUX\s*=.*$/SELINUX=permissive/" $SE_LINUX_CONF
			fi
			k_print_info $(eval_gettext "SELinux has been disabled.")
		;;
		* )
			k_print_usage "kusanagi selinux {on [--strict]|off [--permanent]}"
			return 1
		;;
	esac

	# restart middleware
	k_restart_web_server
	k_restart_php_daemon
}

function k_is_selinux_activated () {
	if [[ $(getenforce) = 'Enforcing' ]] ; then
		return 0
	fi
	return 1
}

function __k_is_selinux_strict_security () {
	if getsebool ftpd_full_access | grep 'off$' > /dev/null ; then
		return 0
	fi
	return 1
}

function k_comment_out_all_line () {
	local file=$1
	if [ ! -f ${file} ]; then
		k_print_result "NOTICE: ${file} does not exist."
		return 1
	fi
	sed -i "s/^/${KUSANAGI_COMMENT_SYMBOL}/g" $file
}

function k_comment_in_all_line () {
	local file=$1
	if [ ! -f ${file} ]; then
		k_print_result "NOTICE: ${file} does not exist."
		return 1
	fi
	sed -i "s/${KUSANAGI_COMMENT_SYMBOL}//g" $file
}

# check if the ${KUSANAGI_COMMENT_SYMBOL} exists.
function k_is_comment_out () {
	local FILE=$1
	if grep ${KUSANAGI_COMMENT_SYMBOL} ${FILE} > /dev/null ; then
		return 0
	else
		return 1
	fi
}

function k_get_provisioned_nginx_conf () {
	k_get_provisioned_conf "nginx"
}

function k_get_provisioned_httpd_conf () {
	k_get_provisioned_conf "httpd"
}

function k_get_provisioned_conf () {
	local web=$1
	local conf
	for conf in $(find /etc/$web/conf.d/ -type f -name '*http.conf' -o -name '*ssl.conf')
	do
		echo ${conf}
	done
}

# shutdown all db daemon
function k_shutdown_all_db () {
	k_deactivate_psql
	k_deactivate_mariadb
}

# verify whether two words are same
function k_check_word () {
	if [[ -z "$1" ]]; then
		return 1;
	fi

	if [[ "$1" != "$2" ]]; then
		return 1
	fi
	return 0;
}

# display info message
function k_print_info () {
	k_print_green "INFO: $1"
}

# display error message
function k_print_error () {
	k_print_red "ERROR: $1"
}

# display notice message
function k_print_notice () {
	k_print_yellow "NOTICE: $1"
}

# display message
function k_print_result () {

	local TYPE START END OUT

	if echo "$1" | grep -i 'INFO:' > /dev/null ; then
		TYPE=info
	elif  echo "$1" | grep -i 'NOTICE:' > /dev/null  ; then
		TYPE=notice
	elif  echo "$1" | grep -i 'ERROR:' > /dev/null  ; then
		TYPE=error
	fi

	OUT='STD'
	case ${TYPE} in
		info)
			START='\e[32m';
			END='\e[m'
		;;
		notice)
			START='\e[33m';
			END='\e[m'
		;;
		error)
			START='\e[31m';
			END='\e[m'
			OUT='ERR'
		;;
	esac

	if [[ -t 1 ]]; then
		if [[ "$OUT" = "ERR" ]]; then
			echo -e "${START}$1${END}" 1>&2
		else
			echo -e "${START}$1${END}"
		fi
	else
		if [[ "$OUT" = "ERR" ]]; then
			echo "$1" 1>&2
		else
			echo "$1"
		fi
	fi
}

function k_print_red () {
	local OUT="${1}"
	if k_is_tty; then
		echo -e "\e[31m${OUT}\e[m"
	else
		echo "$OUT"
	fi
}

function k_print_yellow () {
	local OUT="${1}"
	if k_is_tty; then
		echo -e "\e[33m${OUT}\e[m"
	else
		echo "$OUT"
	fi
}

function k_print_green () {
	local OUT="${1}"
	if k_is_tty; then
		echo -e "\e[32m${OUT}\e[m"
	else
		echo "$OUT"
	fi
}

function k_print_usage () {
	k_print_yellow "Usage: $1"
}

# restart current php daemon
function k_restart_php_daemon () {
	if [[ $(k_is_active php7-fpm) -eq 0 ]] ; then
		k_php7 'php7'
	elif [[ $(k_is_active hhvm) -eq 0 ]] ; then
		k_hhvm 'hhvm'
	elif [[ $(k_is_active php-fpm) -eq 0 ]] ; then
		k_phpfpm 'php-fpm'
	fi
}

# change the php binary path
function _k_change_php_bin () {

	local CHANGE=$1

	if [[ -L /usr/local/bin/php ]]; then
		unlink /usr/local/bin/php
	else
		CHANGE=1
	fi

	if [[ $(k_is_active php7-fpm) -eq 0 ]] ; then
		ln -snf /usr/local/php7/bin/php /usr/local/bin/php
	elif [[ $(k_is_active php-fpm) -eq 0 ]] ; then
		ln -snf /bin/php /usr/local/bin/php
	fi

	if [[ $CHANGE -eq 1 ]]; then
		k_print_notice "Please run the following command to change the php command path in the current shell."
		echo
		k_print_yellow "$ hash -r"
		echo
	fi
}

function k_is_reinstall () {

	local NAME=$1
	local IS_FORCE=$2

	if [[ $IS_FORCE = '--force' ]]; then
		return 0
	fi

	k_print_notice "$NAME is already installed. Are you sure you want to reinstall $NAME? [y/n]"
	if ! k_is_yes ; then
		return 1
	else
		return 0
	fi
}

# execution as kusanagi user
function k_kusanagi_user_exec () {
	su - kusanagi -c "$1"
}

# restart current web server
function k_restart_web_server () {
	if [[ $(k_is_active nginx) -eq 0 ]] ; then
		k_nginx 'nginx'
	elif [[ $(k_is_active httpd) -eq 0 ]] ; then
		k_httpd 'httpd'
	fi
}

# set directive num value
function _k_set_directive_num () {
	local DIRECTIVE=$1
	local VALUE=$2
	local CONF=$3
	local COMPARE=$4

	local OPERATER=
	if [[ -n ${COMPARE} ]]; then
		local OPERATER=$(echo ${COMPARE} | sed -e 's;[[:digit:]];;g')
		local NUM=$(echo ${COMPARE} | sed -e 's;[^[:digit:]];;g')
	fi

	local hit_line=0
	local DO=0
	local regex=
	while read -r line; do
		hit_line=$(( hit_line+1 ));
		regex="^[^;]*${DIRECTIVE}[[:space:]]*=[[:space:]]*([[:digit:]]{1,})";
		if [[ $line =~ $regex ]] ; then
			DO=0
			if [[ $OPERATER = '<' ]] ; then
				if [[ ${BASH_REMATCH[1]} -lt $NUM ]]; then
					DO=1
				fi
			fi
			if [[ $OPERATER = '>' ]] ; then
				if [[ ${BASH_REMATCH[1]} -gt $NUM ]]; then
					DO=1
				fi
			fi

			if [[ -z $OPERATER ]] ; then
				DO=1
			fi

			if [[ $DO -eq 1 ]]; then
				sed -ie "$hit_line s/^[^;]*${DIRECTIVE}[[:space:]]*=.*/${DIRECTIVE} = ${VALUE}/g" ${CONF};
			fi
		fi
	done < <(cat ${CONF})
}

# check if a file descriptor is a tty.
function k_is_tty () {
	if [[ -t 1 ]]; then
		return 0
	else
		return 1
	fi
}

# check if current shell is interactive
function k_is_interactive () {
	case "$-" in
		*i*)  return 0 ;;
		*)  return 1;;
	esac
}
