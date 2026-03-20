# Статус сервера и API

## ✅ Сервер работает правильно

### Проверка HTTPS:
```bash
curl -I https://milviar.ru
# HTTP/2 200 ✅
```

### Проверка SSL сертификата:
```bash
openssl s_client -connect milviar.ru:443 -servername milviar.ru
# Сертификат: Let's Encrypt ✅
# Verify return code: 0 (ok) ✅
```

### Проверка API:
```bash
curl https://milviar.ru/api/auth/email-login -X POST -H 'Content-Type: application/json' -d '{"email":"test","password":"test"}'
# Возвращает ответ от сервера ✅
```

### Корневой путь:
```bash
curl https://milviar.ru
# {"status":"ok","message":"API Server is running","api":"https://milviar.ru/api"} ✅
```

---

## Конфигурация

### Nginx:
- ✅ HTTPS настроен (порт 443)
- ✅ SSL сертификат Let's Encrypt валидный
- ✅ Проксирование на Node.js (порт 3000)
- ✅ WebSocket поддержка (WSS)
- ✅ Автоматический редирект HTTP → HTTPS

### Node.js:
- ✅ Приложение работает на порту 3000
- ✅ API эндпоинты доступны через `/api/*`
- ✅ WebSocket работает через Socket.IO

---

## URL для приложения

**Base URL:** `https://milviar.ru`
**WebSocket URL:** `https://milviar.ru`

**Все запросы идут через HTTPS** ✅

---

## Если у заказчика проблемы

### Проверьте:
1. **В Safari:** Откройте `https://milviar.ru` - должно показать `{"status":"ok",...}`
2. **Версия приложения:** Должна быть **1.0.0+16** или выше
3. **Логи приложения:** Должны показывать `https://milviar.ru` в URL

### Если не работает:
- Проверьте DNS на устройстве заказчика
- Попробуйте через Wi-Fi
- Попробуйте через VPN
- Перезагрузите устройство
