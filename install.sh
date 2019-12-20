#!/usr/bin/bash

# 動作確認バージョン設定
VERSION_TARGET="8.4.5-3"

# root権限での実行確認
if [ ${EUID:-${UID}} != 0 ]; then
    echo 'Please run as root.'
    exit 1
fi

# yum から kusanagi の rpm のバージョン番号取得
VERSION_CURRENT=`yum list installed kusanagi | grep kusanagi.noarch | sed -e "s/kusanagi.noarch//" -e "s/\@kusanagi//" -e ':loop;N;$!b loop;s/\n//g'`

# バージョン確認
if [ $VERSION_CURRENT != $VERSION_TARGET ]; then
	echo "This installer works with kusanagi version $VERSION_TARGET"
	echo "Current installed version : $VERSION_CURRENT"
	exit 1
fi

# rsync で配置
DIR=$(cd $(dirname $0); pwd)
rsync -rltv --progress $DIR/mod/usr/lib/kusanagi/ /usr/lib/kusanagi/
echo "kusanagi-command-custom install successfully done."
exit 0