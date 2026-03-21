#!/bin/bash

# Скрипт для правильной очистки и пересборки iOS проекта

set -e  # Остановить при ошибке

echo "🧹 Начинаем очистку проекта..."

# 1. Очистка Flutter
echo "📦 Очистка Flutter..."
flutter clean

# 2. Получение зависимостей (создаст Generated.xcconfig)
echo "📥 Получение зависимостей Flutter..."
flutter pub get

# 3. Очистка iOS зависимостей
echo "🍎 Очистка iOS зависимостей..."
cd ios
rm -rf Pods Podfile.lock
echo "📦 Установка CocoaPods..."
pod install
cd ..

# 4. Очистка кэша Xcode
echo "🗑️  Очистка кэша Xcode..."
rm -rf ~/Library/Developer/Xcode/DerivedData/*

echo "✅ Очистка завершена!"
echo ""
echo "📱 Следующие шаги:"
echo "1. Запустите эмулятор: open -a Simulator"
echo "2. Подождите полной загрузки эмулятора"
echo "3. Выполните: xcrun simctl uninstall booted com.vvedenskii.messenger"
echo "4. Выполните: xcrun simctl privacy booted reset all"
echo "5. Откройте проект в Xcode: open ios/Runner.xcworkspace"
echo "6. Проверьте настройки Info.plist в Xcode (см. FIX_PERMISSIONS_FINAL.md)"
echo "7. Запустите: flutter run"
