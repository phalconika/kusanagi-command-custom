cd $TARGET_DIR
GIT_HOME="https://github.com/phpmyadmin/phpmyadmin.git";
git clone -b STABLE $GIT_HOME DocumentRoot
ret=$?

# yarn準備
curl --silent --location https://dl.yarnpkg.com/rpm/yarn.repo | tee /etc/yum.repos.d/yarn.repo
yum -y install yarn

chown -R kusanagi.kusanagi $TARGET_DIR
chmod 0777 $TARGET_DIR/DocumentRoot

cd $TARGET_DIR/DocumentRoot
sudo -u kusanagi ${KUSANAGI_COMPOSER_BIN} update
sudo -u kusanagi yarn install

# 多言語化
# ※ ↓ 2019/03/01現在、4.8.5でエラーが出るので過去バージョンの po をコピる
# ※ ↓ 2019/08/21現在、STABLE が 4.9 になってエラー出なくなった
# sudo -u kusanagi cp -R /usr/lib/kusanagi/resource/phpMyAdmin/po $TARGET_DIR/DocumentRoot/
sudo -u kusanagi scripts/generate-mo