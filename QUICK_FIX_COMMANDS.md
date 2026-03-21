# Быстрое исправление - Выполните команды по порядку

## ⚠️ ВАЖНО: Вы уже в директории проекта! Не выполняйте `cd msngIosAndroidv2`

## Шаг 1: Очистка и подготовка

```bash
# Очистка Flutter
flutter clean

# Получение зависимостей (ВАЖНО: сначала это!)
flutter pub get

# Очистка iOS зависимостей
cd ios
rm -rf Pods Podfile.lock
pod install
cd ..

# Очистка кэша Xcode
rm -rf ~/Library/Developer/Xcode/DerivedData/*
```

## Шаг 2: Запуск эмулятора и сброс разрешений

```bash
# Запустите эмулятор
open -a Simulator

# ПОДОЖДИТЕ 30-60 секунд, пока эмулятор полностью загрузится!

# Удалите приложение (если установлено)
xcrun simctl uninstall booted com.vvedenskii.messenger

# Сбросьте настройки приватности
xcrun simctl privacy booted reset all
```

## Шаг 3: КРИТИЧЕСКИ ВАЖНО - Проверка в Xcode

```bash
# Откройте проект в Xcode
open ios/Runner.xcworkspace
```

**В Xcode выполните:**

1. Выберите проект `Runner` (синий значок слева)
2. Выберите таргет **`Runner`** (НЕ RunnerTests!)
3. Перейдите на вкладку **"Info"**
4. Проверьте раздел **"Custom iOS Target Properties"**
5. **Убедитесь, что видны ключи:**
   - `Privacy - Microphone Usage Description`
   - `Privacy - Camera Usage Description`
   - `Privacy - Photo Library Usage Description`
   - `Privacy - Photo Library Additions Usage Description`

6. **Если ключей НЕТ:**
   - Нажмите **"+"** внизу списка
   - Добавьте каждый ключ вручную из выпадающего списка
   - Введите значения из файла `Info.plist`

7. Перейдите на вкладку **"Build Settings"**
8. Найдите `INFOPLIST_FILE` - должно быть: `Runner/Info.plist`
9. Найдите `GENERATE_INFOPLIST_FILE` - должно быть: `NO` (или отсутствовать)

10. Сохраните проект (`Cmd + S`)
11. Закройте Xcode

## Шаг 4: Пересборка и запуск

```bash
# Пересборка
flutter clean
flutter pub get
cd ios
pod install
cd ..

# Запуск на эмуляторе
flutter run
```

## Шаг 5: Тестирование

1. Откройте чат в приложении
2. Нажмите кнопку звонка (аудио или видео)
3. **Должно появиться системное окно** с запросом разрешения
4. Проверьте Settings → Messenger App - должны быть видны разрешения

## Если не работает

См. подробную инструкцию в `CRITICAL_PERMISSIONS_FIX.md`
