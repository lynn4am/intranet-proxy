#!/bin/bash

# 内网代理配置生成脚本
# 交互式收集参数，自动生成所有配置文件

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 获取脚本所在目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo -e "${BLUE}============================================${NC}"
echo -e "${BLUE}       内网代理配置生成工具${NC}"
echo -e "${BLUE}============================================${NC}"
echo ""

# 收集配置参数
echo -e "${YELLOW}请输入配置参数：${NC}"
echo ""

# 公网 VPS IP
read -p "公网 VPS IP 地址: " VPS_IP
while [[ -z "$VPS_IP" ]]; do
    echo -e "${RED}IP 地址不能为空${NC}"
    read -p "公网 VPS IP 地址: " VPS_IP
done

# frp 通信端口
read -p "frp 通信端口 [默认 7000]: " FRP_PORT
FRP_PORT=${FRP_PORT:-7000}

# xray 代理端口
read -p "xray 代理端口 [默认 9000]: " XRAY_PORT
XRAY_PORT=${XRAY_PORT:-9000}

# 加密方式选择
echo ""
echo "选择加密方式："
echo "  1) aes-128-gcm (推荐，兼容性好)"
echo "  2) aes-256-gcm"
echo "  3) chacha20-poly1305"
echo "  4) 2022-blake3-aes-128-gcm (更安全，需要新版客户端)"
echo "  5) 2022-blake3-aes-256-gcm"
echo "  6) 2022-blake3-chacha20-poly1305"
read -p "请选择 [1-6，默认 1]: " ENCRYPT_CHOICE
ENCRYPT_CHOICE=${ENCRYPT_CHOICE:-1}

case $ENCRYPT_CHOICE in
    1) ENCRYPT_METHOD="aes-128-gcm"; KEY_LEN=16 ;;
    2) ENCRYPT_METHOD="aes-256-gcm"; KEY_LEN=32 ;;
    3) ENCRYPT_METHOD="chacha20-poly1305"; KEY_LEN=32 ;;
    4) ENCRYPT_METHOD="2022-blake3-aes-128-gcm"; KEY_LEN=16 ;;
    5) ENCRYPT_METHOD="2022-blake3-aes-256-gcm"; KEY_LEN=32 ;;
    6) ENCRYPT_METHOD="2022-blake3-chacha20-poly1305"; KEY_LEN=32 ;;
    *) ENCRYPT_METHOD="aes-128-gcm"; KEY_LEN=16 ;;
esac

# 生成密码
echo ""
echo -e "${YELLOW}生成安全密钥...${NC}"
XRAY_PASSWORD=$(openssl rand -base64 $KEY_LEN)
FRP_TOKEN=$(openssl rand -base64 32)

echo ""
echo -e "${GREEN}============================================${NC}"
echo -e "${GREEN}配置参数确认：${NC}"
echo -e "${GREEN}============================================${NC}"
echo "  公网 VPS IP:    $VPS_IP"
echo "  frp 通信端口:   $FRP_PORT"
echo "  xray 代理端口:  $XRAY_PORT"
echo "  加密方式:       $ENCRYPT_METHOD"
echo "  xray 密码:      $XRAY_PASSWORD"
echo "  frp Token:      $FRP_TOKEN"
echo ""

read -p "确认生成配置？[Y/n]: " CONFIRM
CONFIRM=${CONFIRM:-Y}
if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
    echo "已取消"
    exit 0
fi

echo ""
echo -e "${YELLOW}生成配置文件...${NC}"

# =====================
# 生成 .env 文件
# =====================
cat > "$SCRIPT_DIR/.env" << EOF
# 内网代理配置
# 由 setup.sh 自动生成于 $(date)

# 公网 VPS
VPS_IP=$VPS_IP
FRP_PORT=$FRP_PORT

# xray 配置
XRAY_PORT=$XRAY_PORT
XRAY_PASSWORD=$XRAY_PASSWORD
ENCRYPT_METHOD=$ENCRYPT_METHOD

# frp 认证
FRP_TOKEN=$FRP_TOKEN
EOF

echo "  ✓ .env"

# =====================
# 生成 server/frps.toml
# =====================
cat > "$SCRIPT_DIR/server/frps.toml" << EOF
# frp 服务端配置
# 部署在公网 VPS 上

bindPort = $FRP_PORT
auth.token = "$FRP_TOKEN"

# 日志配置
log.to = "console"
log.level = "info"
EOF

echo "  ✓ server/frps.toml"

# =====================
# 生成 server/docker-compose.yml
# =====================
cat > "$SCRIPT_DIR/server/docker-compose.yml" << EOF
version: '3.8'

