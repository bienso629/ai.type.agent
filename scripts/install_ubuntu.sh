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
PIXMAP_DIR="$HOME/.local/share/pixmaps"

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
mkdir -p "$PIXMAP_DIR"

echo "2. Sao chep bo bundle vao $INSTALL_DIR..."
rm -rf "$INSTALL_DIR"/*
cp -r "$BUNDLE_DIR"/* "$INSTALL_DIR/"
chmod +x "$INSTALL_DIR/ai-type-agent"

if [ -d "/opt/ai-type-agent" ] && [ -w "/opt/ai-type-agent" ]; then
    rm -rf /opt/ai-type-agent/*
    cp -r "$BUNDLE_DIR"/* /opt/ai-type-agent/
    chmod +x /opt/ai-type-agent/ai-type-agent
fi

echo "3. Chuan hoa va sao chep bieu tuong ung dung (icon)..."
SRC_ICON=""
if [ -f "$SOURCE_DIR/assets/app_icon.png" ]; then
    SRC_ICON="$SOURCE_DIR/assets/app_icon.png"
elif [ -f "$SOURCE_DIR/assets/logo.png" ]; then
    SRC_ICON="$SOURCE_DIR/assets/logo.png"
fi

if [ -n "$SRC_ICON" ]; then
    python3 - "$SRC_ICON" "$ICON_TARGET" << 'PYEOF'
import sys
from PIL import Image, ImageDraw

src, dst = sys.argv[1], sys.argv[2]
im = Image.open(src).convert("RGBA")
if im.size != (512, 512):
    im = im.resize((512, 512), Image.LANCZOS)

bbox = im.getbbox()
# Neu icon tran vien (khong co vien trong suot chuẩn GNOME/Ubuntu Dock ~9%), tu dong thu nho ve 420x420 giua khung 512x512
if bbox is not None and bbox[0] < 20 and bbox[1] < 20 and bbox[2] > 492 and bbox[3] > 492:
    target_size = 420
    margin = (512 - target_size) // 2
    inner = im.resize((target_size, target_size), Image.LANCZOS)
    mask = Image.new("L", (target_size, target_size), 0)
    draw = ImageDraw.Draw(mask)
    draw.rounded_rectangle((0, 0, target_size - 1, target_size - 1), radius=92, fill=255)
    r, g, b, a = inner.split()
    new_a = Image.composite(a, Image.new("L", (target_size, target_size), 0), mask)
    inner.putalpha(new_a)
    canvas = Image.new("RGBA", (512, 512), (0, 0, 0, 0))
    canvas.paste(inner, (margin, margin), inner)
    canvas.save(dst, "PNG")
else:
    im.save(dst, "PNG")
PYEOF

    cp "$ICON_TARGET" "$PIXMAP_DIR/ai-type-agent.png"
    python3 - "$ICON_TARGET" "$HOME/.local/share/icons/hicolor" << 'PYRESIZE'
import sys, os
from PIL import Image

src_icon, base_dir = sys.argv[1], sys.argv[2]
im = Image.open(src_icon).convert("RGBA")
for sz in (16, 32, 48, 64, 128, 256):
    out_dir = os.path.join(base_dir, f"{sz}x{sz}", "apps")
    os.makedirs(out_dir, exist_ok=True)
    resized = im.resize((sz, sz), Image.LANCZOS)
    resized.save(os.path.join(out_dir, "ai-type-agent.png"), "PNG")
PYRESIZE
    if [ -w "/usr/share/icons/hicolor/512x512/apps/ai-type-agent.png" ] || [ -w "/usr/share/icons/hicolor/512x512/apps" ]; then
        cp "$ICON_TARGET" /usr/share/icons/hicolor/512x512/apps/ai-type-agent.png 2>/dev/null || true
    fi
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
Icon=ai-type-agent
Terminal=false
Categories=Development;Utility;
StartupNotify=true
StartupWMClass=ai-type-agent
DESKTOP_EOF

chmod +x "$DESKTOP_FILE"

if [ -w "/usr/share/applications/ai-type-agent.desktop" ]; then
    cat <<DESKTOP_SYS_EOF > /usr/share/applications/ai-type-agent.desktop
[Desktop Entry]
Version=1.0
Type=Application
Name=AI Type Agent
GenericName=Agent Coder Client
Comment=Quan tri may chu va Agent Coding
Exec=$INSTALL_DIR/ai-type-agent %u
Icon=ai-type-agent
Terminal=false
Categories=Development;Utility;
StartupNotify=true
StartupWMClass=ai-type-agent
DESKTOP_SYS_EOF
fi

echo "6. Cap nhat co so du lieu ung dung Desktop va Icon Cache cua Ubuntu..."
update-desktop-database "$DESKTOP_DIR" 2>/dev/null || true
update-desktop-database /usr/share/applications 2>/dev/null || true
gtk-update-icon-cache -f -t "$HOME/.local/share/icons/hicolor" 2>/dev/null || true
gtk-update-icon-cache -f -t /usr/share/icons/hicolor 2>/dev/null || true

echo "=== CAI DAT THANH CONG ==="
echo "- Ung dung da xuat hien trong danh sach ung dung (App Menu / Dash) cua Ubuntu voi ten 'AI Type Agent'."
echo "- Co the chay truc tiep tu Terminal bang lenh: ai-type-agent (neu $HOME/.local/bin co trong PATH) hoac $INSTALL_DIR/ai-type-agent"
