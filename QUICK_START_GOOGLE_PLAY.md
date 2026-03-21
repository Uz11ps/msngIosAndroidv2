# Быстрый старт: Публикация в Google Play

## Шаг 1: Создание аккаунта разработчика

1. Перейдите на https://play.google.com/console
2. Создайте аккаунт разработчика ($25 единоразово)
3. Дождитесь активации (обычно несколько часов)

## Шаг 2: Настройка подписи приложения

### Windows:
```bash
setup_keystore.bat
```

### Linux/Mac:
```bash
chmod +x setup_keystore.sh
./setup_keystore.sh
```

**ВАЖНО:** Сохраните пароли и файл `upload-keystore.jks` в безопасном месте!

## Шаг 3: Обновление build.gradle

Откройте `android/app/build.gradle` и добавьте в начало файла (после `plugins { ... }`):

```gradle
def keystoreProperties = new Properties()
def keystorePropertiesFile = rootProject.file('key.properties')
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(new FileInputStream(keystorePropertiesFile))
}
```

И обновите секцию `android`:

```gradle
android {
    // ... существующий код ...

    signingConfigs {
        release {
            keyAlias keystoreProperties['keyAlias']
            keyPassword keystoreProperties['keyPassword']
            storeFile keystoreProperties['storeFile'] ? file(keystoreProperties['storeFile']) : null
            storePassword keystoreProperties['storePassword']
        }
    }

    buildTypes {
        release {
            signingConfig signingConfigs.release
        }
    }
}
```

## Шаг 4: Сборка App Bundle

```bash
flutter clean
flutter pub get
flutter build appbundle --release
```

Файл будет в: `build/app/outputs/bundle/release/app-release.aab`

## Шаг 5: Подготовка материалов

### Обязательно нужно:
- ✅ Иконка 512x512 пикселей (PNG)
- ✅ Минимум 2 скриншота
- ✅ Feature Graphic 1024x500 пикселей
- ✅ Описание приложения
- ✅ Политика конфиденциальности (используйте `privacy_policy_template.html`)

## Шаг 6: Загрузка в Google Play Console

1. Войдите в https://play.google.com/console
2. Создайте новое приложение
3. Заполните основную информацию
4. Загрузите материалы (иконка, скриншоты, Feature Graphic)
5. Загрузите App Bundle в разделе "Выпуск" → "Production"
6. Заполните "Что нового в этой версии"
7. Заполните политику конфиденциальности
8. Пройдите контентный рейтинг
9. Отправьте на проверку

## Шаг 7: Ожидание

Проверка обычно занимает 1-3 дня. Вы получите email о результате.

## Полезные команды

```bash
# Сборка App Bundle
flutter build appbundle --release

# Сборка APK (для тестирования)
flutter build apk --release

# Проверка версии
cat pubspec.yaml | grep version

# Обновление версии (для следующего релиза)
# Измените version: 1.0.0+1 на version: 1.0.1+2
```

## Чек-лист перед публикацией

- [ ] Аккаунт разработчика создан и оплачен
- [ ] Ключ подписи создан и сохранен
- [ ] build.gradle настроен для подписи
- [ ] App Bundle собран
- [ ] Иконка 512x512 готова
- [ ] Скриншоты готовы (минимум 2)
- [ ] Feature Graphic готов
- [ ] Описание написано
- [ ] Политика конфиденциальности создана и размещена
- [ ] Все разделы в Google Play Console заполнены

## Подробная инструкция

См. `GOOGLE_PLAY_PUBLICATION_GUIDE.md` для детальной информации.
