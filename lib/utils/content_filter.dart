import 'package:flutter/foundation.dart';

class ContentFilter {
  // Базовый список неприемлемых слов и фраз (можно расширить)
  static const List<String> _blockedWords = [
    // Оскорбления (примеры - можно расширить)
    // 'word1', 'word2', ...
    // Примечание: В реальном приложении этот список должен быть более полным
    // и может загружаться с сервера для обновления без обновления приложения
  ];

  // Проверяет, содержит ли текст неприемлемые слова
  static bool containsObjectionableContent(String text) {
    if (text.isEmpty) return false;
    
    final lowerText = text.toLowerCase();
    
    // Проверка на базовые блокируемые слова
    for (final word in _blockedWords) {
      if (lowerText.contains(word.toLowerCase())) {
        if (kDebugMode) {
          print('🚫 Content filter: Found blocked word "$word"');
        }
        return true;
      }
    }
    
    // Дополнительные проверки можно добавить здесь:
    // - Проверка на спам-паттерны
    // - Проверка на URL-спам
    // - Проверка на повторяющиеся символы (например, "ааааааа")
    
    return false;
  }

  // Фильтрует текст, заменяя неприемлемые слова на звездочки
  static String filterText(String text) {
    if (text.isEmpty) return text;
    
    String filtered = text;
    for (final word in _blockedWords) {
      final regex = RegExp(word, caseSensitive: false);
      filtered = filtered.replaceAll(regex, '*' * word.length);
    }
    
    return filtered;
  }

  // Проверяет, является ли сообщение спамом (базовая проверка)
  static bool isSpam(String text) {
    if (text.length < 10) return false;
    
    // Проверка на повторяющиеся символы (более 5 подряд)
    if (RegExp(r'(.)\1{5,}').hasMatch(text)) {
      return true;
    }
    
    // Проверка на множественные URL (более 2)
    final urlPattern = RegExp(r'https?://[^\s]+');
    final urls = urlPattern.allMatches(text);
    if (urls.length > 2) {
      return true;
    }
    
    return false;
  }
}
