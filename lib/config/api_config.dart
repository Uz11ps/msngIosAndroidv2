import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';

class ApiConfig {
  // Primary URL (Cloudflare). This should work for most networks.
  static const String primaryBaseUrl = 'https://api.milviar.ru';

  // NOTE: A direct IP fallback over cleartext HTTP is NOT used automatically,
  // because some carrier networks inject DPI portals into HTTP (as HTML), which
  // breaks the API and is insecure.
  //
  // Keep this for manual diagnostics only.
  static const String fallbackIpHttpBaseUrl = 'http://83.166.246.225:8080';

  static const List<String> baseUrlCandidates = <String>[
    primaryBaseUrl,
  ];

  static const String _prefsKeyBaseUrl = 'api_base_url';
  static String _currentBaseUrl = primaryBaseUrl;
  static int _lastSwitchMs = 0;

  static String get baseUrl => _currentBaseUrl;
  static String get wsUrl => _currentBaseUrl; // socket.io is served by the same backend

  static bool get isUsingFallback => _currentBaseUrl != primaryBaseUrl;

  static Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_prefsKeyBaseUrl);
      if (saved != null && baseUrlCandidates.contains(saved)) {
        _currentBaseUrl = saved;
      } else {
        _currentBaseUrl = primaryBaseUrl;
      }
      print('🌐 ApiConfig: current baseUrl = $_currentBaseUrl');
    } catch (e) {
      // Non-fatal: keep default.
      _currentBaseUrl = primaryBaseUrl;
      print('⚠️ ApiConfig.init failed, using default: $e');
    }
  }

  static Future<void> setBaseUrl(String url, {String reason = 'manual'}) async {
    if (!baseUrlCandidates.contains(url)) return;
    _currentBaseUrl = url;
    print('🌐 ApiConfig: switched baseUrl to $_currentBaseUrl (reason=$reason)');
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKeyBaseUrl, _currentBaseUrl);
    } catch (_) {}
  }

  static Future<String> rotateToNextBaseUrl({String reason = 'auto'}) async {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    // Throttle endpoint switches to avoid oscillations.
    if (nowMs - _lastSwitchMs < 10 * 1000) {
      return _currentBaseUrl;
    }
    _lastSwitchMs = nowMs;

    final idx = baseUrlCandidates.indexOf(_currentBaseUrl);
    final nextIdx = idx >= 0 ? (idx + 1) % baseUrlCandidates.length : 0;
    final next = baseUrlCandidates[nextIdx];
    await setBaseUrl(next, reason: reason);
    return next;
  }

  static Future<void> resetToPrimary({String reason = 'reset'}) async {
    await setBaseUrl(primaryBaseUrl, reason: reason);
  }
  
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
  static const String blockUser = '/api/users/block';
  static const String reportUser = '/api/users/report';
  static const String reportMessage = '/api/messages/report';
  
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
  static const String uploadFileBase64 = '/api/upload-base64';
  static const String uploadChunksInit = '/api/upload-chunks/init';
  static const String uploadChunksPart = '/api/upload-chunks/part';
  static const String uploadChunksComplete = '/api/upload-chunks/complete';
  
  // Полный URL для загрузок
  static String getUploadUrl(String? path) {
    if (path == null || path.isEmpty) return '';
    final currentUrl = baseUrl;
    // Do not force direct HTTP IP for media URLs: some carrier paths inject HTML
    // into cleartext HTTP, which produces invalid image bytes on iOS.
    final mediaBase = currentUrl;

    // Prefer fetching media through /api/media/* instead of /uploads/*.
    // Some networks hang specifically on /uploads while /api works.
    String filename;
    if (path.startsWith('http://') || path.startsWith('https://')) {
      try {
        final u = Uri.parse(path);
        // Rewrite absolute URLs pointing to `/uploads/*` to the API media endpoint.
        if (u.path.startsWith('/uploads/')) {
          filename = u.path.split('/').last;
          return '$mediaBase/api/media/$filename';
        }
      } catch (_) {}
      return path;
    }
    if (path.startsWith('/uploads/')) {
      filename = path.split('/').last;
    } else if (path.startsWith('/api/media/')) {
      return '$mediaBase$path';
    } else if (path.startsWith('/')) {
      // Unknown absolute path: keep old behavior.
      return '$currentUrl$path';
    } else {
      filename = path.split('/').last;
    }
    return '$mediaBase/api/media/$filename';
  }
  
  // Headers
  static Map<String, String> getHeaders(String? token) {
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      'User-Agent': 'MessengerApp/1.0.0 (iOS)',
      'Connection': 'keep-alive',
    };
    if (token != null) {
      headers['Authorization'] = 'Bearer $token';
    }
    return headers;
  }

  // Multipart/form-data uploads must NOT set Content-Type manually (boundary is required).
  static Map<String, String> getMultipartHeaders(String? token) {
    final headers = <String, String>{
      'Accept': 'application/json',
      'User-Agent': 'MessengerApp/1.0.0 (iOS)',
      'Connection': 'keep-alive',
    };
    if (token != null) {
      headers['Authorization'] = 'Bearer $token';
    }
    return headers;
  }
}
