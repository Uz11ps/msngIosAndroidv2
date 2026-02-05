class AgoraConfig {
  // Agora App ID
  static const String appId = '9f3bf11c90364991926390fae2a67c92';
  
  // Для production рекомендуется использовать токены
  // Для тестирования можно использовать временный токен или null
  static String? getToken(String channelName, int uid) {
    // TODO: Генерировать токен на бекенде для безопасности
    return null; // null для тестирования без токена
  }
}
