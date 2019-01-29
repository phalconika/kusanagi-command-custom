# kusanagi-command-custom
KUSANAGI標準のShellScriptをカスタマイズしたもの

挙動確認バージョン : 8.4.2-1 on AWS

あくまで本家KUSANAGIを使いこなせている or ドキュメントをしっかり読んで理解している人向けです。

## できること
・任意のディレクトリへの provision  
・provision の際に --dbskip を指定することでDB名、DBユーザ、DBパスワードの確認とDB自動作成をスキップ可能  
・phpMyAdmin のデプロイ  
・provision 先のディレクトリに etc サブディレクトリを作成し、/etc/ 以下から SymbolicLink を張りつつ kusanagi 権限で編集可能に変更  

## install
```
git clone https://github.com/qkotsudo/kusanagi-command-custom.git
cd kusanagi-command-custom
sudo ./install.sh
```

## usage
### kusanagi provision option
[ --dbskip ]  
このオプションを指定することで、DBチェックとDBユーザの作成をスキップします。  
既存インスタンス上で既存DBを使用したい場合等に指定します  
  
[ --dst-dir (path_to_destination_directory) ]  
provision 先のディレクトリを指定します。  
対象のディレクトリ自体は provision 内で作成するので、すでに存在している場合はエラーで終了します。  
また、親ディレクトリまでの path が存在していないとエラーで終了します。  
  
[ --phpmyadmin | --phpMyAdmin ]  
phpMyAdmin 用のプロファイルです。  
最新版を git にて取得 → composer update や yarn のインストール、多言語対応を行います  


## 差分メモ
functions.sh  
	--phpMyAdmin, --dbskip, --dst-dir の説明追加  
	k_read_profile()内のTARGET_DIR, NGINX_HTTP, NGINX_HTTPS, HTTPD_HTTP, HTTPD_HTTPS調整
	k_target()内のプロファイル名判別の文字数を最大253文字に変更  
	

help.sh  
	--phpMyAdmin, --dbskip, --dst-dir の説明追加
	
provision.sh  
	--phpMyAdmin, --dbskip, --dst-dir を処理する宣言追加  
	プロファイル名の文字数を253文字以内まで拡張  
	$TARGET_DIR への代入調整  
	--dbskip の処理追加  

virt.sh  
	サブディレクトリ作成を先頭に移動、etcディレクトリ作成を追加  
	apache, nginx, monit の設定ファイルをサブディレクトリ内の etc に変更し、/etc/ の各設定用ディレクトリ内へ SymbolicLink  
	既存設定ファイルのバックアップをコメントアウト(monitでエラー出るので)  
	$PROFILE の置き換え処理調整  

deploy-phpMyAdmin.sh  
	新規  

deploy-*.sh  
	プロビジョン先ディレクトリ調整  

remove.sh  
	TARGET_DIR調整