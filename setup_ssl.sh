cat << 'EOF' > /root/setup_ssl.sh
#!/bin/bash
set -e

# 1. 让用户输入域名
echo "========================================="
echo "    天诚复印机经营部 - VPS 证书一键配置"
echo "========================================="
read -p "请输入您要配置的域名 (例如 vpu.baby): " DOMAIN

if [ -z "$DOMAIN" ]; then
    echo "错误：域名不能为空！"
    exit 1
fi

echo ""
echo "====> [1/4] 正在安装基础环境 (Certbot & psmisc)..."
apt-get update && apt-get install certbot psmisc nginx -y

echo ""
echo "====> [2/4] 正在检查并暂时关闭 Web 服务以释放 80 端口..."
[ -f /lib/systemd/system/nginx.service ] && systemctl stop nginx || true
[ -f /lib/systemd/system/apache2.service ] && systemctl stop apache2 || true

echo ""
echo "====> [3/4] 正在申请/验证 SSL 证书..."
# 使用 standalone 模式申请，并支持如果已有证书则自动重用/续期
certbot certonly --standalone -d "$DOMAIN" --register-unsafely-without-email --agree-tos --keep-until-expiring || true

# 检查证书是否真的存在
if [ ! -f "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" ]; then
    echo "错误：证书申请失败，请检查域名解析(A记录)是否正确指向本服务器！"
    # 尝试恢复 Nginx
    systemctl start nginx || true
    exit 1
fi

echo ""
echo "====> [4/4] 正在全自动写入 Nginx 配置文件..."
# 写入全新的 Nginx 配置，统一使用用户输入的域名
cat << 'NET_EOF' > /etc/nginx/sites-available/default
server {
    listen 80;
    server_name $DOMAIN;
    # 强制所有 http 请求跳转到 https
    return 301 https://$host$request_uri;
}

server {
    listen 443 ssl;
    server_name $DOMAIN;

    # SSL 证书路径配置
    ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;

    # 现代安全协议优化
    ssl_session_timeout 5m;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-RSA-AES128-GCM-SHA256:HIGH:!aNULL:!MD5:!RC4:!DHE;

    # 脚本文件存放根目录
    location / {
        root /var/www/html;
        index index.html index.htm;
    }
}
NET_EOF

# 替换 Nginx 配置文件中的变量
sed -i "s/\$DOMAIN/$DOMAIN/g" /etc/nginx/sites-available/default

echo ""
echo "====> 正在测试 Nginx 语法并启动服务..."
nginx -t
systemctl restart nginx

echo "========================================="
echo "恭喜！域名 $DOMAIN 的 HTTPS 自动化配置已全部完成！"
echo "您的文件存放在 VPS 的: /var/www/html 目录下"
echo "现在可以用 https://$DOMAIN/ 访问您的脚本了。"
echo "========================================="
EOF
