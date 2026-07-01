#!/bin/bash
# 如果含有回车符，立即原地解毒并重新载入
if echo "$0" | grep -q 'ssl' && grep -q $'\r' "$0"; then sed -i 's/\r//g' "$0"; exec bash "$0" "$@"; exit; fi

set -e
echo "========================================="
echo "    天诚复印机经营部 - VPS 证书一键配置"
echo "========================================="
read -p "请输入您要配置的域名 (例如 vpu.baby): " DOMAIN
if [ -z "$DOMAIN" ]; then echo "错误：域名不能为空！"; exit 1; fi
echo ""
echo "====> [1/3] 正在安装基础环境 (Certbot)..."
apt-get update && apt-get install certbot psmisc nginx -y
echo ""
echo "====> [2/3] 正在释放 80 端口并申请/验证 SSL 证书..."
[ -f /lib/systemd/system/nginx.service ] && systemctl stop nginx || true
[ -f /lib/systemd/system/apache2.service ] && systemctl stop apache2 || true
certbot certonly --standalone -d "$DOMAIN" --register-unsafely-without-email --agree-tos --keep-until-expiring || true
if [ ! -f "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" ]; then echo "错误：证书不存在，请检查域名A记录解析！"; systemctl start nginx || true; exit 1; fi
echo ""
echo "====> [3/3] 正在全自动写入 Nginx 配置文件..."
echo "server { listen 80; server_name $DOMAIN; return 301 https://\$host\$request_uri; }" > /etc/nginx/sites-available/default
echo "server { listen 443 ssl; server_name $DOMAIN; ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem; ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem; ssl_session_timeout 5m; ssl_protocols TLSv1.2 TLSv1.3; ssl_ciphers ECDHE-RSA-AES128-GCM-SHA256:HIGH:!aNULL:!MD5:!RC4:!DHE; location / { root /var/www/html; index index.html index.htm; } }" >> /etc/nginx/sites-available/default
sed -i "s/\$DOMAIN/$DOMAIN/g" /etc/nginx/sites-available/default
echo ""
echo "====> 正在测试 Nginx 语法并启动服务..."
nginx -t && systemctl restart nginx || systemctl start nginx
echo "========================================="
echo "恭喜！域名 $DOMAIN 的 HTTPS 自动化配置已全部完成！"
echo "您的文件存放在 VPS 的: /var/www/html 目录下"
echo "现在可以用 https://$DOMAIN/ 访问您的脚本了。"
echo "========================================="
