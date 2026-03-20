# Простая настройка HTTPS для milviar.ru

## Шаг 1: Настройка DNS (в панели управления доменом)

1. Зайдите в панель управления доменом `milviar.ru`
2. Найдите раздел "DNS записи" или "Управление DNS"
3. Добавьте A-запись:
   - **Тип:** A
   - **Имя:** @ (или пустое)
   - **IP:** 83.166.246.225
   - **TTL:** 3600
4. Сохраните

**Подождите 10-15 минут** для распространения DNS.

---

## Шаг 2: Подключение к серверу

Откройте терминал и выполните:

```bash
ssh root@83.166.246.225
```

Введите пароль: `kcokmkzgHQ5dJOBF`

---

## Шаг 3: Установка пакетов

Скопируйте и выполните эти команды по очереди:

```bash
apt update
```

```bash
apt install -y nginx certbot python3-certbot-nginx openssl ufw
```

---

## Шаг 4: Проверка DNS

```bash
dig milviar.ru +short
```

Должно показать: `83.166.246.225`

Если показывает другой IP или ничего - подождите еще 10 минут и проверьте снова.

---

## Шаг 5: Создание временной конфигурации Nginx

```bash
cat > /etc/nginx/sites-available/messenger-app << 'EOF'
server {
    listen 80;
    server_name milviar.ru www.milviar.ru;
    
    location /.well-known/acme-challenge/ {
        root /var/www/html;
    }
    
    location / {
        proxy_pass http://localhost:3000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    }
}
EOF
```

---

## Шаг 6: Активация конфигурации

```bash
ln -sf /etc/nginx/sites-available/messenger-app /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default
nginx -t
```

---

## Шаг 7: Запуск Nginx

```bash
systemctl enable nginx
systemctl start nginx
systemctl reload nginx
```

---

## Шаг 8: Настройка файрвола

```bash
ufw --force enable
ufw allow 22/tcp
ufw allow 80/tcp
ufw allow 443/tcp
```

---

## Шаг 9: Получение SSL сертификата

```bash
certbot --nginx -d milviar.ru -d www.milviar.ru --non-interactive --agree-tos --email admin@milviar.ru --redirect
```

**Важно:** Если появится ошибка про email, замените `admin@milviar.ru` на ваш реальный email.

---

## Шаг 10: Обновление конфигурации для WebSocket

```bash
cat > /etc/nginx/sites-available/messenger-app << 'EOF'
server {
    listen 80;
    server_name milviar.ru www.milviar.ru;
    return 301 https://$server_name$request_uri;
}

server {
    listen 443 ssl http2;
    server_name milviar.ru www.milviar.ru;
    
    ssl_certificate /etc/letsencrypt/live/milviar.ru/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/milviar.ru/privkey.pem;
    
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_prefer_server_ciphers on;
    
    client_max_body_size 100M;
    
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
        proxy_buffering off;
    }
}
EOF
```

---

## Шаг 11: Перезагрузка Nginx

```bash
nginx -t
systemctl reload nginx
```

---

## Шаг 12: Проверка работы

```bash
curl -I https://milviar.ru
```

Должно показать `HTTP/2 200` или `HTTP/2 301`.

---

## Если что-то пошло не так

### Ошибка: DNS не распространился

Подождите еще 15-30 минут и проверьте снова:
```bash
dig milviar.ru +short
```

### Ошибка: Certbot не может получить сертификат

Проверьте логи:
```bash
journalctl -u certbot -n 50
```

Убедитесь, что:
1. DNS запись правильная: `dig milviar.ru +short` показывает `83.166.246.225`
2. Порт 80 открыт: `ufw status | grep 80`
3. Nginx работает: `systemctl status nginx`

### Ошибка: Nginx не запускается

Проверьте конфигурацию:
```bash
nginx -t
```

Просмотрите ошибки:
```bash
tail -f /var/log/nginx/error.log
```

---

## После успешной настройки

1. Откройте в браузере: https://milviar.ru
2. Должно быть БЕЗ предупреждений о безопасности
3. Соберите новую версию приложения (уже обновлено в коде)

---

## Готово! ✅

Если все шаги выполнены успешно:
- ✅ HTTPS работает на https://milviar.ru
- ✅ SSL сертификат валидный
- ✅ WebSocket работает через WSS
- ✅ Приложение готово к использованию
