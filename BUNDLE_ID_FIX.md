# 🔧 Исправление Bundle Identifier

## Проблема:
Bundle Identifier `com.messenger.messengerApp` уже занят и не может быть зарегистрирован.

## Решение:
Bundle Identifier изменен на: **`com.uz11ps.messengerapp`**

---

## Что было изменено:

1. **iOS Bundle Identifier:**
   - Старый: `com.messenger.messengerApp`
   - Новый: `com.uz11ps.messengerapp`

2. **iOS Test Target:**
   - Старый: `com.messenger.messengerApp.RunnerTests`
   - Новый: `com.uz11ps.messengerapp.RunnerTests`

---

## Что нужно сделать на Mac:

### 1. Обновите проект:
```bash
cd msngIosAndroidv2
git pull
```

### 2. В Xcode:

1. Откройте проект: `open ios/Runner.xcworkspace`

2. Проверьте Bundle Identifier:
   - Project → Runner → General
   - Убедитесь, что Bundle Identifier: `com.uz11ps.messengerapp`
   - Если не совпадает, измените вручную

3. Проверьте Signing:
   - Project → Runner → Signing & Capabilities
   - Убедитесь, что Team выбрана правильно
   - Если есть ошибки, нажмите "Try Again"

4. Очистите и пересоберите:
   - Product → Clean Build Folder (Shift+Cmd+K)
   - Product → Archive

---

## Альтернатива: Использовать свой уникальный Bundle ID

Если хотите использовать другой Bundle Identifier:

1. В Xcode:
   - Project → Runner → General → Bundle Identifier
   - Измените на что-то уникальное, например:
     - `com.yourname.messengerapp`
     - `com.yourcompany.messengerapp`
     - `com.yourdomain.messengerapp`

2. Формат должен быть:
   - Обратный домен (com.company.appname)
   - Только строчные буквы
   - Без пробелов и специальных символов (кроме точек)

---

## После изменения:

1. Создайте новый Archive
2. Загрузите в App Store Connect
3. Bundle Identifier должен быть успешно зарегистрирован

---

## Важно:

- Bundle Identifier должен быть уникальным во всем App Store
- После первой публикации его нельзя изменить
- Используйте формат обратного домена для избежания конфликтов
