# Быстрая настройка HTTPS на сервере Reg.ru Cloud

## Данные вашего сервера

- **IP:** 83.166.246.225
- **Логин:** root
- **Пароль:** kcokmkzgHQ5dJOBF
- **Панель управления:** https://cv5970021.regru.cloud:1500/

## Способ 1: Автоматическая настройка (РЕКОМЕНДУЕТСЯ)

### Шаг 1: Подключение к серверу

```bash
ssh root@83.166.246.225
# Введите пароль: kcokmkzgHQ5dJOBF
```

### Шаг 2: Загрузка и выполнение скрипта

```bash
# Скачайте скрипт на сервер
curl -o setup_https.sh https://raw.githubusercontent.com/your-repo/setup_https.sh

# Или создайте файл вручную:
nano setup_https.sh
# Скопируйте содержимое файла setup_https.sh из проекта

# Сделайте скрипт исполняемым
chmod +x setup_https.sh

# Запустите скрипт
bash setup_https.sh
```

Скрипт автоматически:
- ✅ Установит Nginx
- ✅ Создаст SSL сертификат
- ✅ Настроит HTTPS прокси на порт 3000
- ✅ Настроит WebSocket (WSS)
- ✅ Откроет необходимые порты в файрволе

### Шаг 3: Проверка работы

```bash
# Проверка HTTPS
curl -k https://83.166.246.225

# Проверка статуса Nginx
systemctl status nginx

# Проверка портов
netstat -tuln | grep -E ':(80|443|3000)'
```

---

## Способ 2: Ручная настройка через ISPmanager

### Шаг 1: Вход в панель управления

1. Откройте: https://cv5970021.regru.cloud:1500/
2. Войдите с данными:
   - **Логин:** root
   - **Пароль:** kcokmkzgHQ5dJOBF

### Шаг 2: Установка Nginx через ISPmanager

1. Перейдите в раздел **"Веб-серверы"** → **"Nginx"**
2. Если Nginx не установлен, нажмите **"Установить"**
3. Дождитесь установки

### Шаг 3: Создание SSL сертификата

1. Перейдите в **"SSL-сертификаты"**
2. Нажмите **"Создать"**
3. Выберите **"Самоподписанный сертификат"**
4. Заполните:
   - **Доменное имя:** 83.166.246.225
   - **Email:** ваш email
5. Нажмите **"Создать"**

### Шаг 4: Настройка виртуального хоста

1. Перейдите в **"Веб-серверы"** → **"Виртуальные хосты"**
2. Нажмите **"Создать"**
3. Заполните:
   - **Доменное имя:** 83.166.246.225
   - **IP-адрес:** 83.166.246.225
   - **Порт:** 443
   - **SSL:** Включить
   - **SSL сертификат:** Выберите созданный сертификат
4. В разделе **"Настройки прокси"**:
   - **Включить прокси:** Да
   - **Проксировать на:** http://localhost:3000
5. Нажмите **"Создать"**

---

## Способ 3: Ручная настройка через SSH (если ISPmanager не работает)

### Шаг 1: Подключение

```bash
ssh root@83.166.246.225
```

### Шаг 2: Установка пакетов

```bash
apt update
apt install -y nginx openssl
```

### Шаг 3: Создание SSL сертификата

```bash
mkdir -p /etc/nginx/ssl
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout /etc/nginx/ssl/server.key \
    -out /etc/nginx/ssl/server.crt \
    -subj "/C=RU/ST=Moscow/L=Moscow/O=MessengerApp/CN=83.166.246.225"

chmod 600 /etc/nginx/ssl/server.key
chmod 644 /etc/nginx/ssl/server.crt
```

### Шаг 4: Создание конфигурации Nginx

```bash
nano /etc/nginx/sites-available/messenger-app
```

Вставьте следующее содержимое:

```nginx
server {
    listen 80;
    server_name 83.166.246.225;
    return 301 https://$server_name$request_uri;
}

server {
    listen 443 ssl http2;
    server_name 83.166.246.225;
    
    ssl_certificate /etc/nginx/ssl/server.crt;
    ssl_certificate_key /etc/nginx/ssl/server.key;
    
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_prefer_server_ciphers on;
    
    location / {
        proxy_pass http://localhost:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_read_timeout 86400;
        proxy_send_timeout 86400;
    }
}
```

Сохраните: `Ctrl+O`, `Enter`, `Ctrl+X`

### Шаг 5: Активация и перезагрузка

```bash
ln -s /etc/nginx/sites-available/messenger-app /etc/nginx/sites-enabled/
nginx -t
systemctl reload nginx
```

### Шаг 6: Настройка файрвола

```bash
ufw allow 80/tcp
ufw allow 443/tcp
ufw allow 22/tcp
ufw enable
```

---

## Проверка работы

### 1. Проверка HTTPS

```bash
# С сервера
curl -k https://localhost

# С вашего компьютера
curl -k https://83.166.246.225
```

### 2. Проверка WebSocket

Откройте в браузере консоль разработчика и выполните:

```javascript
const ws = new WebSocket('wss://83.166.246.225');
ws.onopen = () => console.log('WebSocket connected!');
ws.onerror = (e) => console.error('WebSocket error:', e);
```

### 3. Проверка логов

```bash
# Логи доступа
tail -f /var/log/nginx/messenger-access.log

# Логи ошибок
tail -f /var/log/nginx/messenger-error.log

# Логи Nginx
tail -f /var/log/nginx/error.log
```

---

## Обновление приложения после настройки HTTPS

После успешной настройки HTTPS на сервере:

1. **Обновите `lib/config/api_config.dart`:**
```dart
static const String baseUrl = 'https://83.166.246.225';
static const String wsUrl = 'https://83.166.246.225';
```

2. **Обновите `ios/Runner/Info.plist`** (уберите настройки для HTTP, оставьте только HTTPS)

3. **Соберите новую версию приложения**

---

## Решение проблем

### Проблема: Nginx не запускается

```bash
# Проверка конфигурации
nginx -t

# Просмотр ошибок
journalctl -u nginx -n 50

# Перезапуск
systemctl restart nginx
```

### Проблема: Порт 443 занят

```bash
# Проверка, что использует порт 443
netstat -tulpn | grep 443

# Если ISPmanager использует порт, измените порт в конфигурации Nginx
```

### Проблема: Node.js приложение не отвечает

```bash
# Проверка, что приложение работает
netstat -tuln | grep 3000

# Проверка логов приложения
# (зависит от того, как вы запускаете приложение)
```

### Проблема: WebSocket не работает

Убедитесь, что в конфигурации Nginx есть:
```nginx
proxy_set_header Upgrade $http_upgrade;
proxy_set_header Connection "upgrade";
proxy_read_timeout 86400;
```

---

## Получение валидного SSL сертификата (если есть домен)

Если у вас есть домен (например, example.com):

1. **Привяжите домен к IP:**
   - В панели управления доменом добавьте A-запись: `example.com` → `83.166.246.225`

2. **Получите сертификат Let's Encrypt:**
```bash
apt install certbot python3-certbot-nginx
certbot --nginx -d example.com
```

3. **Обновите конфигурацию Nginx** (certbot сделает это автоматически)

4. **Обновите приложение:**
```dart
static const String baseUrl = 'https://example.com';
static const String wsUrl = 'https://example.com';
```

---

## Готово! 🎉

После выполнения этих шагов:
- ✅ HTTPS будет работать на порту 443
- ✅ HTTP будет автоматически перенаправляться на HTTPS
- ✅ WebSocket будет работать через WSS
- ✅ Приложение будет работать через мобильные данные Мегафона
