# Инструкция по сборке и загрузке в TestFlight

## Подготовка проекта для iOS

### 1. Проверка зависимостей

Убедитесь, что все зависимости установлены:
```bash
cd ios
pod install
cd ..
flutter pub get
```

### 2. Настройка версии приложения

В файле `pubspec.yaml` установите версию:
```yaml
version: 1.0.0+1
```
Где:
- `1.0.0` - версия приложения (CFBundleShortVersionString)
- `+1` - build number (CFBundleVersion)

Для каждого нового билда увеличивайте build number: `1.0.0+2`, `1.0.0+3` и т.д.

### 3. Настройка Bundle Identifier в Xcode

1. Откройте проект в Xcode:
   ```bash
   open ios/Runner.xcworkspace
   ```
   ⚠️ Важно: открывайте `.xcworkspace`, а не `.xcodeproj`!

2. В Xcode:
   - Выберите проект `Runner` в навигаторе слева
   - Выберите target `Runner`
   - Перейдите на вкладку `Signing & Capabilities`
   - Убедитесь, что `Automatically manage signing` включено
   - Выберите вашу Team (Apple Developer Account)
   - Проверьте Bundle Identifier (должен быть уникальным, например: `com.yourcompany.messenger_app`)

### 4. Настройка App Icons

Убедитесь, что все иконки приложения добавлены в `ios/Runner/Assets.xcassets/AppIcon.appiconset/`

### 5. Сборка для TestFlight

#### Вариант 1: Через Xcode (Рекомендуется)

1. Откройте проект в Xcode:
   ```bash
   open ios/Runner.xcworkspace
   ```

2. В Xcode:
   - Выберите `Product` → `Scheme` → `Runner`
   - Выберите `Any iOS Device` в списке устройств (не симулятор!)
   - Выберите `Product` → `Archive`

3. После завершения архивации откроется окно `Organizer`
   - Выберите ваш архив
   - Нажмите `Distribute App`
   - Выберите `App Store Connect`
   - Нажмите `Next`
   - Выберите `Upload` (для TestFlight)
   - Следуйте инструкциям

#### Вариант 2: Через командную строку

```bash
# Очистка предыдущих сборок
flutter clean
flutter pub get
cd ios
pod install
cd ..

# Сборка для release
flutter build ipa --release

# После сборки файл будет в: build/ios/ipa/messenger_app.ipa
```

Затем загрузите `.ipa` файл через:
- Xcode → Window → Organizer → Archives → Distribute App
- Или через Transporter app от Apple

### 6. Загрузка в App Store Connect

1. Войдите в [App Store Connect](https://appstoreconnect.apple.com/)
2. Перейдите в `My Apps` → выберите ваше приложение
3. Перейдите на вкладку `TestFlight`
4. После обработки билда (может занять 10-30 минут) вы сможете:
   - Добавить тестировщиков
   - Отправить приглашения на тестирование
   - Установить приложение через TestFlight

### 7. Проверка перед загрузкой

Убедитесь, что:
- ✅ Все разрешения настроены в `Info.plist`
- ✅ Bundle Identifier уникален
- ✅ Версия и build number установлены правильно
- ✅ App Icons добавлены
- ✅ Приложение работает на реальном устройстве iOS
- ✅ Все функции протестированы (звонки, сообщения, загрузка файлов)

### 8. Частые проблемы и решения

#### Проблема: "No such module 'Flutter'"
**Решение:**
```bash
cd ios
pod deintegrate
pod install
cd ..
flutter clean
flutter pub get
```

#### Проблема: "Code signing error"
**Решение:**
- Проверьте, что выбран правильный Team в Xcode
- Убедитесь, что у вас есть активная подписка Apple Developer ($99/год)

#### Проблема: "Agora SDK not found"
**Решение:**
```bash
cd ios
pod install --repo-update
cd ..
```

#### Проблема: "Invalid Bundle"
**Решение:**
- Проверьте, что Bundle Identifier уникален
- Убедитесь, что версия и build number установлены правильно

### 9. Увеличение версии для следующего билда

Перед каждой новой загрузкой в TestFlight:
1. Обновите версию в `pubspec.yaml`:
   ```yaml
   version: 1.0.0+2  # Увеличьте build number
   ```
2. Или обновите только build number:
   ```yaml
   version: 1.0.0+3  # Только build number увеличивается
   ```

### 10. Тестирование на реальном устройстве перед TestFlight

```bash
# Подключите iPhone через USB
# Убедитесь, что устройство доверено в Xcode
flutter run --release -d <device-id>
```

Где `<device-id>` можно узнать командой:
```bash
flutter devices
```

## Дополнительные настройки для продакшена

### Настройка App Store Connect

1. **App Information:**
   - Название приложения
   - Подкатегория
   - Ключевые слова
   - Поддержка сайт

2. **Pricing and Availability:**
   - Цена (можно установить бесплатно)
   - Доступность по странам

3. **App Privacy:**
   - Укажите, какие данные собирает приложение
   - Для мессенджера: контакты, сообщения, аудио, фото, видео

### Требования App Store

- ✅ Приложение должно работать без интернета (базовая функциональность)
- ✅ Все функции должны быть доступны без дополнительных покупок
- ✅ Приватность пользователей должна быть защищена
- ✅ Контент должен соответствовать правилам App Store

## Контакты для поддержки

Если возникнут проблемы:
1. Проверьте логи в Xcode (Window → Devices and Simulators → View Device Logs)
2. Проверьте статус билда в App Store Connect
3. Обратитесь в поддержку Apple Developer, если проблема с аккаунтом
