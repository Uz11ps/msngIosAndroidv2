import 'package:flutter/foundation.dart';

class ContentFilter {
  // Базовый локальный фильтр.
  // Полный набор правил должен поддерживаться на сервере модерации.
  static const List<String> _blockedWords = [
    'hate',
    'nazi',
    'terror',
    'scam',
    'fraud',
    'porn',
    'суицид',
    'террор',
    'насилие',
    'мошен',
    'порн',
  ];

  // Проверяет, содержит ли текст неприемлемые слова
  static bool containsObjectionableContent(String text) {
    if (text.isEmpty) return false;
    
    final lowerText = _normalizeForMatch(text);
    
    // Проверка на базовые блокируемые слова
    for (final word in _blockedWords) {
      if (lowerText.contains(_normalizeForMatch(word))) {
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
      final regex = RegExp(RegExp.escape(word), caseSensitive: false);
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

    // Слишком большое количество одинаковых слов подряд.
    if (RegExp(r'\b(\w+)(\s+\1){4,}\b', caseSensitive: false).hasMatch(text)) {
      return true;
    }
    
    return false;
  }

  static String _normalizeForMatch(String value) {
    return value
        .toLowerCase()
        .replaceAll('0', 'o')
        .replaceAll('1', 'i')
        .replaceAll('3', 'e')
        .replaceAll('4', 'a')
        .replaceAll('5', 's')
        .replaceAll('7', 't')
        .replaceAll('_', '')
        .replaceAll('-', '')
        .replaceAll(' ', '');
  }
}
