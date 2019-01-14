cd $TARGET_DIR/DocumentRoot
chown -R kusanagi.kusanagi $TARGET_DIR
chmod 0777 $TARGET_DIR/DocumentRoot

cp -r /usr/lib/kusanagi/skel/etc $TARGET_DIR/etc
chown -R kusanagi.kusanagi $TARGET_DIR/etc
