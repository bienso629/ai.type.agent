#!/usr/bin/env bash
set -e

SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUNDLE_DIR="$SOURCE_DIR/build/linux/x64/release/bundle"
INSTALL_DIR="$HOME/.local/share/ai-type-agent"
BIN_LINK="$HOME/.local/bin/ai-type-agent"
DESKTOP_DIR="$HOME/.local/share/applications"
DESKTOP_FILE="$DESKTOP_DIR/ai-type-agent.desktop"
ICON_DIR="$HOME/.local/share/icons/hicolor/512x512/apps"
ICON_TARGET="$ICON_DIR/ai-type-agent.png"

echo "=== DANG CAI DAT AI TYPE AGENT VAO MAY TINH (UBUNTU / LINUX) ==="

if [ ! -d "$BUNDLE_DIR" ]; then
    echo "Thu muc bundle chua ton tai. Dang tien hanh bien dich ban release..."
    cd "$SOURCE_DIR"
    flutter build linux --release
fi

echo "1. Tao cac thu muc he thong cho nguoi dung..."
mkdir -p "$INSTALL_DIR"
mkdir -p "$HOME/.local/bin"
mkdir -p "$DESKTOP_DIR"
mkdir -p "$ICON_DIR"

echo "2. Sao chep bo bundle vao $INSTALL_DIR..."
rm -rf "$INSTALL_DIR"/*
cp -r "$BUNDLE_DIR"/* "$INSTALL_DIR/"
chmod +x "$INSTALL_DIR/ai-type-agent"

echo "3. Sao chep bieu tuong ung dung (icon)..."
if [ -f "$SOURCE_DIR/assets/app_icon.png" ]; then
    cp "$SOURCE_DIR/assets/app_icon.png" "$ICON_TARGET"
elif [ -f "$SOURCE_DIR/assets/logo.png" ]; then
    cp "$SOURCE_DIR/assets/logo.png" "$ICON_TARGET"
fi

echo "4. Tao lien ket thuc thi command-line: $BIN_LINK..."
ln -sf "$INSTALL_DIR/ai-type-agent" "$BIN_LINK"

echo "5. Tao file bieu tuong khoi chay desktop: $DESKTOP_FILE..."
cat <<DESKTOP_EOF > "$DESKTOP_FILE"
[Desktop Entry]
Version=1.0
Type=Application
Name=AI Type Agent
GenericName=Agent Coder Client
Comment=Quan tri may chu va Agent Coding
Exec=$INSTALL_DIR/ai-type-agent %u
Icon=$ICON_TARGET
Terminal=false
Categories=Development;Utility;
StartupNotify=true
StartupWMClass=ai-type-agent
DESKTOP_EOF

chmod +x "$DESKTOP_FILE"

echo "6. Cap nhat co so du lieu ung dung Desktop cua Ubuntu..."
update-desktop-database "$DESKTOP_DIR" 2>/dev/null || true
gtk-update-icon-cache -f -t "$HOME/.local/share/icons/hicolor" 2>/dev/null || true

echo "=== CAI DAT THANH CONG ==="
echo "- Ung dung da xuat hien trong danh sach ung dung (App Menu / Dash) cua Ubuntu voi ten 'AI Type Agent'."
echo "- Co the chay truc tiep tu Terminal bang lenh: ai-type-agent (neu $HOME/.local/bin co trong PATH) hoac $INSTALL_DIR/ai-type-agent"
