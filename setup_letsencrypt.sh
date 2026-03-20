#!/bin/bash

# Скрипт для получения SSL сертификата Let's Encrypt после настройки домена
# Использование: bash setup_letsencrypt.sh your-domain.tk

set -e

DOMAIN=$1

if [ -z "$DOMAIN" ]; then
    echo "❌ Ошибка: Укажите домен"
    echo "Использование: bash setup_letsencrypt.sh your-domain.tk"
    exit 1
fi

echo "🔐 Настройка SSL сертификата Let's Encrypt для домена: $DOMAIN"
echo "=================================================="

# Проверка прав root
if [ "$EUID" -ne 0 ]; then 
    echo "❌ Ошибка: Запустите скрипт с правами root (sudo bash setup_letsencrypt.sh $DOMAIN)"
    exit 1
fi

# Проверка DNS
echo "🔍 Проверка DNS записи для $DOMAIN..."
if dig +short $DOMAIN | grep -q "83.166.246.225"; then
    echo "✅ DNS запись найдена"
else
    echo "⚠️  DNS запись не найдена или указывает на другой IP"
    echo "Убедитесь, что A-запись для $DOMAIN указывает на 83.166.246.225"
    read -p "Продолжить? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# Установка Certbot
echo "📦 Установка Certbot..."
apt update
apt install -y certbot python3-certbot-nginx

# Обновление конфигурации Nginx для домена
echo "📝 Обновление конфигурации Nginx..."

# Создание резервной копии
cp /etc/nginx/sites-available/messenger-app /etc/nginx/sites-available/messenger-app.backup

# Обновление конфигурации
cat > /etc/nginx/sites-available/messenger-app << EOF
# HTTP -> HTTPS редирект
server {
    listen 80;
    listen [::]:80;
    server_name $DOMAIN 83.166.246.225;
    
    # Для Let's Encrypt проверки
    location /.well-known/acme-challenge/ {
        root /var/www/html;
    }
    
    # Редирект на HTTPS
    location / {
        return 301 https://\$server_name\$request_uri;
    }
}

# HTTPS сервер
server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name $DOMAIN 83.166.246.225;
    
    # SSL сертификаты (будут обновлены Certbot)
    ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;
    
    # SSL настройки
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers 'ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384';
    ssl_prefer_server_ciphers on;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 10m;
    
    # Безопасность заголовков
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    
    # Логи
    access_log /var/log/nginx/messenger-access.log;
    error_log /var/log/nginx/messenger-error.log;
    
    # Увеличенные размеры для загрузки файлов
    client_max_body_size 100M;
    
    # Проксирование на Node.js приложение
    location / {
        proxy_pass http://localhost:3000;
        proxy_http_version 1.1;
        
        # WebSocket поддержка
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        
        # Заголовки
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        
        # Таймауты для WebSocket
        proxy_read_timeout 86400;
        proxy_send_timeout 86400;
        proxy_buffering off;
    }
}
EOF

# Проверка конфигурации
echo "🔍 Проверка конфигурации Nginx..."
nginx -t

# Перезагрузка Nginx
echo "🔄 Перезагрузка Nginx..."
systemctl reload nginx

# Получение SSL сертификата
echo "🔐 Получение SSL сертификата от Let's Encrypt..."
certbot --nginx -d $DOMAIN --non-interactive --agree-tos --email admin@$DOMAIN --redirect

# Проверка сертификата
echo "✅ Проверка сертификата..."
if [ -f "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" ]; then
    echo "✅ SSL сертификат успешно установлен!"
    echo ""
    echo "📋 Информация о сертификате:"
    openssl x509 -in /etc/letsencrypt/live/$DOMAIN/fullchain.pem -noout -subject -dates
    echo ""
    echo "✅ HTTPS настроен для домена: https://$DOMAIN"
    echo "✅ Ваше приложение доступно по адресу: https://$DOMAIN"
    echo ""
    echo "📝 Обновите приложение:"
    echo "   baseUrl = 'https://$DOMAIN'"
    echo "   wsUrl = 'https://$DOMAIN'"
else
    echo "❌ Ошибка при получении сертификата"
    echo "Проверьте логи: journalctl -u certbot"
    exit 1
fi

# Проверка автообновления
echo "🔄 Проверка автообновления сертификата..."
certbot renew --dry-run

echo ""
echo "✅ Готово! SSL сертификат настроен и будет автоматически обновляться."
