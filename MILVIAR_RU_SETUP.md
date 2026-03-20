# Настройка HTTPS для домена milviar.ru

## Шаг 1: Настройка DNS записи

Убедитесь, что DNS запись для домена `milviar.ru` указывает на IP сервера `83.166.246.225`.

### В панели управления доменом (Reg.ru или другой регистратор):

1. Перейдите в настройки домена `milviar.ru`
2. Найдите раздел **"DNS записи"** или **"Управление DNS"**
3. Добавьте или измените A-запись:
   - **Тип:** A
   - **Имя:** @ (или оставьте пустым для корневого домена)
   - **Значение:** `83.166.246.225`
   - **TTL:** 3600
4. Опционально добавьте запись для www:
   - **Тип:** A
   - **Имя:** www
   - **Значение:** `83.166.246.225`
   - **TTL:** 3600
5. Сохраните изменения

### Проверка DNS:

Подождите 5-15 минут для распространения DNS записей, затем проверьте:

```bash
# С вашего компьютера
nslookup milviar.ru
# или
dig milviar.ru A

# Должно показать: 83.166.246.225
```

---

## Шаг 2: Настройка HTTPS на сервере

### Подключитесь к серверу:

```bash
ssh root@83.166.246.225
# Пароль: kcokmkzgHQ5dJOBF
```

### Запустите скрипт автоматической настройки:

```bash
# Создайте файл скрипта
nano setup_milviar_ru.sh

# Скопируйте содержимое файла setup_milviar_ru.sh из проекта и вставьте в nano
# Сохраните: Ctrl+O, Enter, Ctrl+X

# Сделайте скрипт исполняемым
chmod +x setup_milviar_ru.sh

# Запустите скрипт
bash setup_milviar_ru.sh
```

Скрипт автоматически:
- ✅ Установит Nginx и Certbot
- ✅ Настроит временную конфигурацию для получения сертификата
- ✅ Получит валидный SSL сертификат от Let's Encrypt для `milviar.ru` и `www.milviar.ru`
- ✅ Настроит HTTPS с поддержкой WebSocket
- ✅ Настроит автоматическое обновление сертификата
- ✅ Откроет необходимые порты в файрволе

---

## Шаг 3: Проверка работы HTTPS

### Проверка в браузере:

Откройте в браузере:
- https://milviar.ru
- https://www.milviar.ru

**Должно быть БЕЗ предупреждений о безопасности!** ✅

### Проверка через curl:

```bash
# С сервера
curl -I https://milviar.ru

# Должно показать HTTP/2 200 или 301
```

### Проверка SSL сертификата:

```bash
openssl s_client -connect milviar.ru:443 -showcerts | grep -A 2 "Certificate chain"
```

---

## Шаг 4: Обновление приложения

### Файл `lib/config/api_config.dart`:

Уже обновлен автоматически:
```dart
static const String baseUrl = 'https://milviar.ru';
static const String wsUrl = 'https://milviar.ru';
```

### Файл `ios/Runner/Info.plist`:

Уже обновлен автоматически для домена `milviar.ru`

### Версия билда:

Обновите версию перед сборкой:
```yaml
# pubspec.yaml
version: 1.0.0+13
```

---

## Шаг 5: Сборка и тестирование

1. **Соберите новую версию приложения:**
```bash
cd /Users/uz1ps/msngIosAndroidv2
flutter clean
flutter pub get
flutter build ios
```

2. **Протестируйте:**
   - ✅ Через Wi-Fi
   - ✅ Через мобильные данные Мегафона
   - ✅ Все функции должны работать

---

## Решение проблем

### Проблема: DNS не распространился

**Решение:**
- Подождите до 24 часов (обычно 5-15 минут)
- Проверьте DNS: `nslookup milviar.ru`
- Убедитесь, что A-запись правильная

### Проблема: Certbot не может получить сертификат

**Ошибка:** "Failed to verify domain"

**Решение:**
1. Убедитесь, что DNS запись указывает на правильный IP
2. Убедитесь, что порт 80 открыт: `ufw allow 80/tcp`
3. Проверьте, что Nginx работает: `systemctl status nginx`
4. Проверьте логи: `journalctl -u certbot -n 50`

### Проблема: WebSocket не работает

**Решение:**
1. Проверьте конфигурацию Nginx:
```bash
cat /etc/nginx/sites-available/messenger-app | grep -A 5 "proxy_set_header Upgrade"
```

2. Должны быть строки:
```nginx
proxy_set_header Upgrade $http_upgrade;
proxy_set_header Connection "upgrade";
proxy_read_timeout 86400;
```

3. Перезагрузите Nginx: `systemctl reload nginx`

### Проблема: Приложение не подключается

**Решение:**
1. Проверьте, что Node.js приложение работает на порту 3000:
```bash
netstat -tuln | grep 3000
```

2. Проверьте логи Nginx:
```bash
tail -f /var/log/nginx/messenger-error.log
```

3. Проверьте логи приложения Node.js

---

## Полезные команды

```bash
# Проверка статуса Nginx
systemctl status nginx

# Перезагрузка Nginx
systemctl reload nginx

# Просмотр логов Nginx
tail -f /var/log/nginx/messenger-error.log
tail -f /var/log/nginx/messenger-access.log

# Проверка SSL сертификата
openssl s_client -connect milviar.ru:443 -showcerts

# Проверка автообновления сертификата
certbot renew --dry-run

# Просмотр информации о сертификате
certbot certificates
```

---

## Автоматическое обновление сертификата

Certbot автоматически настроит обновление сертификата. Сертификат Let's Encrypt действителен 90 дней и будет автоматически обновляться за 30 дней до истечения.

Проверка автообновления:
```bash
certbot renew --dry-run
```

---

## Готово! ✅

После выполнения всех шагов:
- ✅ HTTPS работает на https://milviar.ru
- ✅ SSL сертификат валидный (без предупреждений)
- ✅ WebSocket работает через WSS
- ✅ Приложение работает через мобильные данные Мегафона
- ✅ Сертификат автоматически обновляется

**Ваше приложение готово к использованию!** 🎉