services:
  frps:
    image: snowdreamtech/frps
    container_name: frps
    restart: always
    ports:
      - "$FRP_PORT:$FRP_PORT"      # frp 通信端口
      - "$XRAY_PORT:$XRAY_PORT"    # xray 代理端口（转发到内网）
    volumes:
      - ./frps.toml:/etc/frp/frps.toml
    command: ["-c", "/etc/frp/frps.toml"]
EOF

echo "  ✓ server/docker-compose.yml"

# =====================
# 生成 client/xray-config.json
# =====================
cat > "$SCRIPT_DIR/client/xray-config.json" << EOF
{
  "inbounds": [
    {
      "port": $XRAY_PORT,
      "protocol": "shadowsocks",
      "settings": {
        "method": "$ENCRYPT_METHOD",
        "password": "$XRAY_PASSWORD",
        "network": "tcp,udp"
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom"
    }
  ]
}
EOF

echo "  ✓ client/xray-config.json"

# =====================
# 生成 client/frpc.toml
# =====================
cat > "$SCRIPT_DIR/client/frpc.toml" << EOF
# frp 客户端配置
# 部署在内网机器上

serverAddr = "$VPS_IP"
serverPort = $FRP_PORT
auth.token = "$FRP_TOKEN"

# 日志配置
log.to = "console"
log.level = "info"

# xray 代理端口转发
[[proxies]]
name = "xray-proxy"
type = "tcp"
localIP = "xray"
localPort = $XRAY_PORT
remotePort = $XRAY_PORT
EOF

echo "  ✓ client/frpc.toml"

# =====================
# 生成 client/docker-compose.yml
# =====================
cat > "$SCRIPT_DIR/client/docker-compose.yml" << EOF
version: '3.8'

services:
  xray:
    image: teddysun/xray
    container_name: xray
    restart: always
    volumes:
      - ./xray-config.json:/etc/xray/config.json
    networks:
      - proxy-net

  frpc:
    image: snowdreamtech/frpc
    container_name: frpc
    restart: always
    depends_on:
      - xray
    volumes:
      - ./frpc.toml:/etc/frp/frpc.toml
    command: ["-c", "/etc/frp/frpc.toml"]
    networks:
      - proxy-net

networks:
  proxy-net:
    driver: bridge
EOF

echo "  ✓ client/docker-compose.yml"

# =====================
# 生成 user/clash-config.yaml
# =====================
cat > "$SCRIPT_DIR/user/clash-config.yaml" << EOF
# Clash 配置片段
# 将以下内容添加到你的 Clash 配置中

# 在 proxies 部分添加：
proxies:
  - name: "内网代理"
    type: ss
    server: $VPS_IP
    port: $XRAY_PORT
    cipher: $ENCRYPT_METHOD
    password: "$XRAY_PASSWORD"

# 在 proxy-groups 部分添加（可选）：
# proxy-groups:
#   - name: "内网访问"
#     type: select
#     proxies:
#       - 内网代理

# 在 rules 部分添加（可选，按需配置内网 IP 段）：
# rules:
#   - IP-CIDR,10.0.0.0/8,内网代理
#   - IP-CIDR,172.16.0.0/12,内网代理
#   - IP-CIDR,192.168.0.0/16,内网代理
EOF

echo "  ✓ user/clash-config.yaml"

# =====================
# 生成 user/xray-config.json
# =====================
cat > "$SCRIPT_DIR/user/xray-config.json" << EOF
{
  "inbounds": [
    {
      "port": 1080,
      "protocol": "socks",
      "settings": {
        "udp": true
      }
    },
    {
      "port": 1081,
      "protocol": "http"
    }
  ],
  "outbounds": [
    {
      "protocol": "shadowsocks",
      "settings": {
        "servers": [
          {
            "address": "$VPS_IP",
            "port": $XRAY_PORT,
            "method": "$ENCRYPT_METHOD",
            "password": "$XRAY_PASSWORD"
          }
        ]
      }
    }
  ]
}
EOF

echo "  ✓ user/xray-config.json"

# =====================
# 完成
# =====================
echo ""
echo -e "${GREEN}============================================${NC}"
echo -e "${GREEN}配置生成完成！${NC}"
echo -e "${GREEN}============================================${NC}"
echo ""
echo -e "${BLUE}下一步操作：${NC}"
echo ""
echo "1. 部署公网 VPS："
echo "   scp -r server/ user@$VPS_IP:/opt/intranet-proxy/"
echo "   ssh user@$VPS_IP 'cd /opt/intranet-proxy && docker-compose up -d'"
echo ""
echo "2. 部署内网机器："
echo "   cd client/ && docker-compose up -d"
echo ""
echo "3. 配置 Mac 客户端："
echo "   - Clash: 参考 user/clash-config.yaml"
echo "   - xray:  使用 user/xray-config.json"
echo ""
echo -e "${YELLOW}注意：请确保 VPS 防火墙开放端口 $FRP_PORT 和 $XRAY_PORT${NC}"
