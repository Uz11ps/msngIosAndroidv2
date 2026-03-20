# Инструкция по настройке HTTPS в Reg.ru Cloud

## Обзор

Эта инструкция поможет настроить HTTPS для вашего сервера `83.166.246.225:3000` в Reg.ru Cloud, чтобы приложение работало через мобильные данные Мегафона.

## Варианты настройки

### Вариант 1: Nginx как Reverse Proxy (РЕКОМЕНДУЕТСЯ)

Этот вариант использует Nginx как прокси перед вашим Node.js приложением. Nginx обрабатывает HTTPS, а приложение работает на HTTP локально.

### Вариант 2: Прямая настройка HTTPS в Node.js

Приложение напрямую работает с HTTPS без Nginx.

---

## Вариант 1: Nginx Reverse Proxy (РЕКОМЕНДУЕТСЯ)

### Шаг 1: Установка Nginx

```bash
# Подключитесь к серверу по SSH
ssh root@83.166.246.225

# Обновление системы
apt update && apt upgrade -y

# Установка Nginx
apt install nginx -y

# Проверка статуса
systemctl status nginx
```

### Шаг 2: Установка Certbot (Let's Encrypt)

```bash
# Установка Certbot
apt install certbot python3-certbot-nginx -y

# Проверка версии
certbot --version
```

### Шаг 3: Настройка домена (если есть)

Если у вас есть домен, привяжите его к IP `83.166.246.225`:

1. Зайдите в панель управления доменом в Reg.ru
2. Добавьте A-запись:
   - **Тип:** A
   - **Имя:** @ (или поддомен, например `api`)
   - **Значение:** `83.166.246.225`
   - **TTL:** 3600

**Пример:** Если домен `example.com`, то:
- `example.com` → `83.166.246.225`
- Или `api.example.com` → `83.166.246.225`

### Шаг 4: Получение SSL сертификата

#### Если есть домен:

```bash
# Получение сертификата (замените example.com на ваш домен)
certbot --nginx -d example.com -d www.example.com

# Или для поддомена:
certbot --nginx -d api.example.com
```

Certbot автоматически:
- Получит сертификат от Let's Encrypt
- Настроит Nginx для HTTPS
- Настроит автоматическое обновление сертификата

#### Если домена нет (только IP):

Для IP-адреса нельзя получить обычный SSL сертификат. Нужно:
1. Использовать самоподписанный сертификат (см. ниже)
2. Или получить бесплатный домен (например, через Freenom или NoIP)

### Шаг 5: Настройка Nginx для Reverse Proxy

Создайте конфигурационный файл Nginx:

```bash
# Создайте файл конфигурации
nano /etc/nginx/sites-available/messenger-app
```

Вставьте следующую конфигурацию:

```nginx
# HTTP -> HTTPS редирект
server {
    listen 80;
    server_name 83.166.246.225;  # или ваш домен example.com
    
    # Редирект на HTTPS
    return 301 https://$server_name$request_uri;
}

# HTTPS сервер
server {
    listen 443 ssl http2;
    server_name 83.166.246.225;  # или ваш домен example.com
    
    # SSL сертификаты (если используете Let's Encrypt)
    ssl_certificate /etc/letsencrypt/live/example.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/example.com/privkey.pem;
    
    # Или для самоподписанного сертификата:
    # ssl_certificate /etc/nginx/ssl/server.crt;
    # ssl_certificate_key /etc/nginx/ssl/server.key;
    
    # SSL настройки
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
    ssl_prefer_server_ciphers on;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 10m;
    
    # Логи
    access_log /var/log/nginx/messenger-access.log;
    error_log /var/log/nginx/messenger-error.log;
    
    # Проксирование на Node.js приложение
    location / {
        proxy_pass http://localhost:3000;
        proxy_http_version 1.1;
        
        # WebSocket поддержка
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        
        # Заголовки
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        
        # Таймауты для WebSocket
        proxy_read_timeout 86400;
        proxy_send_timeout 86400;
    }
    
    # Статические файлы (если есть)
    location /uploads/ {
        alias /path/to/your/uploads/;
        expires 30d;
        add_header Cache-Control "public, immutable";
    }
}
```

**Важно:** Замените:
- `example.com` на ваш домен (если есть)
- `/path/to/your/uploads/` на реальный путь к загрузкам

