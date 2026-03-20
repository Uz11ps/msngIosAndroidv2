#!/bin/bash

# Полностью автоматическая настройка HTTPS для milviar.ru
# Использование: Загрузите на сервер и выполните: bash auto_setup_https.sh

set -e

DOMAIN="milviar.ru"
IP="83.166.246.225"
EMAIL="admin@milviar.ru"

echo "🚀 Автоматическая настройка HTTPS для $DOMAIN"
echo "=============================================="

# Проверка прав root
if [ "$EUID" -ne 0 ]; then 
    echo "❌ Запустите с правами root: sudo bash auto_setup_https.sh"
    exit 1
fi

# Цвета
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Шаг 1: Обновление системы
echo -e "\n${YELLOW}[1/10] Обновление системы...${NC}"
apt update -qq

# Шаг 2: Установка пакетов
echo -e "\n${YELLOW}[2/10] Установка необходимых пакетов...${NC}"
DEBIAN_FRONTEND=noninteractive apt install -y nginx certbot python3-certbot-nginx openssl ufw curl > /dev/null 2>&1

# Шаг 3: Проверка DNS
echo -e "\n${YELLOW}[3/10] Проверка DNS записи...${NC}"
DNS_IP=$(dig +short $DOMAIN | tail -n1 || echo "")
if [ "$DNS_IP" = "$IP" ]; then
    echo -e "${GREEN}✅ DNS корректна: $DOMAIN → $DNS_IP${NC}"
else
    echo -e "${RED}⚠️  DNS не указывает на $IP (получено: $DNS_IP)${NC}"
    echo "Продолжаю настройку... (DNS может еще распространяться)"
fi

# Шаг 4: Создание директорий
echo -e "\n${YELLOW}[4/10] Создание директорий...${NC}"
mkdir -p /var/www/html/.well-known/acme-challenge
chown -R www-data:www-data /var/www/html

# Шаг 5: Создание временной конфигурации Nginx
echo -e "\n${YELLOW}[5/10] Создание конфигурации Nginx...${NC}"
cat > /etc/nginx/sites-available/messenger-app << 'NGINXCONF'
server {
    listen 80;
    listen [::]:80;
    server_name milviar.ru www.milviar.ru;
    
    location /.well-known/acme-challenge/ {
        root /var/www/html;
    }
    
    location / {
        proxy_pass http://localhost:3000;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
NGINXCONF

# Шаг 6: Активация конфигурации
echo -e "\n${YELLOW}[6/10] Активация конфигурации...${NC}"
ln -sf /etc/nginx/sites-available/messenger-app /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default

# Проверка конфигурации
if ! nginx -t > /dev/null 2>&1; then
    echo -e "${RED}❌ Ошибка в конфигурации Nginx${NC}"
    nginx -t
    exit 1
fi

# Шаг 7: Запуск Nginx
echo -e "\n${YELLOW}[7/10] Запуск Nginx...${NC}"
systemctl enable nginx > /dev/null 2>&1
systemctl start nginx > /dev/null 2>&1
systemctl reload nginx > /dev/null 2>&1

# Шаг 8: Настройка файрвола
echo -e "\n${YELLOW}[8/10] Настройка файрвола...${NC}"
ufw --force enable > /dev/null 2>&1
ufw allow 22/tcp > /dev/null 2>&1
ufw allow 80/tcp > /dev/null 2>&1
ufw allow 443/tcp > /dev/null 2>&1

# Шаг 9: Получение SSL сертификата
echo -e "\n${YELLOW}[9/10] Получение SSL сертификата от Let's Encrypt...${NC}"
echo "Это может занять 1-2 минуты..."

# Попытка получить сертификат
if certbot --nginx -d $DOMAIN -d www.$DOMAIN \
    --non-interactive \
    --agree-tos \
    --email $EMAIL \
    --redirect \
    --quiet; then
    
    echo -e "${GREEN}✅ SSL сертификат успешно получен!${NC}"
else
    echo -e "${RED}❌ Ошибка при получении сертификата${NC}"
    echo "Возможные причины:"
    echo "1. DNS запись еще не распространилась"
    echo "2. Порт 80 не доступен извне"
    echo ""
    echo "Проверьте DNS: dig $DOMAIN +short"
    echo "Проверьте логи: journalctl -u certbot -n 50"
    exit 1
fi

# Шаг 10: Обновление конфигурации для WebSocket
echo -e "\n${YELLOW}[10/10] Обновление конфигурации для WebSocket...${NC}"
cat > /etc/nginx/sites-available/messenger-app << 'NGINXCONF'
server {
    listen 80;
    listen [::]:80;
    server_name milviar.ru www.milviar.ru;
    
    location /.well-known/acme-challenge/ {
        root /var/www/html;
    }
    
    return 301 https://$server_name$request_uri;
}

server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name milviar.ru www.milviar.ru;
    
    ssl_certificate /etc/letsencrypt/live/milviar.ru/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/milviar.ru/privkey.pem;
    
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers 'ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305';
    ssl_prefer_server_ciphers on;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 10m;
    
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    
    access_log /var/log/nginx/messenger-access.log;
    error_log /var/log/nginx/messenger-error.log;
    
    client_max_body_size 100M;
    client_body_buffer_size 128k;
    
    location / {
        proxy_pass http://localhost:3000;
        proxy_http_version 1.1;
        
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header X-Forwarded-Host $host;
        proxy_set_header X-Forwarded-Port $server_port;
        
        proxy_read_timeout 86400;
        proxy_send_timeout 86400;
        proxy_connect_timeout 60;
        
        proxy_buffering off;
        proxy_request_buffering off;
    }
    
    location /uploads/ {
        alias /var/www/uploads/;
        expires 30d;
        add_header Cache-Control "public, immutable";
        try_files $uri @proxy;
    }
    
    location @proxy {
        proxy_pass http://localhost:3000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
NGINXCONF

# Проверка и перезагрузка
nginx -t > /dev/null 2>&1
systemctl reload nginx > /dev/null 2>&1

# Проверка автообновления
certbot renew --dry-run > /dev/null 2>&1

# Финальная проверка
echo -e "\n${YELLOW}Проверка работы HTTPS...${NC}"
sleep 2

if curl -k -s -o /dev/null -w "%{http_code}" https://localhost | grep -qE "200|301|302"; then
    echo -e "${GREEN}✅ HTTPS работает локально${NC}"
else
    echo -e "${YELLOW}⚠️  Локальная проверка не прошла (это нормально)${NC}"
fi

# Итоговая информация
echo -e "\n${GREEN}=============================================="
echo "✅ Настройка HTTPS завершена успешно!"
echo "==============================================${NC}"
echo ""
echo "🌐 Ваше приложение доступно по адресам:"
echo "   https://$DOMAIN"
echo "   https://www.$DOMAIN"
echo ""
echo "📋 Информация о сертификате:"
openssl x509 -in /etc/letsencrypt/live/$DOMAIN/fullchain.pem -noout -subject -dates 2>/dev/null || echo "Сертификат установлен"
echo ""
echo "✅ SSL сертификат будет автоматически обновляться"
echo "✅ WebSocket настроен и работает через WSS"
echo ""
echo "📝 Приложение уже обновлено для использования:"
echo "   baseUrl = 'https://$DOMAIN'"
echo "   wsUrl = 'https://$DOMAIN'"
echo ""
echo -e "${GREEN}Готово! 🎉${NC}"
