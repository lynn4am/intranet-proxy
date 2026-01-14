# 内网代理 (Intranet Proxy)

通过 frp + xray 将内网服务代理到公网，实现在家访问公司/内网资源。

## 架构图

```
┌──────────────────┐      ┌──────────────────┐      ┌──────────────────────────┐
│     家里 Mac     │      │    公网 VPS      │      │        内网机器          │
│                  │      │                  │      │                          │
│  ┌────────────┐  │      │  ┌────────────┐  │      │  ┌────────┐  ┌────────┐  │
│  │clash/xray  │──┼─────▶│  │   frps     │◀─┼──────┼──│  frpc  │──│  xray  │  │
│  │  client    │  │      │  │  :7000     │  │      │  │        │  │ :9000  │  │
│  └────────────┘  │      │  └────────────┘  │      │  └────────┘  └────────┘  │
│                  │      │        │         │      │                    │     │
└──────────────────┘      │        ▼         │      │                    ▼     │
                          │   公网端口 :9000  │      │              内网服务    │
                          └──────────────────┘      └──────────────────────────┘

数据流: Mac → 公网VPS:9000 → frps → frpc → xray:9000 → 内网
```

## 组件说明

| 组件 | 作用 | 部署位置 |
|------|------|----------|
| **frps** | frp 服务端，接收 frpc 连接并转发流量 | 公网 VPS |
| **frpc** | frp 客户端，将内网端口映射到公网 | 内网机器 |
| **xray** | 代理服务器，提供 Shadowsocks 协议加密 | 内网机器 |
| **clash/xray** | 代理客户端，连接公网代理 | 你的 Mac |

## 快速开始

### 1. 生成配置

```bash
# 克隆项目
git clone <repo-url>
cd intranet-proxy

# 运行配置生成脚本（交互式）
./setup.sh
```

脚本会询问以下信息并自动生成所有配置：
- 公网 VPS IP 地址
- frp 通信端口（默认 7000）
- xray 代理端口（默认 9000）
- 加密方式（默认 aes-128-gcm）

### 2. 部署公网 VPS

```bash
# 将 server/ 目录复制到 VPS
scp -r server/ user@your-vps:/opt/intranet-proxy/

# SSH 到 VPS 启动服务
ssh user@your-vps
cd /opt/intranet-proxy
docker-compose up -d

# 检查状态
docker-compose logs -f
```

### 3. 部署内网机器

```bash
cd client/
docker-compose up -d

# 检查状态
docker-compose logs -f
```

### 4. 配置客户端 (Mac)

配置文件已生成在 `user/` 目录：

**方式 A: Clash**
- 将 `user/clash-config.yaml` 内容添加到你的 Clash 配置中

**方式 B: xray**
- 使用 `user/xray-config.json` 作为客户端配置

## 目录结构

```
intranet-proxy/
├── README.md              # 本文档
├── setup.sh               # 配置生成脚本
├── .env.example           # 环境变量模板
│
├── server/                # 公网 VPS
│   ├── docker-compose.yml
│   └── frps.toml
│
├── client/                # 内网机器
│   ├── docker-compose.yml
│   ├── frpc.toml
│   └── xray-config.json
│
└── user/                  # Mac 客户端配置
    ├── clash-config.yaml
    └── xray-config.json
```

## 故障排查

### 1. frpc 无法连接 frps

```bash
# 内网机器上检查 frpc 日志
docker logs frpc

# 常见原因：
# - VPS 防火墙未开放 frp 端口
# - frp token 不匹配
# - VPS IP 或端口配置错误
```

### 2. 客户端无法连接代理

```bash
# 检查 xray 是否正常运行
docker logs xray

# 检查公网端口是否开放
nc -zv your-vps-ip 9000

# 常见原因：
# - VPS 防火墙未开放代理端口
# - xray 密码配置错误
# - frp 代理未正确映射
```

### 3. 连接成功但无法访问内网

```bash
# 进入 xray 容器测试内网连通性
docker exec -it xray sh
ping 内网IP

# 常见原因：
# - xray 容器网络配置问题
# - 内网防火墙限制
```

## 常用命令

```bash
# 启动服务
docker-compose up -d

# 停止服务
docker-compose down

# 查看日志
docker-compose logs -f

# 重启服务
docker-compose restart

# 查看运行状态
docker-compose ps
```

## 参考链接

- [frp 官方文档](https://gofrp.org/zh-cn/docs/)
- [xray Shadowsocks 配置](https://xtls.github.io/config/inbounds/shadowsocks.html)
- [teddysun/xray Docker 镜像](https://hub.docker.com/r/teddysun/xray)
