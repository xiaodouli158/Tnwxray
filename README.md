# Nginx + WebSocket + Xray 配置说明

本文档详细说明了如何使用 TLS 加密、 Nginx、WebSocket、VMess/VLess 协议来构建一个高效、稳定且安全的代理服务器。

## 架构概述

在这个架构中，我们结合了以下技术组件：

- **TLS**：加密客户端与 Nginx 之间的通信，确保数据的机密性和完整性
- **Nginx**：作为反向代理服务器，解密来自客户端的 HTTPS 流量，并将 WebSocket 请求转发到内部服务
- **WebSocket**：在客户端和代理服务器之间建立持续的双向连接
- **VMess/VLess**：通过 Xray 内部代理服务，处理 WebSocket 传输中的流量


## 流程说明

[Client] ⇄ TLS ⇄ [Nginx] ⇄ WebSocket ⇄ [V2Ray/Xray 内部服务]
   ↑                         ↑                        ↑
   |                         |                        |
    -----------------------> WebSocket 协议 <----------------------
   |                         |                        |
    -----> TLS 加密连接 -------> WebSocket 握手 ------->


1. 客户端通过 HTTPS（使用 TLS）与 Nginx 服务器建立安全连接
2. 客户端发起 WebSocket 协议的连接请求
3. Nginx 解密流量并将 WebSocket 请求转发给后端的 VMess/VLess 内部服务
4. 内部的 Xray 服务接收来自 Nginx 转发的流量，处理实际的协议转发
5. 整个过程中的流量都经过 TLS 加密，防止中间人攻击和流量泄露

## 关键配置文件

### 1. Xray 配置 (`/project/workspace/Xray/config.json`)

```json
{
  "log": {
    "access": "/project/workspace/Xray/access.log",
    "error": "/project/workspace/Xray/error.log",
    "loglevel": "warning"
  },
  "inbounds": [
    {
      "port": 10000,
      "listen": "127.0.0.1",
      "protocol": "vmess",
      "settings": {
        "clients": [
          {
            "id": "de04add9-5c68-8bab-950c-08cd5320df18",
            "alterId": 0
          }
        ]
      },
      "streamSettings": {
        "network": "ws",
        "wsSettings": {
          "path": "/vmess"
        }
      }
    },
    {
      "port": 20000,
      "listen": "127.0.0.1",
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "de04add9-5c68-8bab-950c-08cd5320df18"
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "ws",
        "wsSettings": {
          "path": "/vless"
        }
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "settings": {}
    }
  ],
  "dns": {
    "server": [
      "8.8.8.8",
      "8.8.4.4",
      "localhost"
    ]
  }
}
```

**关键配置点**：
- VMess 和 VLess 协议分别监听在 `127.0.0.1:10000` 和 `127.0.0.1:20000`
- 两种协议都使用 WebSocket 作为传输层
- WebSocket 路径分别为 `/vmess` 和 `/vless`
- 客户端认证使用 UUID: `de04add9-5c68-8bab-950c-08cd5320df18`

### 2. Nginx 配置 (`/project/workspace/Nginx/nginx.conf`)

```nginx
worker_processes  1;

# 使用绝对路径
error_log  /project/workspace/Nginx/logs/error.log;
pid        /project/workspace/Nginx/logs/nginx.pid;

events {
    worker_connections  1024;
}

http {
    include       mime.types;
    default_type  application/octet-stream;

    access_log  /project/workspace/Nginx/logs/access.log;
    sendfile        on;
    keepalive_timeout  65;

    # HTTP server for redirect to HTTPS
    server {
        listen       8080;
        server_name  localhost;
        return 301 https://$host:8443$request_uri;
    }

    # HTTPS server
    server {
        listen       8443 ssl;
        server_name  localhost;

        ssl_certificate      /project/workspace/Nginx/ssl/nginx.crt;
        ssl_certificate_key  /project/workspace/Nginx/ssl/nginx.key;
        ssl_protocols        TLSv1.2 TLSv1.3;
        ssl_ciphers          HIGH:!aNULL:!MD5;
        ssl_session_cache    shared:SSL:10m;
        ssl_session_timeout  10m;

        location / {
            root   /project/workspace/Nginx/html;
            index  index.html index.htm;
        }

        # VMess WebSocket configuration
        location /vmess {
            proxy_redirect off;
            proxy_pass http://127.0.0.1:10000;
            proxy_http_version 1.1;
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection "upgrade";
            proxy_set_header Host $http_host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        }

        # VLess WebSocket configuration
        location /vless {
            proxy_redirect off;
            proxy_pass http://127.0.0.1:20000;
            proxy_http_version 1.1;
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection "upgrade";
            proxy_set_header Host $http_host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        }

        error_page   500 502 503 504  /50x.html;
        location = /50x.html {
            root   /project/workspace/Nginx/html;
        }
    }
}
```

