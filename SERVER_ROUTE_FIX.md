# Исправление ошибки "Маршрут не найден"

## Проблема

При обращении к `http://83.166.246.225:3000/api/auth/email-register` сервер возвращает:
```json
{"success":false,"error":"Маршрут не найден","path":"/api/auth/email-register"}
```

## Причина

Маршрут зарегистрирован правильно в коде (строка 156 в `бекенд/index.js`), но сервер не видит его. Это означает, что:

1. **Сервер не перезапущен** после изменений в коде
2. **Используется старая версия** файла `index.js`
3. **Процесс запущен из другой директории** и использует другой файл

## Решение

### Вариант 1: Перезапуск через PM2 (рекомендуется)

Если сервер запущен через PM2:

```bash
cd бекенд
pm2 restart messenger-backend
# или
pm2 restart all
```

Проверьте статус:
```bash
pm2 status
pm2 logs messenger-backend --lines 50
```

### Вариант 2: Полный перезапуск

```bash
cd бекенд

# Остановите старый процесс
pm2 stop messenger-backend
# или
pkill -f "node.*index.js"

# Запустите заново
pm2 start index.js --name messenger-backend
# или
node index.js
```

### Вариант 3: Использование скрипта

Я создал скрипт `restart_server.sh`:

```bash
cd бекенд
chmod +x restart_server.sh
./restart_server.sh
```

## Проверка

После перезапуска проверьте:

1. **Проверка в браузере:**
   ```
   http://83.166.246.225:3000/api/auth/email-register
   ```
   
   Должен вернуться JSON (не HTML):
   ```json
   {"success":false,"message":"Email и пароль обязательны"}
   ```

2. **Проверка через curl:**
   ```bash
   curl -X POST http://83.166.246.225:3000/api/auth/email-register \
     -H "Content-Type: application/json" \
     -d '{"email":"test@test.com","password":"123456"}'
   ```

3. **Проверка логов:**
   ```bash
   pm2 logs messenger-backend
   # или
   tail -f server.log
   ```

## Если проблема остается

1. **Проверьте, что файл правильный:**
   ```bash
   cd бекенд
   grep -n "email-register" index.js
   ```
   
   Должна быть строка:
   ```
   156:app.post('/api/auth/email-register', async (req, res) => {
   ```

2. **Проверьте, что процесс запущен из правильной директории:**
   ```bash
   pm2 info messenger-backend
   # Проверьте поле "script path"
   ```

3. **Проверьте, нет ли другого процесса на порту 3000:**
   ```bash
   lsof -i :3000
   # или
   netstat -tulpn | grep 3000
   ```

4. **Убедитесь, что база данных доступна:**
   ```bash
   cd бекенд
   ls -la database.sqlite
   ```

## Дополнительная диагностика

Добавьте логирование в начало маршрута для отладки:

```javascript
app.post('/api/auth/email-register', async (req, res) => {
  console.log('[DEBUG] Registration route called');
  console.log('[DEBUG] Request body:', req.body);
  // ... остальной код
});
```

После перезапуска проверьте логи - должны появиться сообщения `[DEBUG]` при запросе.
