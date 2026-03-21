# Финальное исправление разрешений iOS

## Проблема
Разрешения на микрофон, камеру и фото не появляются в настройках iOS приложения, хотя они есть в `Info.plist`.

## Решение

### Шаг 1: Правильная последовательность команд очистки

Выполните команды в правильном порядке (вы уже в директории проекта, не нужно `cd msngIosAndroidv2`):

```bash
# 1. Очистка Flutter
flutter clean

# 2. Получение зависимостей (это создаст Generated.xcconfig)
flutter pub get

# 3. Очистка iOS зависимостей
cd ios
rm -rf Pods Podfile.lock
pod install
cd ..

# 4. Очистка кэша Xcode
rm -rf ~/Library/Developer/Xcode/DerivedData/*
```

### Шаг 2: Запуск эмулятора ПЕРЕД сбросом разрешений

**ВАЖНО:** Эмулятор должен быть запущен перед выполнением команд сброса!

```bash
# Откройте эмулятор вручную или через Xcode
open -a Simulator

# Подождите, пока эмулятор полностью загрузится

# Затем удалите приложение (если оно установлено)
xcrun simctl uninstall booted com.vvedenskii.messenger

# Сбросьте все настройки приватности
xcrun simctl privacy booted reset all
```

### Шаг 3: Проверка Info.plist в Xcode

**КРИТИЧЕСКИ ВАЖНО:** Нужно проверить настройки в Xcode напрямую!

1. Откройте проект в Xcode:
   ```bash
   open ios/Runner.xcworkspace
   ```

2. В Xcode:
   - Выберите проект `Runner` в левой панели (синий значок)
   - Выберите таргет `Runner` (не RunnerTests!)
   - Перейдите на вкладку **"Info"**
   - Найдите раздел **"Custom iOS Target Properties"**
   - Убедитесь, что там есть следующие ключи:
     - `Privacy - Microphone Usage Description` (NSMicrophoneUsageDescription)
     - `Privacy - Camera Usage Description` (NSCameraUsageDescription)
     - `Privacy - Photo Library Usage Description` (NSPhotoLibraryUsageDescription)
     - `Privacy - Photo Library Additions Usage Description` (NSPhotoLibraryAddUsageDescription)

3. Если ключей нет в Xcode:
   - Нажмите кнопку **"+"** внизу списка
   - Добавьте каждый ключ вручную
   - Введите значения из `Info.plist`

4. Проверьте Build Settings:
   - Выберите таргет `Runner`
   - Перейдите на вкладку **"Build Settings"**
   - Найдите `INFOPLIST_FILE` (используйте поиск)
   - Убедитесь, что значение: `Runner/Info.plist`
   - Найдите `GENERATE_INFOPLIST_FILE` (если есть)
   - Убедитесь, что значение: `NO` (для основного таргета Runner)

### Шаг 4: Полная пересборка

```bash
# Вернитесь в корень проекта (если вы в ios/)
cd ..

# Полная пересборка
flutter clean
flutter pub get
cd ios
pod install
cd ..
flutter build ios --simulator
```

### Шаг 5: Установка и запуск на эмуляторе

```bash
# Убедитесь, что эмулятор запущен
open -a Simulator

# Запустите приложение
flutter run
```

### Шаг 6: Тестирование разрешений

1. После запуска приложения:
   - Откройте чат
   - Нажмите кнопку звонка (аудио или видео)
   - Должно появиться системное окно запроса разрешения на микрофон/камеру

2. Проверьте настройки:
   - Откройте Settings (Настройки) на эмуляторе
   - Найдите ваше приложение "Messenger App"
   - Должны быть видны разрешения: Microphone, Camera, Photos

## Если проблема остается

Если после всех шагов разрешения все еще не появляются:

1. **Проверьте, что вы редактируете правильный Info.plist:**
   ```bash
   cat ios/Runner/Info.plist | grep -A 1 "NSMicrophoneUsageDescription"
   ```

2. **Убедитесь, что Info.plist включен в Copy Bundle Resources:**
   - В Xcode: Runner target → Build Phases → Copy Bundle Resources
   - Должен быть `Info.plist`

3. **Попробуйте удалить и пересоздать эмулятор:**
   ```bash
   # Список эмуляторов
   xcrun simctl list devices
   
   # Удалите текущий эмулятор и создайте новый
   ```

4. **Проверьте версию iOS на эмуляторе:**
   - Должна быть iOS 14.0 или выше
   - Проверьте в Xcode: Window → Devices and Simulators

## Альтернативное решение: Добавление разрешений через Xcode UI

Если файл Info.plist не работает, добавьте разрешения напрямую через Xcode:

1. Откройте `ios/Runner.xcworkspace` в Xcode
2. Выберите проект → Runner target → Info tab
3. Нажмите "+" и добавьте каждый ключ вручную:
   - `Privacy - Microphone Usage Description` = "Приложению необходим доступ к микрофону для записи голосовых сообщений и аудиозвонков"
   - `Privacy - Camera Usage Description` = "Приложению необходим доступ к камере для отправки фотографий и видеозвонков"
   - `Privacy - Photo Library Usage Description` = "Приложению необходим доступ к галерее для выбора фотографий"
   - `Privacy - Photo Library Additions Usage Description` = "Приложению необходим доступ для сохранения фотографий в галерею"
4. Сохраните проект (Cmd+S)
5. Выполните полную пересборку
