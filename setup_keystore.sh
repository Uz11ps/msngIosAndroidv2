#!/bin/bash

# Скрипт для настройки подписи приложения для Google Play

echo "🔐 Настройка подписи приложения для Google Play"
echo ""

# Проверка наличия keytool
if ! command -v keytool &> /dev/null; then
    echo "❌ Ошибка: keytool не найден!"
    echo "Установите Java JDK для использования keytool"
    exit 1
fi

# Переход в директорию android
cd android || exit

# Проверка существования ключа
if [ -f "upload-keystore.jks" ]; then
    echo "⚠️  Ключ уже существует!"
    read -p "Перезаписать существующий ключ? (y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Отмена."
        exit 0
    fi
    rm -f upload-keystore.jks
fi

echo "📝 Создание нового ключа подписи..."
echo ""
echo "Введите следующие данные:"
echo ""

# Запрос данных
read -p "Пароль для хранилища ключей: " -s STORE_PASSWORD
echo
read -p "Повторите пароль: " -s STORE_PASSWORD_CONFIRM
echo

if [ "$STORE_PASSWORD" != "$STORE_PASSWORD_CONFIRM" ]; then
    echo "❌ Пароли не совпадают!"
    exit 1
fi

read -p "Пароль для ключа (можно использовать тот же): " -s KEY_PASSWORD
echo
read -p "Ваше имя и фамилия: " NAME
read -p "Название организации: " ORGANIZATION
read -p "Город: " CITY
read -p "Регион/Область: " REGION
read -p "Код страны (2 буквы, например RU): " COUNTRY_CODE

echo ""
echo "Создание ключа..."

# Создание ключа
keytool -genkey -v -keystore upload-keystore.jks \
    -keyalg RSA -keysize 2048 -validity 10000 \
    -alias upload \
    -storepass "$STORE_PASSWORD" \
    -keypass "$KEY_PASSWORD" \
    -dname "CN=$NAME, OU=$ORGANIZATION, O=$ORGANIZATION, L=$CITY, ST=$REGION, C=$COUNTRY_CODE"

if [ $? -eq 0 ]; then
    echo "✅ Ключ успешно создан!"
    
    # Создание key.properties
    echo "📝 Создание файла key.properties..."
    
    cat > key.properties << EOF
storePassword=$STORE_PASSWORD
keyPassword=$KEY_PASSWORD
keyAlias=upload
storeFile=upload-keystore.jks
EOF
    
    echo "✅ Файл key.properties создан!"
    echo ""
    echo "⚠️  ВАЖНО:"
    echo "1. Сохраните пароли в безопасном месте!"
    echo "2. Добавьте key.properties в .gitignore!"
    echo "3. Сохраните upload-keystore.jks в безопасном месте!"
    echo ""
    echo "Без этого ключа вы не сможете обновлять приложение в Google Play!"
    
else
    echo "❌ Ошибка при создании ключа!"
    exit 1
fi
