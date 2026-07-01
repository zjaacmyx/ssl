#!/bin/bash
set -e

echo "========================================="
echo "    天诚复印机经营部 - VPS 证书一键配置"
echo "========================================="

# 核心修改：优先获取命令后面的第一个参数作为域名，如果没有传参，再弹出提示让人输入
if [ -n "$1" ]; then
    DOMAIN="$1"
    echo "已通过参数指定域名: $DOMAIN"
else
    read -p "请输入您要配置的域名 (例如 vpu.baby): " DOMAIN
fi

if [ -z "$DOMAIN" ]; then 
    echo "错误：域名不能为空！"
    exit 1
fi

echo ""
echo "====> [1/3] 正在安装基础环境 (Certbot)..."
apt-get update && apt-get install certbot psmisc nginx -y

echo ""
echo "====> [2/3] 正在释放 80 端口并申请/验证 SSL 证书..."
[ -f /lib/systemd/system/nginx.service ] && systemctl stop nginx || true
[ -f /lib/systemd/system/apache2.service ] && systemctl stop apache2 || true

certbot certonly --standalone -d "$DOMAIN" --register-unsafely-without-email --agree-tos --keep-until-expiring || true

if [ ! -f "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" ]; then 
    echo "错误：证书不存在，请检查域名A记录解析！"
    systemctl start nginx || true
    exit 1
fi

echo ""
echo "====> [3/3] 正在全自动写入双通道 Nginx 配置文件..."

cat << 'NET_EOF' > /etc/nginx/sites-available/default
# 1. 域名的 HTTP 自动强转 HTTPS
server {
    listen 80;
    server_name MY_DOMAIN_PLACEHOLDER;
    return 301 https://$host$request_uri;
}

# 2. 域名的 HTTPS 加密通道
server {
    listen 443 ssl;
    server_name MY_DOMAIN_PLACEHOLDER;

    ssl_certificate /etc/letsencrypt/live/MY_DOMAIN_PLACEHOLDER/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/MY_DOMAIN_PLACEHOLDER/privkey.pem;
    ssl_session_timeout 5m;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-RSA-AES128-GCM-SHA256:HIGH:!aNULL:!MD5:!RC4:!DHE;

    location / {
        root /var/www/html;
        index index.html index.htm;
    }
}

# 3. 专门给纯 IP 留的 HTTP 直通车（不进行任何跳转）
server {
    listen 80 default_server;
    server_name _;

    location / {
        root /var/www/html;
        index index.html index.htm;
    }
}
NET_EOF

sed -i "s/MY_DOMAIN_PLACEHOLDER/$DOMAIN/g" /etc/nginx/sites-available/default

echo ""
echo "====> 正在测试 Nginx 语法并启动服务..."
nginx -t && systemctl restart nginx || systemctl start nginx

echo "========================================="
echo "恭喜！域名 $DOMAIN 的 HTTPS 与 纯IP 双通道配置已全部完成！"
echo "您的文件存放在 VPS 的: /var/www/html 目录下"
echo "-> 域名加密通道: https://$DOMAIN/menu.bat"
echo "-> 纯IP备用通道: http://你的VPS_IP/menu.bat"
echo "========================================="
