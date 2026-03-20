#!/bin/bash

# Скрипт настройки HTTPS для домена milviar.ru
# Использование: bash setup_milviar_ru.sh

set -e

DOMAIN="milviar.ru"
IP="83.166.246.225"

echo "🔐 Настройка HTTPS для домена: $DOMAIN"
echo "=================================================="

# Проверка прав root
if [ "$EUID" -ne 0 ]; then 
    echo "❌ Ошибка: Запустите скрипт с правами root (sudo bash setup_milviar_ru.sh)"
    exit 1
fi

# Проверка DNS
echo "🔍 Проверка DNS записи для $DOMAIN..."
DNS_IP=$(dig +short $DOMAIN | tail -n1)
if [ "$DNS_IP" = "$IP" ]; then
    echo "✅ DNS запись корректна: $DOMAIN → $DNS_IP"
else
    echo "⚠️  DNS запись не указывает на правильный IP"
    echo "   Ожидается: $IP"
    echo "   Получено: $DNS_IP"
    echo ""
    echo "📋 Настройте DNS запись:"
    echo "   Тип: A"
    echo "   Имя: @ (или оставьте пустым)"
    echo "   Значение: $IP"
    echo "   TTL: 3600"
    echo ""
    read -p "Продолжить после настройки DNS? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# Установка необходимых пакетов
echo "📦 Установка необходимых пакетов..."
apt update
apt install -y nginx certbot python3-certbot-nginx openssl ufw curl

# Создание директории для временных файлов Let's Encrypt
mkdir -p /var/www/html/.well-known/acme-challenge
chown -R www-data:www-data /var/www/html

# Создание конфигурации Nginx для получения сертификата
echo "📝 Создание временной конфигурации Nginx..."

cat > /etc/nginx/sites-available/messenger-app << EOF
# HTTP сервер для получения сертификата Let's Encrypt
server {
    listen 80;
    listen [::]:80;
    server_name $DOMAIN www.$DOMAIN;
    
    # Для Let's Encrypt проверки
    location /.well-known/acme-challenge/ {
        root /var/www/html;
    }
    
    # Временный редирект (будет изменен после получения сертификата)
    location / {
        proxy_pass http://localhost:3000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF

# Активация конфигурации
ln -sf /etc/nginx/sites-available/messenger-app /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default

# Проверка и перезагрузка Nginx
echo "🔍 Проверка конфигурации Nginx..."
nginx -t

echo "🔄 Перезагрузка Nginx..."
systemctl enable nginx
systemctl start nginx
systemctl reload nginx

# Настройка файрвола
echo "🔥 Настройка файрвола..."
ufw --force enable
ufw allow 22/tcp
ufw allow 80/tcp
ufw allow 443/tcp
ufw status

# Получение SSL сертификата Let's Encrypt
echo "🔐 Получение SSL сертификата от Let's Encrypt..."
echo "   Домен: $DOMAIN"
echo "   Email будет запрошен..."

certbot --nginx -d $DOMAIN -d www.$DOMAIN --non-interactive --agree-tos --email admin@$DOMAIN --redirect

# Проверка сертификата
if [ -f "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" ]; then
    echo "✅ SSL сертификат успешно установлен!"
    echo ""
    echo "📋 Информация о сертификате:"
    openssl x509 -in /etc/letsencrypt/live/$DOMAIN/fullchain.pem -noout -subject -dates
    echo ""
    
    # Обновление конфигурации для WebSocket
    echo "📝 Обновление конфигурации для WebSocket..."
    
    cat > /etc/nginx/sites-available/messenger-app << EOF
# HTTP -> HTTPS редирект
server {
    listen 80;
    listen [::]:80;
    server_name $DOMAIN www.$DOMAIN;
    
    # Для Let's Encrypt проверки
    location /.well-known/acme-challenge/ {
        root /var/www/html;
    }
    
    # Редирект на HTTPS
    return 301 https://\$server_name\$request_uri;
}

# HTTPS сервер
server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name $DOMAIN www.$DOMAIN;
    
    # SSL сертификаты Let's Encrypt
    ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;
    
    # SSL настройки безопасности
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers 'ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384';
    ssl_prefer_server_ciphers on;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 10m;
    ssl_session_tickets off;
    
    # Безопасность заголовков
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
    
    # Логи
    access_log /var/log/nginx/messenger-access.log;
    error_log /var/log/nginx/messenger-error.log;
    
    # Увеличенные размеры для загрузки файлов
    client_max_body_size 100M;
    client_body_buffer_size 128k;
    
    # Проксирование на Node.js приложение
    location / {
        proxy_pass http://localhost:3000;
        proxy_http_version 1.1;
        
        # WebSocket поддержка
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        
        # Заголовки для правильной работы прокси
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header X-Forwarded-Host \$host;
        proxy_set_header X-Forwarded-Port \$server_port;
        
        # Таймауты для WebSocket (долгие соединения)
        proxy_read_timeout 86400;
        proxy_send_timeout 86400;
        proxy_connect_timeout 60;
        
        # Отключение буферизации для WebSocket
        proxy_buffering off;
        proxy_request_buffering off;
    }
    
    # Статические файлы (если есть директория uploads)
    location /uploads/ {
        alias /var/www/uploads/;
        expires 30d;
        add_header Cache-Control "public, immutable";
        
        # Если директории нет, проксируем на приложение
        try_files \$uri @proxy;
    }
    
    location @proxy {
        proxy_pass http://localhost:3000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF
    
    # Проверка конфигурации
    nginx -t
    
    # Перезагрузка Nginx
    systemctl reload nginx
    
    echo ""
    echo "✅ HTTPS успешно настроен!"
    echo ""
    echo "🌐 Ваше приложение доступно по адресам:"
    echo "   https://$DOMAIN"
    echo "   https://www.$DOMAIN"
    echo ""
    echo "📝 Обновите приложение:"
    echo "   baseUrl = 'https://$DOMAIN'"
    echo "   wsUrl = 'https://$DOMAIN'"
    echo ""
    echo "✅ SSL сертификат будет автоматически обновляться каждые 60 дней"
    
else
    echo "❌ Ошибка при получении сертификата"
    echo "Проверьте логи: journalctl -u certbot"
    exit 1
fi

# Проверка автообновления
echo "🔄 Проверка автообновления сертификата..."
certbot renew --dry-run

echo ""
echo "✅ Готово! HTTPS настроен для домена $DOMAIN"
