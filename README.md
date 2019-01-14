# kusanagi-command-custom
KUSANAGI標準のShellScriptをカスタマイズしたもの

挙動確認バージョン : 8.4.2-1

あくまで本家KUSANAGIを使いこなせている or ドキュメントをしっかり読んで理解している人向けです。

## できること
・任意のディレクトリへの provision  
・provision の際に --dbskip を指定することでDB名、DBユーザ、DBパスワードの確認とDB自動作成をスキップ可能  
・phpMyAdmin のデプロイ  

## install
```
git clone git@github.com:/qkotsudo/kusanagi-command-custom
cd kusanagi-command-custom
chmod a+x install.sh
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

help.sh  
	--phpMyAdmin, --dbskip, --dst-dir の説明追加
	
provision.sh  
	--phpMyAdmin, --dbskip, --dst-dir, --dst-name を処理する宣言追加  
	プロファイル名の文字数を253文字以内まで拡張  
	$TARGET_DIR への代入調整  
	--dbskip の処理追加  

virt.sh  
	既存設定ファイルのバックアップをコメントアウト(monitでエラー出るので)  
	$PROFILE の置き換え処理調整  

deploy-phpMyAdmin.sh  
	新規  

deploy-*.sh  
	プロビジョン先ディレクトリ調整  
	追加設定用etcディレクトリ設置  
