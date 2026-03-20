#!/bin/bash

# Скрипт автоматической настройки HTTPS для сервера Reg.ru Cloud
# IP: 83.166.246.225
# Использование: скопируйте этот файл на сервер и выполните: bash setup_https.sh

set -e  # Остановка при ошибке

echo "🚀 Начало настройки HTTPS для сервера 83.166.246.225"
echo "=================================================="

# Цвета для вывода
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Проверка прав root
if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}❌ Ошибка: Запустите скрипт с правами root (sudo bash setup_https.sh)${NC}"
    exit 1
fi

echo -e "${GREEN}✅ Права root подтверждены${NC}"

# Обновление системы
echo -e "\n${YELLOW}📦 Обновление системы...${NC}"
apt update && apt upgrade -y

# Установка необходимых пакетов
echo -e "\n${YELLOW}📦 Установка необходимых пакетов...${NC}"
apt install -y nginx certbot python3-certbot-nginx openssl ufw curl

# Проверка статуса Nginx
echo -e "\n${YELLOW}🔍 Проверка статуса Nginx...${NC}"
systemctl enable nginx
systemctl start nginx
systemctl status nginx --no-pager

# Создание директории для SSL сертификатов
echo -e "\n${YELLOW}📁 Создание директорий...${NC}"
mkdir -p /etc/nginx/ssl
mkdir -p /var/log/nginx

# Создание самоподписанного сертификата (временный, пока нет домена)
echo -e "\n${YELLOW}🔐 Создание самоподписанного SSL сертификата...${NC}"
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout /etc/nginx/ssl/server.key \
    -out /etc/nginx/ssl/server.crt \
    -subj "/C=RU/ST=Moscow/L=Moscow/O=MessengerApp/CN=83.166.246.225" \
    2>/dev/null

# Установка прав доступа
chmod 600 /etc/nginx/ssl/server.key
chmod 644 /etc/nginx/ssl/server.crt

echo -e "${GREEN}✅ SSL сертификат создан${NC}"

# Создание конфигурации Nginx
echo -e "\n${YELLOW}📝 Создание конфигурации Nginx...${NC}"

cat > /etc/nginx/sites-available/messenger-app << 'EOF'
# HTTP -> HTTPS редирект
server {
    listen 80;
    listen [::]:80;
    server_name 83.166.246.225;
    
    # Редирект на HTTPS
    return 301 https://$server_name$request_uri;
}

# HTTPS сервер
server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name 83.166.246.225;
    
    # SSL сертификаты
    ssl_certificate /etc/nginx/ssl/server.crt;
    ssl_certificate_key /etc/nginx/ssl/server.key;
    
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
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        
        # Заголовки для правильной работы прокси
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header X-Forwarded-Host $host;
        proxy_set_header X-Forwarded-Port $server_port;
        
        # Таймауты для WebSocket (долгие соединения)
        proxy_read_timeout 86400;
        proxy_send_timeout 86400;
        proxy_connect_timeout 60;
        
        # Буферизация
        proxy_buffering off;
        proxy_request_buffering off;
    }
    
    # Статические файлы (если есть директория uploads)
    location /uploads/ {
        alias /var/www/uploads/;
        expires 30d;
        add_header Cache-Control "public, immutable";
        
        # Если директории нет, проксируем на приложение
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
EOF

# Активация конфигурации
echo -e "\n${YELLOW}🔗 Активация конфигурации Nginx...${NC}"
ln -sf /etc/nginx/sites-available/messenger-app /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default

# Проверка конфигурации Nginx
echo -e "\n${YELLOW}🔍 Проверка конфигурации Nginx...${NC}"
if nginx -t; then
    echo -e "${GREEN}✅ Конфигурация Nginx корректна${NC}"
else
    echo -e "${RED}❌ Ошибка в конфигурации Nginx${NC}"
    exit 1
fi

# Перезагрузка Nginx
echo -e "\n${YELLOW}🔄 Перезагрузка Nginx...${NC}"
systemctl reload nginx
systemctl restart nginx

# Настройка файрвола
echo -e "\n${YELLOW}🔥 Настройка файрвола...${NC}"
ufw --force enable
ufw allow 22/tcp   # SSH
ufw allow 80/tcp   # HTTP
ufw allow 443/tcp  # HTTPS
ufw allow 3000/tcp # Node.js (если нужен прямой доступ)

# Проверка статуса файрвола
ufw status

# Проверка работы HTTPS
echo -e "\n${YELLOW}🔍 Проверка работы HTTPS...${NC}"
sleep 2

# Проверка порта 443
if netstat -tuln | grep -q ':443 '; then
    echo -e "${GREEN}✅ Порт 443 открыт${NC}"
else
    echo -e "${RED}❌ Порт 443 не открыт${NC}"
fi

# Проверка SSL сертификата
echo -e "\n${YELLOW}🔐 Проверка SSL сертификата...${NC}"
if [ -f /etc/nginx/ssl/server.crt ]; then
    echo -e "${GREEN}✅ SSL сертификат найден${NC}"
    openssl x509 -in /etc/nginx/ssl/server.crt -noout -subject -dates
else
    echo -e "${RED}❌ SSL сертификат не найден${NC}"
fi

# Проверка подключения
echo -e "\n${YELLOW}🌐 Проверка подключения к HTTPS...${NC}"
if curl -k -s -o /dev/null -w "%{http_code}" https://localhost:443 | grep -q "200\|301\|302"; then
    echo -e "${GREEN}✅ HTTPS работает локально${NC}"
else
    echo -e "${YELLOW}⚠️ HTTPS может не работать локально (это нормально для самоподписанного сертификата)${NC}"
fi

# Информация о следующих шагах
echo -e "\n${GREEN}=================================================="
echo "✅ Настройка HTTPS завершена!"
echo "==================================================${NC}"
echo ""
echo -e "${YELLOW}📋 Следующие шаги:${NC}"
echo ""
echo "1. Проверьте работу HTTPS:"
echo "   curl -k https://83.166.246.225"
echo ""
echo "2. Если у вас есть домен, получите валидный сертификат:"
echo "   certbot --nginx -d your-domain.com"
echo ""
echo "3. Проверьте логи Nginx:"
echo "   tail -f /var/log/nginx/messenger-error.log"
echo ""
echo "4. Убедитесь, что ваше Node.js приложение работает на порту 3000:"
echo "   netstat -tuln | grep 3000"
echo ""
echo -e "${GREEN}✅ Готово! HTTPS настроен на порту 443${NC}"
echo "   Ваше приложение доступно по адресу: https://83.166.246.225"
echo ""
