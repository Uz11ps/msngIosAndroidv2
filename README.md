# Мессенджер - Flutter приложение

Мобильное приложение для Android и iOS, подключенное к бэкенду мессенджера.

## Возможности

- ✅ Регистрация и вход по email/паролю
- ✅ Список чатов
- ✅ Отправка и получение сообщений в реальном времени
- ✅ Профиль пользователя
- ✅ WebSocket для реал-тайм коммуникации

## Технологии

- Flutter 3.24.0
- Dart 3.5.0
- Provider для управления состоянием
- Socket.IO для WebSocket соединений
- HTTP для REST API запросов

## Установка и запуск

1. Убедитесь, что Flutter установлен:
```bash
flutter --version
```

2. Установите зависимости:
```bash
flutter pub get
```

3. Запустите приложение:
```bash
flutter run
```

## Структура проекта

```
lib/
├── config/          # Конфигурация API
├── models/          # Модели данных (User, Chat, Message)
├── providers/       # Провайдеры состояния (AuthProvider, ChatProvider)
├── screens/         # Экраны приложения
├── services/        # Сервисы (API, Socket, Auth)
└── main.dart        # Точка входа
```

## API эндпоинты

Бэкенд находится на `http://83.166.246.225:3000`

### Аутентификация
- `POST /api/auth/email-login` - Вход по email
- `POST /api/auth/email-register` - Регистрация
- `POST /api/auth/send-otp` - Отправка OTP кода
- `POST /api/auth/verify-otp` - Проверка OTP кода

### Пользователи
- `GET /api/users/search` - Поиск пользователей
- `GET /api/users/:userId` - Получить пользователя
- `POST /api/users/update` - Обновить профиль
- `POST /api/users/link-email` - Привязать email
- `POST /api/users/link-phone` - Привязать телефон

### Чаты
- `POST /api/chats/create` - Создать чат
- `POST /api/chats/group` - Создать групповой чат
- `GET /api/chats` - Получить список чатов
- `GET /api/chats/:chatId/messages` - Получить сообщения чата

### WebSocket события
- `send_message` - Отправить сообщение
- `new_message` - Новое сообщение
- `call_user` - Звонок пользователю
- `incoming_call` - Входящий звонок

## Разрешения

### Android
Разрешения для интернета добавлены в `AndroidManifest.xml`

### iOS
Настроен `NSAppTransportSecurity` в `Info.plist` для работы с HTTP

## Следующие шаги

- [ ] Добавить загрузку изображений
- [ ] Реализовать звонки (видео/аудио)
- [ ] Добавить уведомления (FCM)
- [ ] Улучшить UI/UX
- [ ] Добавить поиск пользователей
- [ ] Реализовать создание групповых чатов
