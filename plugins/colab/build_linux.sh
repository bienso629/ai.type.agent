#!/bin/bash
set -e
echo "Building Colab Agent Linux Executable..."
pyinstaller colab_agent_linux.spec --clean

echo "Packaging complete! Copying to user plugins directory..."
mkdir -p /home/yenai/Documents/ai.type/plugins
cp dist/colab_agent_linux /home/yenai/Documents/ai.type/plugins/colab_agent_linux
chmod +x /home/yenai/Documents/ai.type/plugins/colab_agent_linux

echo "✅ Đã đóng gói thành công và đưa vào Documents/ai.type/plugins/colab_agent_linux"
