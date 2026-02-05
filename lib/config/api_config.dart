class ApiConfig {
  // Базовый URL сервера
  static const String baseUrl = 'http://83.166.246.225:3000';
  static const String wsUrl = 'http://83.166.246.225:3000';
  
  // API эндпоинты
  static const String emailLogin = '/api/auth/email-login';
  static const String emailRegister = '/api/auth/email-register';
  static const String sendOtp = '/api/auth/send-otp';
  static const String verifyOtp = '/api/auth/verify-otp';
  
  static const String updateFcmToken = '/api/users/fcm-token';
  static const String updateUser = '/api/users/update';
  static const String linkEmail = '/api/users/link-email';
  static const String linkPhone = '/api/users/link-phone';
  static const String searchUsers = '/api/users/search';
  static const String getUser = '/api/users';
  
  static const String createChat = '/api/chats/create';
  static const String createGroupChat = '/api/chats/group';
  static const String getChats = '/api/chats';
  static const String getChatMessages = '/api/chats';
  static const String addParticipant = '/api/chats';
  static const String removeParticipant = '/api/chats';
  static const String updateGroupChat = '/api/chats';
  static const String deleteChat = '/api/chats';
  static const String deleteMessage = '/api/chats';
  
  static const String uploadFile = '/api/upload';
  
  // Полный URL для загрузок
  static String getUploadUrl(String? path) {
    if (path == null || path.isEmpty) return '';
    if (path.startsWith('http://') || path.startsWith('https://')) return path;
    if (path.startsWith('/')) return '$baseUrl$path';
    return '$baseUrl/uploads/$path';
  }
  
  // Headers
  static Map<String, String> getHeaders(String? token) {
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };
    if (token != null) {
      headers['Authorization'] = 'Bearer $token';
    }
    return headers;
  }
}
