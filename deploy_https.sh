#!/bin/bash

# Автоматический деплой HTTPS на сервер
# Использование: bash deploy_https.sh

set -e

SERVER_IP="83.166.246.225"
SERVER_USER="root"
SERVER_PASS="kcokmkzgHQ5dJOBF"
SCRIPT_NAME="auto_setup_https.sh"

echo "🚀 Автоматический деплой HTTPS на сервер"
echo "========================================"

# Проверка наличия sshpass
if ! command -v sshpass &> /dev/null; then
    echo "📦 Установка sshpass..."
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS
        if ! command -v brew &> /dev/null; then
            echo "❌ Установите Homebrew: https://brew.sh"
            exit 1
        fi
        brew install hudochenkov/sshpass/sshpass
    elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
        # Linux
        sudo apt-get update && sudo apt-get install -y sshpass
    else
        echo "❌ Установите sshpass вручную"
        exit 1
    fi
fi

# Загрузка скрипта на сервер
echo "📤 Загрузка скрипта на сервер..."
sshpass -p "$SERVER_PASS" scp -o StrictHostKeyChecking=no auto_setup_https.sh $SERVER_USER@$SERVER_IP:/root/

# Выполнение скрипта на сервере
echo "🔧 Выполнение настройки на сервере..."
echo "Это может занять 2-3 минуты..."
echo ""

sshpass -p "$SERVER_PASS" ssh -o StrictHostKeyChecking=no $SERVER_USER@$SERVER_IP "bash /root/$SCRIPT_NAME"

echo ""
echo "✅ Деплой завершен!"
echo ""
echo "🌐 Проверьте работу:"
echo "   https://milviar.ru"
echo ""
echo "📱 Приложение готово к использованию!"
