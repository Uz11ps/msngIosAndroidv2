# 🔧 Пошаговое исправление

## Выполните эти команды на Mac:

### Шаг 1: Разрешите конфликт Git

```bash
cd msngIosAndroidv2

# Сохраните локальные изменения (если они нужны)
git stash

# Или закоммитьте их (если хотите сохранить)
# git add ios/
# git commit -m "Save local iOS changes"

# Обновите проект
git pull
```

### Шаг 2: Перезапустите эмулятор

```bash
# Закройте все эмуляторы
killall Simulator

# Подождите 2 секунды, затем запустите заново
sleep 2
open -a Simulator
```

### Шаг 3: Очистите проект полностью

```bash
cd msngIosAndroidv2

# Очистите Flutter
flutter clean

# Очистите iOS зависимости
cd ios
rm -rf Pods Podfile.lock
pod install
cd ..

# Очистите Xcode Derived Data (опционально, но рекомендуется)
rm -rf ~/Library/Developer/Xcode/DerivedData/*
```

### Шаг 4: Пересоберите и запустите

```bash
flutter pub get
flutter run
```

---

## 🔍 Если проблема сохраняется:

### Вариант A: Используйте другой эмулятор

```bash
# Посмотрите список доступных эмуляторов
xcrun simctl list devices

# Запустите другой эмулятор (например, iPhone 15)
flutter run -d "iPhone 15"
```

### Вариант B: Пересоздайте эмулятор

1. Откройте Xcode
2. Window → Devices and Simulators
3. Выберите проблемный эмулятор (iPhone 17 Pro)
4. Нажмите "Delete"
5. Создайте новый эмулятор
6. Запустите приложение

### Вариант C: Запустите через Xcode

```bash
cd ios
open Runner.xcworkspace
```

Затем в Xcode:
- Product → Clean Build Folder (Shift+Cmd+K)
- Product → Run (Cmd+R)

---

## ✅ После исправления:

Приложение должно запускаться без крашей, и разрешения будут запрашиваться при первом использовании функций (звонок, запись голосового сообщения, выбор изображения).
