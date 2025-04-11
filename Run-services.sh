#!/bin/bash

# 设置服务器地址（域名）
SERVER_ADDRESS="p7cvhp-8080.csb.app"
UUID="de04add9-5c68-8bab-950c-08cd5320df18"

echo "=== 配置和启动服务 ==="
echo "服务器地址: $SERVER_ADDRESS"
echo "UUID: $UUID"
echo ""

# 更新配置
echo "正在更新配置..."

# 更新HTML文件中的配置
sed -i "s|Server Address: .*|Server Address: $SERVER_ADDRESS|g" /project/workspace/Nginx/html/index.html
sed -i "s|\"add\": \".*\",|\"add\": \"$SERVER_ADDRESS\",|g" /project/workspace/Nginx/html/index.html
sed -i "s|\"host\": \".*\",|\"host\": \"$SERVER_ADDRESS\",|g" /project/workspace/Nginx/html/index.html
sed -i "s|\"port\": \".*\",|\"port\": \"8443\",|g" /project/workspace/Nginx/html/index.html
sed -i "s|vless://[^@]*@[^:]*|vless://$UUID@$SERVER_ADDRESS|g" /project/workspace/Nginx/html/index.html
sed -i "s|host=[^&]*|host=$SERVER_ADDRESS|g" /project/workspace/Nginx/html/index.html

# 生成VMess和VLess链接
VMESS_LINK=$(echo -n "{\"v\":\"2\",\"ps\":\"VMess-WebSocket-TLS\",\"add\":\"$SERVER_ADDRESS\",\"port\":\"8443\",\"id\":\"$UUID\",\"aid\":\"0\",\"net\":\"ws\",\"type\":\"none\",\"host\":\"$SERVER_ADDRESS\",\"path\":\"/vmess\",\"tls\":\"tls\"}" | base64 -w 0)
VLESS_LINK="vless://$UUID@$SERVER_ADDRESS:8443?encryption=none&security=tls&type=ws&host=$SERVER_ADDRESS&path=/vless#VLess-WebSocket-TLS"

# 停止可能已经运行的服务
echo "正在停止已运行的服务..."
pkill -f xray || true
pkill -f nginx || true

# 强制杀死可能占用端口的进程
echo "强制释放端口..."
# 尝试杀死所有可能的进程
killall -9 nginx 2>/dev/null || true
killall -9 xray 2>/dev/null || true

# 等待进程完全停止
sleep 3

# 启动Xray服务
echo "正在启动Xray服务..."
cd /project/workspace/Xray
./xray -config config.json > /dev/null 2>&1 &
XRAY_PID=$!
echo "Xray已启动，PID: $XRAY_PID"

# 等待Xray初始化
sleep 2

# 启动Nginx服务
echo "正在启动Nginx服务..."
cd /project/workspace/Nginx
./nginx-static -c nginx.conf > /dev/null 2>&1 &
NGINX_PID=$!
echo "Nginx已启动，PID: $NGINX_PID"

# 显示配置信息
echo ""
echo "=== 所有服务已启动 ==="
echo "配置详情:"
echo "服务器地址: $SERVER_ADDRESS"
echo "VMess WebSocket路径: /vmess"
echo "VLess WebSocket路径: /vless"
echo "UUID: $UUID"
echo ""
echo "VMess链接: vmess://$VMESS_LINK"
echo ""
echo "VLess链接: $VLESS_LINK"
echo ""
echo "您可以通过以下地址访问Web界面: https://$SERVER_ADDRESS:8443/"
echo ""
echo "=== 服务启动完成 ==="
