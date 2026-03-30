#!/bin/bash
# Modified version - uses workspace instead of /opt

set -e

# Конфигурация - используем workspace
CLIENT_ID=${CLIENT_ID:-"test-client-1"}
CLIENT_DIR="/home/gorcer/.openclaw/workspace/clients/${CLIENT_ID}"
IMAGE_NAME="openclaw-client-${CLIENT_ID}"

# Переменные окружения клиента
TELEGRAM_BOT_TOKEN="${TELEGRAM_BOT_TOKEN}"
MINIMAX_API_KEY="${MINIMAX_API_KEY}"
YANDEX_API_KEY="${YANDEX_API_KEY}"
YANDEX_FOLDER_ID="${YANDEX_FOLDER_ID}"
PROXY_OUTBOUND="${PROXY_OUTBOUND:-""}"

echo "=== OpenClaw Client Deployment ==="
echo "Client ID: ${CLIENT_ID}"
echo "Client Dir: ${CLIENT_DIR}"

# Пропускаем проверку root для тестирования
#if [ "$EUID" -ne 0 ]; then
#    echo "Запустите от root: sudo $0"
#    exit 1
#fi

# Проверка что Docker работает
if ! docker info > /dev/null 2>&1; then
    echo "Ошибка: Docker не работает"
    exit 1
fi

# Создание директории клиента
mkdir -p "${CLIENT_DIR}/workspace"
mkdir -p "${CLIENT_DIR}/logs"
mkdir -p "${CLIENT_DIR}/xray"

# === XRAY CONFIG ===
cat > "${CLIENT_DIR}/xray/config.json" << 'EOF'
{
  "log": {
    "access": "/var/log/xray/access.log",
    "error": "/var/log/xray/error.log",
    "loglevel": "warning"
  },
  "inbounds": [
    {
      "tag": "socks-inbound",
      "port": 10808,
      "listen": "0.0.0.0",
      "protocol": "socks",
      "settings": {
        "auth": "noauth",
        "udp": true,
        "ip": "127.0.0.1"
      }
    },
    {
      "tag": "http-inbound",
      "port": 10809,
      "listen": "0.0.0.0",
      "protocol": "http",
      "settings": {
        "timeout": 0
      }
    }
  ],
  "outbounds": [
    {
      "tag": "direct",
      "protocol": "freedom",
      "settings": {}
    },
    {
      "tag": "block",
      "protocol": "blackhole",
      "settings": {}
    }
  ]
}
EOF

# === DOCKERFILE ===
cat > "${CLIENT_DIR}/Dockerfile" << 'EOF'
FROM node:20-alpine

WORKDIR /app

RUN apk add --no-cache bash git curl wget

RUN wget -q https://github.com/XTLS/Xray/releases/download/v1.8.6/xray-linux-64.zip && \
    unzip -q xray-linux-64.zip -d /usr/local/bin && \
    rm xray-linux-64.zip && \
    mv /usr/local/bin/xray /usr/local/bin/xray_main && \
    ln -s /usr/local/bin/xray_main /usr/local/bin/xray

RUN git clone https://github.com/openclaw/openclaw.git /app/openclaw

WORKDIR /app/openclaw

RUN npm install --production

RUN adduser -D -u 1000 client

USER 1000

CMD ["/bin/sh", "-c", "xray -config /app/xray/config.json &; npm start"]
EOF

# === DOCKER-COMPOSE ===
cat > "${CLIENT_DIR}/docker-compose.yml" << EOF
version: '3.8'

services:
  xray:
    image: teddysun/xray:latest
    container_name: ${IMAGE_NAME}-xray
    volumes:
      - ./xray/config.json:/etc/xray/config.json
      - ./logs/xray:/var/log/xray
    ports:
      - "127.0.0.1:10808:10808"
      - "127.0.0.1:10809:10809"
    networks:
      - openclaw_net
    restart: unless-stopped
    mem_limit: 128m
    cpu_shares: 128
    read_only: true
    no_new_privileges: true

  openclaw:
    build: .
    container_name: ${IMAGE_NAME}
    environment:
      - TELEGRAM_BOT_TOKEN=${TELEGRAM_BOT_TOKEN}
      - MINIMAX_API_KEY=${MINIMAX_API_KEY}
      - YANDEX_API_KEY=${YANDEX_API_KEY}
      - YANDEX_FOLDER_ID=${YANDEX_FOLDER_ID}
      - HTTP_PROXY=http://xray:10809
      - HTTPS_PROXY=http://xray:10809
      - SOCKS_PROXY=socks5://xray:10808
    volumes:
      - ./workspace:/app/openclaw/workspace
      - ./logs:/app/openclaw/logs
    depends_on:
      - xray
    networks:
      - openclaw_net
    mem_limit: 512m
    cpu_shares: 256
    read_only: true
    no_new_privileges: true
    network_mode: bridge
    pids_limit: 100
    restart: unless-stopped

networks:
  openclaw_net:
    driver: bridge
EOF

echo "Сборка контейнера..."
cd "${CLIENT_DIR}"
docker compose build

echo "Запуск контейнера..."
docker compose up -d

echo "=== Клиент ${CLIENT_ID} запущен ==="
echo "Xray SOCKS5: 127.0.0.1:10808"
echo "Xray HTTP: 127.0.0.1:10809"
echo "Проверить статус: docker ps | grep ${IMAGE_NAME}"
echo "Логи: docker logs ${IMAGE_NAME}"