### Шаг 6: Активация конфигурации

```bash
# Создать символическую ссылку
ln -s /etc/nginx/sites-available/messenger-app /etc/nginx/sites-enabled/

# Удалить дефолтную конфигурацию (если не нужна)
rm /etc/nginx/sites-enabled/default

# Проверить конфигурацию
nginx -t

# Перезагрузить Nginx
systemctl reload nginx
```

### Шаг 7: Настройка файрвола

```bash
# Открыть порты
ufw allow 80/tcp
ufw allow 443/tcp
ufw allow 22/tcp  # SSH

# Включить файрвол (если еще не включен)
ufw enable

# Проверить статус
ufw status
```

### Шаг 8: Автоматическое обновление сертификата

```bash
# Проверить, что автообновление настроено
certbot renew --dry-run

# Сертификат будет автоматически обновляться каждые 60 дней
```

---

## Вариант 2: Самоподписанный сертификат (для IP без домена)

Если у вас нет домена, можно использовать самоподписанный сертификат:

### Шаг 1: Создание самоподписанного сертификата

```bash
# Создать директорию для сертификатов
mkdir -p /etc/nginx/ssl

# Создать самоподписанный сертификат
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout /etc/nginx/ssl/server.key \
    -out /etc/nginx/ssl/server.crt \
    -subj "/C=RU/ST=Moscow/L=Moscow/O=Company/CN=83.166.246.225"

# Установить права доступа
chmod 600 /etc/nginx/ssl/server.key
chmod 644 /etc/nginx/ssl/server.crt
```

### Шаг 2: Настройка Nginx с самоподписанным сертификатом

Используйте конфигурацию из Варианта 1, но с путями к самоподписанному сертификату:

```nginx
ssl_certificate /etc/nginx/ssl/server.crt;
ssl_certificate_key /etc/nginx/ssl/server.key;
```

**⚠️ ВАЖНО:** iOS будет показывать предупреждение о недоверенном сертификате. Нужно добавить настройки в `Info.plist` (см. ниже).

---

## Вариант 3: Прямая настройка HTTPS в Node.js

Если вы хотите настроить HTTPS напрямую в Node.js приложении:

### Шаг 1: Создание сертификата

```bash
# Создать директорию
mkdir -p /path/to/your/app/ssl

# Создать самоподписанный сертификат
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout /path/to/your/app/ssl/server.key \
    -out /path/to/your/app/ssl/server.crt \
    -subj "/C=RU/ST=Moscow/L=Moscow/O=Company/CN=83.166.246.225"
```

### Шаг 2: Изменение кода Node.js приложения

Если используете Express:

```javascript
const express = require('express');
const https = require('https');
const fs = require('fs');
const app = express();

// Загрузка сертификатов
const options = {
  key: fs.readFileSync('/path/to/your/app/ssl/server.key'),
  cert: fs.readFileSync('/path/to/your/app/ssl/server.crt')
};

// Ваш код приложения
app.use(express.json());
// ... остальные маршруты

// Запуск HTTPS сервера
const PORT = 3000;
https.createServer(options, app).listen(PORT, () => {
  console.log(`HTTPS Server running on port ${PORT}`);
});
```

Если используете Socket.IO:

```javascript
const https = require('https');
const fs = require('fs');
const { Server } = require('socket.io');

const options = {
  key: fs.readFileSync('/path/to/your/app/ssl/server.key'),
  cert: fs.readFileSync('/path/to/your/app/ssl/server.crt')
};

const server = https.createServer(options);
const io = new Server(server, {
  cors: {
    origin: "*",
    methods: ["GET", "POST"]
  }
});

server.listen(3000, () => {
  console.log('Socket.IO HTTPS server running on port 3000');
});
```

---

## Настройка iOS приложения для самоподписанного сертификата

Если используете самоподписанный сертификат, нужно обновить `Info.plist`:

```xml
<key>NSAppTransportSecurity</key>
<dict>
    <key>NSAllowsLocalNetworking</key>
    <true/>
    <key>NSExceptionDomains</key>
    <dict>
        <key>83.166.246.225</key>
        <dict>
            <key>NSIncludesSubdomains</key>
            <true/>
            <key>NSExceptionRequiresForwardSecrecy</key>
            <false/>
            <key>NSExceptionMinimumTLSVersion</key>
            <string>TLSv1.0</string>
            <key>NSExceptionAllowsInsecureHTTPLoads</key>
            <false/>
            <key>NSTemporaryExceptionAllowsInsecureHTTPLoads</key>
            <false/>
            <key>NSThirdPartyExceptionRequiresForwardSecrecy</key>
            <false/>
            <key>NSExceptionAllowsInsecureHTTPLoads</key>
            <false/>
        </dict>
    </dict>
</dict>
```

