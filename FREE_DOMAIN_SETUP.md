# Получение бесплатного домена и настройка Let's Encrypt

## Вариант 1: Freenom (бесплатные домены .tk, .ml, .ga, .cf)

### Шаг 1: Регистрация домена

1. Перейдите на https://www.freenom.com/
2. Зарегистрируйтесь или войдите
3. В поиске введите желаемое имя (например: `messenger-app`)
4. Выберите бесплатный домен (.tk, .ml, .ga, .cf)
5. Добавьте в корзину и оформите заказ (бесплатно на 12 месяцев)

### Шаг 2: Настройка DNS

1. В панели управления Freenom перейдите в **"Services"** → **"My Domains"**
2. Выберите ваш домен
3. Перейдите в **"Manage Domain"** → **"Management Tools"** → **"Nameservers"**
4. Выберите **"Use default nameservers"** или настройте:
   - `ns1.freenom.com`
   - `ns2.freenom.com`
5. Перейдите в **"Management Tools"** → **"DNS"**
6. Добавьте A-запись:
   - **Type:** A
   - **Name:** @ (или `api` для поддомена)
   - **TTL:** 3600
   - **Target:** `83.166.246.225`
7. Сохраните изменения

### Шаг 3: Ожидание распространения DNS

Подождите 5-30 минут для распространения DNS записей. Проверьте:

```bash
# Проверка DNS
nslookup your-domain.tk
# или
dig your-domain.tk A
```

### Шаг 4: Получение SSL сертификата Let's Encrypt

```bash
# Подключитесь к серверу
ssh root@83.166.246.225

# Установите Certbot (если еще не установлен)
apt install certbot python3-certbot-nginx -y

# Получите сертификат
certbot --nginx -d your-domain.tk

# Следуйте инструкциям:
# - Введите email
# - Согласитесь с условиями
# - Certbot автоматически настроит Nginx
```

### Шаг 5: Автоматическое обновление

Certbot автоматически настроит обновление сертификата. Проверьте:

```bash
certbot renew --dry-run
```

---

## Вариант 2: NoIP (бесплатный динамический домен)

### Шаг 1: Регистрация

1. Перейдите на https://www.noip.com/
2. Зарегистрируйтесь (бесплатный аккаунт)
3. Подтвердите email

### Шаг 2: Создание хоста

1. Войдите в панель управления
2. Перейдите в **"Dynamic DNS"** → **"Hostnames"**
3. Нажмите **"Create Hostname"**
4. Заполните:
   - **Hostname:** например `messenger-app`
   - **Domain:** выберите из списка (например `.ddns.net`)
   - **IPv4 Address:** `83.166.246.225`
5. Нажмите **"Create Hostname"**

### Шаг 3: Настройка DNS

DNS настраивается автоматически. Подождите 5-10 минут.

### Шаг 4: Получение SSL сертификата

```bash
certbot --nginx -d your-hostname.ddns.net
```

---

## Вариант 3: DuckDNS (бесплатный поддомен)

### Шаг 1: Регистрация

1. Перейдите на https://www.duckdns.org/
2. Войдите через Google/GitHub/Twitter
3. Создайте поддомен (например: `messenger-app`)

### Шаг 2: Настройка IP

1. В панели управления DuckDNS
2. Введите ваш IP: `83.166.246.225`
3. Нажмите **"Update IP"**

### Шаг 3: Получение SSL сертификата

```bash
certbot --nginx -d your-subdomain.duckdns.org
```

---

## После получения домена и SSL сертификата

### Обновление конфигурации Nginx

Certbot автоматически обновит конфигурацию Nginx. Проверьте:

```bash
cat /etc/nginx/sites-available/messenger-app
```

### Обновление приложения

Обновите `lib/config/api_config.dart`:

```dart
static const String baseUrl = 'https://your-domain.tk';  // ваш домен
static const String wsUrl = 'https://your-domain.tk';
```

### Обновление Info.plist

Убедитесь, что в `Info.plist` есть настройки для вашего домена:

```xml
<key>NSExceptionDomains</key>
<dict>
    <key>your-domain.tk</key>
    <dict>
        <key>NSIncludesSubdomains</key>
        <true/>
        <key>NSExceptionRequiresForwardSecrecy</key>
        <false/>
        <key>NSExceptionMinimumTLSVersion</key>
        <string>TLSv1.0</string>
    </dict>
</dict>
```

---

## Проверка работы

```bash
# Проверка SSL сертификата
openssl s_client -connect your-domain.tk:443 -showcerts

# Проверка через curl
curl -v https://your-domain.tk

# Проверка в браузере
# Откройте https://your-domain.tk - должно быть без предупреждений!
```

---

## Рекомендации

1. **Freenom** - самый простой вариант, домены на 12 месяцев бесплатно
2. **NoIP** - требует подтверждение каждые 30 дней (бесплатно)
3. **DuckDNS** - очень простой, но только поддомены

**Лучший выбор:** Freenom для полноценного домена или DuckDNS для быстрой настройки.
