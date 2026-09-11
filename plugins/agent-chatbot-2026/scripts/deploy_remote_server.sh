#!/bin/bash
set -e

# ==============================================================================
# Script dong goi va deploy len Website Server tu xa (Remote Server)
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

SERVER_HOST="${1:-103.74.116.119}"
SERVER_PORT="${2:-7878}"
SERVER_USER="${3:-root}"
REMOTE_PATH="${4:-/opt/agent-chatbot-2026}"

echo "=========================================================="
echo "  Deploy AI Agent Chatbot 2026 len Remote Server"
echo "  Server: $SERVER_USER@$SERVER_HOST:$SERVER_PORT"
echo "  Remote Directory: $REMOTE_PATH"
echo "=========================================================="

# 1. Tao goi bundle nhe gom ma nguon Backend va kien truc Docker
TMP_DEPLOY_DIR="/tmp/agent-chatbot-deploy-$(date +%s)"
mkdir -p "$TMP_DEPLOY_DIR"

echo "--> [1/4] Chuan bi tep tin backend va cau hinh he thong..."
cp -r "$ROOT_DIR/backend-cloud-sync" "$TMP_DEPLOY_DIR/"
cp "$ROOT_DIR/web_server_deploy.md" "$TMP_DEPLOY_DIR/"

# Tao file docker-compose production cho server
cat << 'DOCKER_PROD_EOF' > "$TMP_DEPLOY_DIR/docker-compose.server.yml"
version: '3.8'

services:
  agent-db:
    image: mariadb:10.6
    container_name: agent-chatbot-mysql
    restart: always
    environment:
      MYSQL_ROOT_PASSWORD: RootSecurePass2026!
      MYSQL_DATABASE: agent_chatbot_db
      MYSQL_USER: agent_user
      MYSQL_PASSWORD: AgentPass2026!
    volumes:
      - agent_cloud_db_data:/var/lib/mysql
      - ./backend-cloud-sync/database/schema.sql:/docker-entrypoint-initdb.d/init.sql:ro
    networks:
      - agent-net

  agent-backend:
    build:
      context: ./backend-cloud-sync
      dockerfile: Dockerfile
    container_name: agent-chatbot-backend
    restart: always
    environment:
      DB_HOST: agent-db
      DB_PORT: 3306
      DB_NAME: agent_chatbot_db
      DB_USER: agent_user
      DB_PASS: AgentPass2026!
    ports:
      - "8888:80"
    depends_on:
      - agent-db
    networks:
      - agent-net

volumes:
  agent_cloud_db_data:

networks:
  agent-net:
    driver: bridge
DOCKER_PROD_EOF

# 2. Dong goi thanh archive
ARCHIVE_NAME="agent-chatbot-server-deploy.tar.gz"
echo "--> [2/4] Dong goi bundle: $ARCHIVE_NAME..."
cd "$TMP_DEPLOY_DIR"
tar -czf "$ROOT_DIR/dist/$ARCHIVE_NAME" .
rm -rf "$TMP_DEPLOY_DIR"

echo "--> [3/4] File deploy san sang tai: $ROOT_DIR/dist/$ARCHIVE_NAME"
ls -lh "$ROOT_DIR/dist/$ARCHIVE_NAME"

echo ""
echo "--> [4/4] Lenh day len Server va khoi chay:"
echo "    scp -P $SERVER_PORT $ROOT_DIR/dist/$ARCHIVE_NAME $SERVER_USER@$SERVER_HOST:/tmp/"
echo "    ssh -p $SERVER_PORT $SERVER_USER@$SERVER_HOST \"mkdir -p $REMOTE_PATH && tar -xzf /tmp/$ARCHIVE_NAME -C $REMOTE_PATH && cd $REMOTE_PATH && docker compose -f docker-compose.server.yml up -d --build\""
echo "=========================================================="
echo "  San sang trien khai!"
echo "=========================================================="