**⚠️ ВАЖНО:** Для самоподписанного сертификата iOS может требовать дополнительных настроек или установки сертификата в доверенные.

---

## Обновление приложения после настройки HTTPS

После настройки HTTPS на сервере:

1. Обновите `lib/config/api_config.dart`:
```dart
static const String baseUrl = 'https://83.166.246.225:3000';  // или https://example.com
static const String wsUrl = 'https://83.166.246.225:3000';     // или wss://example.com
```

2. Если используете домен вместо IP:
```dart
static const String baseUrl = 'https://api.example.com';
static const String wsUrl = 'https://api.example.com';
```

3. Обновите `Info.plist` (уберите настройки для HTTP, оставьте только HTTPS)

---

## Проверка работы HTTPS

### 1. Проверка через браузер

Откройте в браузере:
- `https://83.166.246.225` (если используете Nginx на порту 443)
- `https://83.166.246.225:3000` (если HTTPS напрямую в Node.js)

### 2. Проверка через curl

```bash
# Проверка HTTPS
curl -k https://83.166.246.225

# Проверка с выводом информации о сертификате
curl -vI https://83.166.246.225
```

### 3. Проверка WebSocket (WSS)

```bash
# Установка wscat
npm install -g wscat

# Проверка WSS соединения
wscat -c wss://83.166.246.225
```

---

## Решение проблем

### Проблема 1: Ошибка "SSL certificate problem"

**Решение:**
- Проверьте, что сертификат правильно установлен
- Проверьте права доступа к файлам сертификата
- Убедитесь, что путь к сертификату правильный в конфигурации

### Проблема 2: WebSocket не работает через WSS

**Решение:**
- Убедитесь, что в Nginx настроены заголовки `Upgrade` и `Connection`
- Проверьте, что Socket.IO настроен для работы через прокси
- Проверьте таймауты в Nginx

### Проблема 3: iOS не доверяет самоподписанному сертификату

**Решение:**
- Используйте валидный сертификат от Let's Encrypt (требует домен)
- Или установите сертификат в доверенные на устройстве iOS

### Проблема 4: Порт 443 занят

**Решение:**
```bash
# Проверить, что использует порт 443
netstat -tulpn | grep 443

# Остановить конфликтующий сервис или изменить порт
```

---

## Рекомендации

1. **Используйте домен:** Получите бесплатный домен (Freenom, NoIP) или купите домен в Reg.ru для использования валидного SSL сертификата

2. **Используйте Let's Encrypt:** Это бесплатный и автоматически обновляемый SSL сертификат

3. **Используйте Nginx:** Это более безопасный и производительный вариант, чем прямая настройка HTTPS в Node.js

4. **Настройте автообновление:** Certbot автоматически обновляет сертификаты Let's Encrypt

5. **Мониторинг:** Настройте мониторинг SSL сертификата для отслеживания сроков действия

---

## Полезные команды

```bash
# Проверка статуса Nginx
systemctl status nginx

# Перезагрузка Nginx
systemctl reload nginx

# Проверка конфигурации Nginx
nginx -t

# Просмотр логов Nginx
tail -f /var/log/nginx/error.log
tail -f /var/log/nginx/access.log

# Проверка SSL сертификата
openssl s_client -connect 83.166.246.225:443 -showcerts

# Проверка портов
netstat -tulpn | grep -E ':(80|443|3000)'
```

---

## После настройки HTTPS

1. Обновите приложение на HTTPS (см. раздел "Обновление приложения")
2. Протестируйте через Wi-Fi и мобильные данные
3. Убедитесь, что WebSocket работает через WSS
4. Проверьте работу всех функций приложения

---

## Поддержка

Если возникнут проблемы:
1. Проверьте логи Nginx: `/var/log/nginx/error.log`
2. Проверьте логи приложения Node.js
3. Проверьте статус сервисов: `systemctl status nginx`
4. Проверьте файрвол: `ufw status`
