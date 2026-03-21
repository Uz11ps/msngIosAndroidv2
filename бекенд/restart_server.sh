#!/bin/bash

# Скрипт для перезапуска сервера

echo "🔄 Перезапуск сервера..."

# Проверяем, запущен ли PM2
if command -v pm2 &> /dev/null; then
    echo "📦 Используем PM2 для перезапуска..."
    
    # Проверяем, есть ли процесс
    if pm2 list | grep -q "messenger-backend"; then
        echo "🔄 Перезапускаем процесс messenger-backend..."
        pm2 restart messenger-backend
        echo "✅ Сервер перезапущен через PM2"
        pm2 logs messenger-backend --lines 20
    else
        echo "⚠️  Процесс messenger-backend не найден. Запускаем..."
        cd "$(dirname "$0")"
        pm2 start index.js --name messenger-backend
        echo "✅ Сервер запущен через PM2"
        pm2 logs messenger-backend --lines 20
    fi
else
    echo "⚠️  PM2 не установлен. Используем прямой запуск..."
    
    # Останавливаем старый процесс, если есть
    pkill -f "node.*index.js" || true
    
    # Запускаем новый
    cd "$(dirname "$0")"
    nohup node index.js > server.log 2>&1 &
    echo "✅ Сервер запущен. Логи в server.log"
    echo "📋 Последние строки лога:"
    tail -20 server.log
fi

echo ""
echo "🔍 Проверка доступности сервера..."
sleep 2

# Проверяем доступность
if curl -s http://localhost:3000/api/auth/email-register -X POST -H "Content-Type: application/json" -d '{}' | grep -q "Email и пароль обязательны"; then
    echo "✅ Сервер работает правильно!"
else
    echo "⚠️  Сервер не отвечает или отвечает неверно. Проверьте логи."
fi