**关键配置点**：
- HTTP 服务器监听在端口 `8080`，自动重定向到 HTTPS
- HTTPS 服务器监听在端口 `8443`，使用 TLS 加密
- 配置了 WebSocket 代理，将 `/vmess` 和 `/vless` 路径的请求分别转发到 Xray 的对应服务
- 设置了 WebSocket 所需的 HTTP 头部，如 `Upgrade` 和 `Connection`

### 3. 配置更新脚本 (`/project/workspace/update-config.sh`)

```bash
#!/bin/bash

# This script updates the configuration with the actual server IP or domain

# Check if an argument is provided
if [ $# -eq 0 ]; then
    echo "Usage: $0 <server_ip_or_domain>"
    exit 1
fi

SERVER_ADDRESS=$1
UUID="de04add9-5c68-8bab-950c-08cd5320df18"

echo "Updating configuration with server address: $SERVER_ADDRESS"

# Update the HTML file
sed -i "s|Your server IP or domain|$SERVER_ADDRESS|g" /project/workspace/Nginx/html/index.html

# Generate VMess and VLess links
VMESS_LINK=$(echo -n "{\"v\":\"2\",\"ps\":\"VMess-WebSocket-TLS\",\"add\":\"$SERVER_ADDRESS\",\"port\":\"8443\",\"id\":\"$UUID\",\"aid\":\"0\",\"net\":\"ws\",\"type\":\"none\",\"host\":\"$SERVER_ADDRESS\",\"path\":\"/vmess\",\"tls\":\"tls\"}" | base64 -w 0)
VLESS_LINK="vless://$UUID@$SERVER_ADDRESS:8443?encryption=none&security=tls&type=ws&host=$SERVER_ADDRESS&path=/vless#VLess-WebSocket-TLS"

echo "Configuration updated successfully!"
echo ""
echo "VMess Link: vmess://$VMESS_LINK"
echo ""
echo "VLess Link: $VLESS_LINK"
echo ""
echo "You can now access the web interface at: https://$SERVER_ADDRESS:8443/"
```

**关键配置点**：
- 脚本接受服务器 IP 或域名作为参数
- 更新 HTML 文件中的服务器地址
- 生成 VMess 和 VLess 的客户端配置链接
- 显示访问 Web 界面的 URL

## 使用方法

### 1. 启动服务

```bash
cd /project/workspace
./start-services.sh
```

### 2. 更新配置

```bash
cd /project/workspace
./update-config.sh your-server-ip-or-domain
```

### 3. 客户端配置

使用 `update-config.sh` 脚本生成的链接配置客户端：

- **VMess 链接格式**：
  ```
  vmess://{Base64编码的配置}
  ```

- **VLess 链接格式**：
  ```
  vless://{UUID}@{服务器地址}:8443?encryption=none&security=tls&type=ws&host={服务器地址}&path=/vless#VLess-WebSocket-TLS
  ```

## 安全性考虑

1. **TLS 加密**：使用 TLS 1.2/1.3 协议和强加密套件，防止中间人攻击
2. **WebSocket 安全**：使用 WSS（WebSocket over TLS）协议，确保 WebSocket 连接的安全性
3. **证书管理**：当前使用自签名证书，生产环境建议使用受信任的 CA 颁发的证书
4. **UUID 安全**：当前使用固定的 UUID，建议生成新的随机 UUID 增强安全性

## 性能优化

1. **TLS 会话复用**：通过启用 TLS 会话复用，减少后续连接的建立时间
2. **WebSocket 持久连接**：WebSocket 是持久化连接，减少了连接建立的开销
3. **Nginx 缓存**：可以进一步配置 Nginx 的缓存机制，提高性能

## 故障排查

1. **检查服务状态**：
   ```bash
   ps aux | grep -E 'nginx|xray'
   ```

2. **检查端口监听**：
   ```bash
   netstat -tuln | grep -E '8080|8443|10000|20000'
   ```

3. **检查日志**：
   - Nginx 错误日志：`/project/workspace/Nginx/logs/error.log`
   - Xray 错误日志：`/project/workspace/Xray/error.log`

## 注意事项

1. 本配置使用的端口（8080、8443）可能需要根据实际环境调整
2. 自签名证书会导致浏览器警告，生产环境建议使用有效证书
3. 默认 UUID 应该更改为随机生成的值，以提高安全性
4. 在某些网络环境中，可能需要配合 Cloudflare CDN 使用，以提高连接成功率
