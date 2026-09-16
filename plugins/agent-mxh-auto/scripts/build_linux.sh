#!/bin/bash
set -e

# Script đóng gói và tạo file cài đặt .deb cho Ubuntu/Debian Linux
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
DIST_DIR="$APP_DIR/dist-flutter"

echo "========================================================"
echo " TAO BAN CAI DAT UBUNTU/DEBIAN CHO MXH TU DONG"
echo "========================================================"

cd "$APP_DIR"

echo "[1/4] Dang bien dich Flutter Linux Release..."
flutter build linux --release

echo "[2/4] Chuan bi cau truc goi cai dat .deb..."
PKG_NAME="mxh-tu-dong_1.0.0_amd64"
PKG_DIR="$DIST_DIR/$PKG_NAME"

rm -rf "$PKG_DIR"
mkdir -p "$PKG_DIR/DEBIAN"
mkdir -p "$PKG_DIR/opt/mxh-tu-dong"
mkdir -p "$PKG_DIR/usr/bin"
mkdir -p "$PKG_DIR/usr/share/applications"
mkdir -p "$PKG_DIR/usr/share/icons/hicolor/512x512/apps"

# Copy Linux release bundle
cp -r "$APP_DIR/build/linux/x64/release/bundle/"* "$PKG_DIR/opt/mxh-tu-dong/"

# Tao script khoi chay trong /usr/bin de chay truc tiep tu command line
cat << 'BIN_EOF' > "$PKG_DIR/usr/bin/mxh-tu-dong"
#!/bin/bash
exec /opt/mxh-tu-dong/agent_mxh_auto "$@"
BIN_EOF
chmod +x "$PKG_DIR/usr/bin/mxh-tu-dong"

# Icon
if [ -f "$APP_DIR/assets/icon.png" ]; then
    cp "$APP_DIR/assets/icon.png" "$PKG_DIR/usr/share/icons/hicolor/512x512/apps/mxh-tu-dong.png"
elif [ -f "$APP_DIR/assets/logo.jpg" ]; then
    cp "$APP_DIR/assets/logo.jpg" "$PKG_DIR/usr/share/icons/hicolor/512x512/apps/mxh-tu-dong.jpg"
fi

# Desktop Launcher
cat << 'DESKTOP_EOF' > "$PKG_DIR/usr/share/applications/mxh-tu-dong.desktop"
[Desktop Entry]
Name=MXH Tự Động
Comment=Phần mềm AI quản lý MXH tự động
Exec=/usr/bin/mxh-tu-dong
Icon=mxh-tu-dong
Terminal=false
Type=Application
Categories=Development;Utility;
DESKTOP_EOF
chmod 644 "$PKG_DIR/usr/share/applications/mxh-tu-dong.desktop"

# Debian Control file
cat << 'CONTROL_EOF' > "$PKG_DIR/DEBIAN/control"
Package: mxh-tu-dong
Version: 1.0.0
Section: utils
Priority: optional
Architecture: amd64
Maintainer: Tadu Cloud Team <support@tadu.vn>
Depends: libc6, libgtk-3-0
Description: Phan mem AI quan ly MXH tu dong
 Ung dung Flutter Desktop quan ly MXH tu dong tren Ubuntu va Debian Linux.
CONTROL_EOF

echo "[3/4] Dong goi file cai dat .deb..."
dpkg-deb --build "$PKG_DIR" "$DIST_DIR/mxh-tu-dong_1.0.0_amd64.deb"
rm -rf "$PKG_DIR"

echo "[4/4] Tao ban nen Portable .tar.gz..."
cd "$APP_DIR/build/linux/x64/release/bundle"
tar -czf "$DIST_DIR/MXH-Tu-Dong-Portable-Ubuntu-x64.tar.gz" .

echo "========================================================"
echo " HOAN TAT DONG GOI CHO UBUNTU!"
echo " File cai dat .deb: $DIST_DIR/mxh-tu-dong_1.0.0_amd64.deb"
echo " File portable:    $DIST_DIR/MXH-Tu-Dong-Portable-Ubuntu-x64.tar.gz"
echo "========================================================"
