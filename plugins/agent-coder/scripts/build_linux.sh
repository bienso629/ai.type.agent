#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
DIST_DIR="$PROJECT_DIR/dist"

echo "=== [1/4] Building Flutter Linux Release ==="
cd "$PROJECT_DIR"
flutter build linux --release

echo "=== [2/4] Preparing Debian package structure ==="
PKG_NAME="ai-type-agent_1.0.0_amd64"
PKG_DIR="$DIST_DIR/$PKG_NAME"

rm -rf "$PKG_DIR"
mkdir -p "$PKG_DIR/DEBIAN"
mkdir -p "$PKG_DIR/opt/ai-type-agent"
mkdir -p "$PKG_DIR/usr/bin"
mkdir -p "$PKG_DIR/usr/share/applications"
mkdir -p "$PKG_DIR/usr/share/icons/hicolor/512x512/apps"

# Copy Linux release bundle
cp -r "$PROJECT_DIR/build/linux/x64/release/bundle/"* "$PKG_DIR/opt/ai-type-agent/"

# Symlink
ln -sf /opt/ai-type-agent/ai-type-agent "$PKG_DIR/usr/bin/ai-type-agent"

# Icon setup across all hicolor sizes
ICON_SRC="$PROJECT_DIR/assets/app_icon.png"
if [ ! -f "$ICON_SRC" ]; then
  ICON_SRC="$PROJECT_DIR/assets/logo.png"
fi

for size in 16x16 32x32 48x48 64x64 128x128 256x256 512x512; do
  mkdir -p "$PKG_DIR/usr/share/icons/hicolor/$size/apps"
  cp "$ICON_SRC" "$PKG_DIR/usr/share/icons/hicolor/$size/apps/ai-type-agent.png"
  cp "$ICON_SRC" "$PKG_DIR/usr/share/icons/hicolor/$size/apps/ai.type.agent.png"
done
mkdir -p "$PKG_DIR/usr/share/pixmaps"
cp "$ICON_SRC" "$PKG_DIR/usr/share/pixmaps/ai-type-agent.png"
cp "$ICON_SRC" "$PKG_DIR/usr/share/pixmaps/ai.type.agent.png"

# Desktop Launcher
cat << 'DESKTOP_EOF' > "$PKG_DIR/usr/share/applications/ai.type.agent.desktop"
[Desktop Entry]
Name=AI Type Agent
GenericName=AI Developer & Server Assistant
Comment=AI Type Agent Native Desktop Application
Exec=/opt/ai-type-agent/ai-type-agent %u
Icon=ai-type-agent
Terminal=false
Type=Application
Categories=Development;Utility;
StartupNotify=true
StartupWMClass=ai.type.agent
Keywords=AI;Agent;Coder;Server;Type;
DESKTOP_EOF

# Control file
cat << 'CONTROL_EOF' > "$PKG_DIR/DEBIAN/control"
Package: ai-type-agent
Version: 1.0.0
Section: devel
Priority: optional
Architecture: amd64
Maintainer: AI Type Team <support@type.ai>
Description: AI Type Agent Native Flutter Desktop Application
 High performance, lightweight native Linux desktop client for AI Type Agent.
CONTROL_EOF

echo "=== [3/4] Packaging .deb installer ==="
mkdir -p "$DIST_DIR"
dpkg-deb --build "$PKG_DIR" "$DIST_DIR/$PKG_NAME.deb"

echo "=== [4/4] Creating portable .tar.gz bundle ==="
cd "$PROJECT_DIR/build/linux/x64/release/bundle"
tar -czf "$DIST_DIR/ai-type-agent-linux-x64.tar.gz" .

if [ -d "$HOME/.local/share/ai-type-agent" ]; then
  echo "=== [5/5] Syncing to local user install (~/.local/share/ai-type-agent) ==="
  cp -r "$PROJECT_DIR/build/linux/x64/release/bundle/"* "$HOME/.local/share/ai-type-agent/"
fi

echo "=== Done! Files generated in $DIST_DIR ==="
ls -lh "$DIST_DIR"

