#!/usr/bin/env bash
set -e

SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$SOURCE_DIR"

APP_NAME="ai-type-agent"
PKG_NAME="ai-type-agent"
VERSION="1.4.0"
ARCH="amd64"
DIST_DIR="$SOURCE_DIR/dist"
BUNDLE_DIR="$SOURCE_DIR/build/linux/x64/release/bundle"
DEB_BUILD_DIR="$SOURCE_DIR/build/deb_pkg"

echo "=== BAT DAU TAO GOI CAI DAT .DEB CHO UBUNTU / LINUX ==="

if [ ! -d "$BUNDLE_DIR" ]; then
    echo "1. Dang bien dich ban release Flutter Linux..."
    flutter build linux --release
fi

echo "2. Chuan bi cau truc thu muc goi .deb..."
rm -rf "$DEB_BUILD_DIR"
mkdir -p "$DEB_BUILD_DIR/DEBIAN"
mkdir -p "$DEB_BUILD_DIR/opt/$APP_NAME"
mkdir -p "$DEB_BUILD_DIR/usr/bin"
mkdir -p "$DEB_BUILD_DIR/usr/share/applications"
mkdir -p "$DEB_BUILD_DIR/usr/share/icons/hicolor/512x512/apps"
mkdir -p "$DIST_DIR"

echo "3. Sao chep ma nguon bundle va tai nguyen..."
cp -r "$BUNDLE_DIR"/* "$DEB_BUILD_DIR/opt/$APP_NAME/"
chmod +x "$DEB_BUILD_DIR/opt/$APP_NAME/ai-type-agent"

# Copy Icon
if [ -f "$SOURCE_DIR/assets/app_icon.png" ]; then
    cp "$SOURCE_DIR/assets/app_icon.png" "$DEB_BUILD_DIR/usr/share/icons/hicolor/512x512/apps/$APP_NAME.png"
elif [ -f "$SOURCE_DIR/assets/logo.png" ]; then
    cp "$SOURCE_DIR/assets/logo.png" "$DEB_BUILD_DIR/usr/share/icons/hicolor/512x512/apps/$APP_NAME.png"
fi

# Tao Desktop File
cat <<DESKTOP_EOF > "$DEB_BUILD_DIR/usr/share/applications/$APP_NAME.desktop"
[Desktop Entry]
Version=1.0
Type=Application
Name=AI Type Agent
GenericName=Agent Coder Client
Comment=Quan tri may chu va Agent Coding
Exec=/opt/$APP_NAME/ai-type-agent %u
Icon=$APP_NAME
Terminal=false
Categories=Development;Utility;
StartupNotify=true
StartupWMClass=ai-type-agent
DESKTOP_EOF

# Tao Wrapper symlink trong /usr/bin
ln -sf "/opt/$APP_NAME/ai-type-agent" "$DEB_BUILD_DIR/usr/bin/$APP_NAME"

# Tao file DEBIAN/control
INSTALLED_SIZE=$(du -sk "$DEB_BUILD_DIR" | cut -f1)
cat <<CONTROL_EOF > "$DEB_BUILD_DIR/DEBIAN/control"
Package: $PKG_NAME
Version: $VERSION
Section: devel
Priority: optional
Architecture: $ARCH
Installed-Size: $INSTALLED_SIZE
Maintainer: AI Type Agent <support@tadu.vn>
Description: AI Type Agent - Trợ lý lập trình và Quản trị máy chủ Agentic AI
 Ứng dụng Desktop dành cho Ubuntu/Debian Linux giúp kết nối máy chủ,
 quản trị hạ tầng và tương tác trực tiếp với các Agent lập trình thông minh.
CONTROL_EOF

# Tao file postinst cap nhat database icon/desktop
cat <<POSTINST_EOF > "$DEB_BUILD_DIR/DEBIAN/postinst"
#!/bin/sh
set -e
if [ "\$1" = "configure" ]; then
    update-desktop-database -q /usr/share/applications 2>/dev/null || true
    gtk-update-icon-cache -q -t -f /usr/share/icons/hicolor 2>/dev/null || true
fi
exit 0
POSTINST_EOF
chmod 755 "$DEB_BUILD_DIR/DEBIAN/postinst"

# Tao file postrm khi go cai dat
cat <<POSTRM_EOF > "$DEB_BUILD_DIR/DEBIAN/postrm"
#!/bin/sh
set -e
if [ "\$1" = "remove" ] || [ "\$1" = "purge" ]; then
    update-desktop-database -q /usr/share/applications 2>/dev/null || true
    gtk-update-icon-cache -q -t -f /usr/share/icons/hicolor 2>/dev/null || true
fi
exit 0
POSTRM_EOF
chmod 755 "$DEB_BUILD_DIR/DEBIAN/postrm"

echo "4. Dong goi tap tin .deb..."
DEB_OUTPUT="$DIST_DIR/${PKG_NAME}_${VERSION}_${ARCH}.deb"
dpkg-deb --build "$DEB_BUILD_DIR" "$DEB_OUTPUT"

# Tao them goi .tar.gz dong goi san (Portable tarball)
echo "5. Tao ban dong goi nen .tar.gz (Portable)..."
TAR_OUTPUT="$DIST_DIR/${PKG_NAME}_${VERSION}_linux_x64.tar.gz"
tar -czf "$TAR_OUTPUT" -C "$BUNDLE_DIR" .

echo "=== HOAN TAT DONG GOI FILE CAI DAT ==="
ls -lh "$DIST_DIR"
