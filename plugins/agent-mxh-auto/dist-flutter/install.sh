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
rm -f ~/.local/share/applications/mxh-tu-dong.desktop
rm -f ~/.local/share/applications/agent.mxh.auto.desktop
rm -f ~/.local/share/icons/hicolor/*/apps/mxh-tu-dong.png
rm -f ~/.local/share/icons/hicolor/*/apps/agent.mxh.auto.png
rm -f ~/.local/share/icons/hicolor/*/apps/agent_mxh_auto.png

echo "[2/3] Tien hanh cai dat ban moi tu goi .deb..."
sudo dpkg -i "$DEB_FILE" || sudo apt-get install -f -y

echo "[3/3] Lam moi cache icon va desktop entry..."
sudo gtk-update-icon-cache -f -t /usr/share/icons/hicolor 2>/dev/null || true
sudo update-desktop-database /usr/share/applications 2>/dev/null || true
gtk-update-icon-cache -f -t ~/.local/share/icons/hicolor 2>/dev/null || true
update-desktop-database ~/.local/share/applications 2>/dev/null || true

echo "=========================================================="
echo " CAI DAT THANH CONG!"
echo " - Duong dan thuc thi: /usr/bin/mxh-tu-dong"
echo " - Hoac mo truc tiep tu Menu Ung dung: 'MXH Tự Động'"
echo "=========================================================="
