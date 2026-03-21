@echo off
REM Скрипт для настройки подписи приложения для Google Play (Windows)

echo 🔐 Настройка подписи приложения для Google Play
echo.

REM Проверка наличия keytool
where keytool >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    echo ❌ Ошибка: keytool не найден!
    echo Установите Java JDK для использования keytool
    pause
    exit /b 1
)

REM Переход в директорию android
cd android
if %ERRORLEVEL% NEQ 0 (
    echo ❌ Ошибка: директория android не найдена!
    pause
    exit /b 1
)

REM Проверка существования ключа
if exist "upload-keystore.jks" (
    echo ⚠️  Ключ уже существует!
    set /p OVERWRITE="Перезаписать существующий ключ? (y/n): "
    if /i not "%OVERWRITE%"=="y" (
        echo Отмена.
        pause
        exit /b 0
    )
    del /f upload-keystore.jks
)

echo 📝 Создание нового ключа подписи...
echo.
echo Введите следующие данные:
echo.

REM Запрос данных
set /p STORE_PASSWORD="Пароль для хранилища ключей: "
set /p STORE_PASSWORD_CONFIRM="Повторите пароль: "

if not "%STORE_PASSWORD%"=="%STORE_PASSWORD_CONFIRM%" (
    echo ❌ Пароли не совпадают!
    pause
    exit /b 1
)

set /p KEY_PASSWORD="Пароль для ключа (можно использовать тот же): "
set /p NAME="Ваше имя и фамилия: "
set /p ORGANIZATION="Название организации: "
set /p CITY="Город: "
set /p REGION="Регион/Область: "
set /p COUNTRY_CODE="Код страны (2 буквы, например RU): "

echo.
echo Создание ключа...

REM Создание ключа
keytool -genkey -v -keystore upload-keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload -storepass "%STORE_PASSWORD%" -keypass "%KEY_PASSWORD%" -dname "CN=%NAME%, OU=%ORGANIZATION%, O=%ORGANIZATION%, L=%CITY%, ST=%REGION%, C=%COUNTRY_CODE%"

if %ERRORLEVEL% EQU 0 (
    echo ✅ Ключ успешно создан!
    
    REM Создание key.properties
    echo 📝 Создание файла key.properties...
    
    (
        echo storePassword=%STORE_PASSWORD%
        echo keyPassword=%KEY_PASSWORD%
        echo keyAlias=upload
        echo storeFile=upload-keystore.jks
    ) > key.properties
    
    echo ✅ Файл key.properties создан!
    echo.
    echo ⚠️  ВАЖНО:
    echo 1. Сохраните пароли в безопасном месте!
    echo 2. Добавьте key.properties в .gitignore!
    echo 3. Сохраните upload-keystore.jks в безопасном месте!
    echo.
    echo Без этого ключа вы не сможете обновлять приложение в Google Play!
    
) else (
    echo ❌ Ошибка при создании ключа!
    pause
    exit /b 1
)

pause
