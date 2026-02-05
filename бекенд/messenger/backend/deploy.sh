#!/bin/bash

# Обновление системы и установка Node.js
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
sudo apt-get install -y nodejs nginx

# Установка PM2 для управления процессами
sudo npm install -g pm2

# Переход в папку проекта (предполагается, что файлы уже загружены)
npm install

# Запуск сервера через PM2
pm2 start index.js --name "messenger-backend"

# Настройка Nginx
echo "server {
    listen 80;
    server_name 83.166.246.225;

    location / {
        proxy_pass http://localhost:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_cache_bypass \$http_upgrade;
    }
}" | sudo tee /etc/nginx/sites-available/default

sudo systemctl restart nginx

echo "Деплой завершен! Сервер запущен на порту 3000 и проксирован через Nginx."
