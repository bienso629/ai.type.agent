#!/bin/bash
set -e

echo "=========================================================="
echo "    CAI DAT UNG DUNG MXH TU DONG CHO UBUNTU / DEBIAN     "
echo "=========================================================="

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEB_FILE="$CURRENT_DIR/mxh-tu-dong_1.0.0_amd64.deb"

if [ ! -f "$DEB_FILE" ]; then
    echo "Loi: Khong tim thay file $DEB_FILE"
    exit 1
fi

echo "[1/3] Don dep phien ban cu va dong tien trinh cu neu co..."
pkill -9 -f "/opt/mxh-tu-dong/agent_mxh_auto" 2>/dev/null || true
pkill -9 -f "agent_mxh_auto" 2>/dev/null || true

# Go bo bang apt/dpkg neu package da cai dat
if dpkg -s mxh-tu-dong >/dev/null 2>&1; then
    echo "Dang go bo package debian cu..."
    sudo dpkg -P mxh-tu-dong || true
fi

# Xoa thu muc cai dat cu va symlink neu ton tai
echo "Dang xoa cac file cai dat cu con sot..."
sudo rm -rf /opt/mxh-tu-dong
sudo rm -f /usr/bin/mxh-tu-dong
sudo rm -f /usr/share/applications/mxh-tu-dong.desktop
sudo rm -f /usr/share/icons/hicolor/*/apps/mxh-tu-dong.*
sudo rm -f /usr/share/icons/hicolor/*/apps/agent.mxh.auto.*
sudo rm -f /usr/share/icons/hicolor/*/apps/agent_mxh_auto.*

# Xoa cac file de lai trong user local neu co
rm -f ~/.local/share/applications/agent.mxh.auto.desktop

echo "[2/3] Tien hanh cai dat ban moi tu goi .deb..."
sudo dpkg -i "$DEB_FILE" || sudo apt-get install -f -y

# Dong bo ban chay local cho nguoi dung hien tai de phong loi quyen /opt
mkdir -p ~/.local/share/mxh-tu-dong
cp -r /opt/mxh-tu-dong/* ~/.local/share/mxh-tu-dong/ 2>/dev/null || true
mkdir -p ~/.local/bin
cat << 'RUNNER_EOF' > ~/.local/bin/mxh-tu-dong
#!/bin/bash
export GDK_BACKEND=x11
if [ -x "/opt/mxh-tu-dong/agent_mxh_auto" ]; then
    exec /opt/mxh-tu-dong/agent_mxh_auto "$@"
elif [ -x "$HOME/.local/share/mxh-tu-dong/agent_mxh_auto" ]; then
    exec "$HOME/.local/share/mxh-tu-dong/agent_mxh_auto" "$@"
fi
RUNNER_EOF
chmod +x ~/.local/bin/mxh-tu-dong

mkdir -p ~/.local/share/applications
cat << 'USER_DESK_EOF' > ~/.local/share/applications/mxh-tu-dong.desktop
[Desktop Entry]
Name=Diễn viên MXH
Comment=Diễn viên MXH
Exec=/home/yenai/.local/bin/mxh-tu-dong %u
Icon=mxh-tu-dong
Terminal=false
Type=Application
Categories=Utility;
StartupNotify=true
StartupWMClass=agent.mxh.auto
USER_DESK_EOF
chmod +x ~/.local/share/applications/mxh-tu-dong.desktop

echo "[3/3] Lam moi cache icon va desktop entry..."
for s in 16 24 32 48 64 128 256 512; do
    mkdir -p ~/.local/share/icons/hicolor/${s}x${s}/apps
    cp /usr/share/icons/hicolor/${s}x${s}/apps/mxh-tu-dong.png ~/.local/share/icons/hicolor/${s}x${s}/apps/ 2>/dev/null || true
done
mkdir -p ~/.local/share/pixmaps
cp /usr/share/pixmaps/mxh-tu-dong.png ~/.local/share/pixmaps/ 2>/dev/null || true
cp /usr/share/icons/hicolor/index.theme ~/.local/share/icons/hicolor/index.theme 2>/dev/null || true

sudo gtk-update-icon-cache -f -t /usr/share/icons/hicolor 2>/dev/null || true
sudo update-desktop-database /usr/share/applications 2>/dev/null || true
gtk-update-icon-cache -f ~/.local/share/icons/hicolor 2>/dev/null || true
update-desktop-database ~/.local/share/applications 2>/dev/null || true

echo "=========================================================="
echo " CAI DAT THANH CONG!"
echo " - Duong dan thuc thi: /usr/bin/mxh-tu-dong"
echo " - Hoac mo truc tiep tu Menu Ung dung: 'Diễn viên MXH'"
echo "=========================================================="
