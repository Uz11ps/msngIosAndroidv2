import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../config/api_config.dart';
import '../models/user.dart';
import '../models/chat.dart';
import '../models/message.dart';
import 'multipart_uploader.dart';
import 'json_uploader.dart';

class _PlainHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = super.createHttpClient(context);
    client.findProxy = (_) => 'DIRECT';
    client.connectionTimeout = const Duration(seconds: 20);
    client.idleTimeout = const Duration(seconds: 20);
    return client;
  }
}

class ApiService {
  String? _token;
  final Connectivity _connectivity = Connectivity();
  static const int _maxRetries = 3;
  static const int _maxRetriesCellular = 10; // Максимум попыток для мобильных данных (особенно Мегафон)
  static const Duration _retryDelay = Duration(seconds: 2);
  static const Duration _retryDelayCellular = Duration(seconds: 5); // Увеличена задержка для мобильных данных

  void setToken(String? token) {
    _token = token;
  }

  // Публичный метод для проверки типа сети (для UI)
  Future<bool> isCellularNetwork() async {
    return await _isCellularNetwork();
  }

  // Определение типа сети
  Future<bool> _isCellularNetwork() async {
    try {
      final connectivityResult = await _connectivity.checkConnectivity();
      final isCellular = connectivityResult.contains(ConnectivityResult.mobile) ||
                        connectivityResult.contains(ConnectivityResult.other);
      
      if (isCellular) {
        print('📱 Network type: Cellular/Mobile data');
      } else {
        print('📶 Network type: WiFi/Ethernet');
      }
      
      return isCellular;
    } catch (e) {
      print('⚠️ Failed to check network type: $e');
      return false; // По умолчанию считаем WiFi
    }
  }

  // Вспомогательный метод для выполнения запроса с retry
  Future<http.Response> _executeWithRetry(
    Future<http.Response> Function() request, {
    String operation = 'request',
  }) async {
    final isCellular = await _isCellularNetwork();
    final maxRetries = isCellular ? _maxRetriesCellular : _maxRetries;
    final baseDelay = isCellular ? _retryDelayCellular : _retryDelay;
    
    int attempt = 0;
    Exception? lastException;

    while (attempt < maxRetries) {
      try {
        print(
          '🔄 $operation: Attempt ${attempt + 1}/$maxRetries '
          '(${isCellular ? "Cellular" : "WiFi"}) baseUrl=${ApiConfig.baseUrl}',
        );
        // Увеличенный таймаут для мобильных сетей (особенно Мегафон)
        final timeoutDuration = isCellular ? const Duration(seconds: 60) : const Duration(seconds: 30);
        final response = await request().timeout(
          timeoutDuration,
          onTimeout: () {
            throw Exception('Request timeout after ${timeoutDuration.inSeconds}s');
          },
        );
        
        // Если получили ответ (даже с ошибкой), возвращаем его
        if (response.statusCode > 0) {
          if (attempt > 0) {
            print('✅ $operation: Success on retry ${attempt + 1}');
          }
          return response;
        }
      } catch (e) {
        lastException = e is Exception ? e : Exception(e.toString());
        print('⚠️ $operation: Attempt ${attempt + 1} failed: $e');

        // Не повторяем для определенных ошибок
        if (e.toString().contains('FormatException') || 
            e.toString().contains('401') ||
            e.toString().contains('403')) {
          rethrow;
        }
        
        // Для мобильных сетей добавляем дополнительную диагностику
        if (isCellular && attempt == 0) {
          print('📱 Cellular network detected - using extended retry strategy');
          print('📱 HTTPS should work through mobile data');
        }
      }

      attempt++;
      if (attempt < maxRetries) {
        // Экспоненциальная задержка с большим множителем для мобильных данных
        final multiplier = isCellular ? 1.5 : 1.0;
        final delay = Duration(milliseconds: (baseDelay.inMilliseconds * attempt * multiplier).round());
        print('⏳ $operation: Waiting ${delay.inMilliseconds}ms before retry...');
        await Future.delayed(delay);
      }
    }

    if (lastException != null) {
      // Улучшенное сообщение об ошибке
      final errorMsg = lastException.toString();
      if (errorMsg.contains('Failed host lookup') || 
          errorMsg.contains('Network is unreachable') ||
          errorMsg.contains('Connection refused') ||
          errorMsg.contains('Connection timed out')) {
        throw Exception(
          'Не удалось подключиться к серверу. '
          'Проверьте интернет-соединение и убедитесь, что сервер доступен.'
        );
      }
      throw lastException;
    }
    throw Exception('Failed after $maxRetries attempts');
  }

  bool _looksLikeHtml(http.Response response) {
    final ct = (response.headers['content-type'] ?? '').toLowerCase();
    if (ct.contains('text/html')) return true;
    final body = response.body.trimLeft().toLowerCase();
    return body.startsWith('<!doctype') || body.startsWith('<html') || body.startsWith('<meta');
  }

  Future<http.Response> _postJsonWithHttpClient({
    required HttpClient client,
    required Uri uri,
    required Map<String, String> headers,
    required String body,
    required Duration timeout,
  }) async {
    try {
      client.findProxy = (_) => 'DIRECT';
      client.connectionTimeout = timeout;
      client.idleTimeout = timeout;
      final req = await client.postUrl(uri).timeout(timeout);
      headers.forEach((k, v) => req.headers.set(k, v));
      req.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
      req.persistentConnection = false;
      req.add(utf8.encode(body));
      final res = await req.close().timeout(timeout);
      final responseBody = await utf8.decoder.bind(res).join().timeout(timeout);
      final responseHeaders = <String, String>{};
      res.headers.forEach((name, values) {
        responseHeaders[name] = values.join(', ');
      });
      return http.Response(responseBody, res.statusCode, headers: responseHeaders);
    } finally {
      try {
        client.close(force: true);
      } catch (_) {}
    }
  }

  // Auth
  Future<Map<String, dynamic>> emailLogin(String email, String password) async {
    try {
      print('🔐 ========== LOGIN REQUEST ==========');
      print('🔐 Attempting login with email: $email');
      print('🔐 Base URL: ${ApiConfig.baseUrl}');

      final uri = Uri.parse('${ApiConfig.baseUrl}${ApiConfig.emailLogin}');
      final headers = ApiConfig.getHeaders(null);
      final body = jsonEncode({'email': email, 'password': password});
      const perReqTimeout = Duration(seconds: 15);

      http.Response? response;

      // 1) Dedicated direct client (faster fail/timeout than shared global stack).
      try {
        response = await _postJsonWithHttpClient(
          client: HttpClient(),
          uri: uri,
          headers: headers,
          body: body,
          timeout: perReqTimeout,
        );
      } catch (e) {
        print('⚠️ Login direct client failed: $e');
      }

      // 2) Pinned Cloudflare edges as fallback for flaky route/DNS behavior.
      if (response == null) {
        final pinnedIps = <InternetAddress>[
          InternetAddress('172.67.154.188'),
          InternetAddress('104.21.5.195'),
        ];
        for (final ip in pinnedIps) {
          try {
            final hc = JsonUploader.pinnedTlsClient(host: uri.host, ip: ip);
            response = await _postJsonWithHttpClient(
              client: hc,
              uri: uri,
              headers: headers,
              body: body,
              timeout: perReqTimeout,
            );
            break;
          } catch (e) {
            print('⚠️ Login pinned ${ip.address} failed: $e');
          }
        }
      }

      // 3) Last resort: existing retry stack.
      response ??= await _executeWithRetry(
        () => http.post(uri, headers: headers, body: body),
        operation: 'Login',
      );

      print('📡 Response status: ${response.statusCode}');
      print('📡 Response headers: ${response.headers}');
      print('📡 Response body: ${response.body}');

      if (response.statusCode == 0 || response.body.isEmpty) {
        print('❌ Empty response or invalid status code');
        return {
          'success': false,
          'message': 'Сервер не отвечает. Проверьте интернет-соединение.'
        };
      }

      // Защита от прокси/порталов/ошибочных HTML-ответов
      if (_looksLikeHtml(response)) {
        return {
          'success': false,
          'message': 'Сервер вернул некорректный ответ. Проверьте доступность API.'
        };
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      
      // Обрабатываем успешный ответ (200) или ошибку (400)
      if (response.statusCode == 200 && data['success'] == true) {
        _token = data['token'] as String;
        print('✅ Login successful, token saved');
        return {
          'success': true,
          'token': data['token'],
          'user': User.fromJson(data['user'] as Map<String, dynamic>),
        };
      }
      
      // Обрабатываем ошибки (400, 500 и т.д.)
      final errorMessage = data['message'] as String? ?? 'Ошибка входа';
      print('❌ Login failed: $errorMessage (status: ${response.statusCode})');
      return {'success': false, 'message': errorMessage};
    } on FormatException catch (e) {
      print('💥 JSON parsing error: $e');
      return {
        'success': false,
        'message': 'Ошибка обработки ответа сервера.'
      };
    } catch (e, stackTrace) {
      print('💥 Login exception: $e');
      print('💥 Exception type: ${e.runtimeType}');
      print('💥 Stack trace: $stackTrace');
      return {
        'success': false,
        'message': 'Ошибка подключения: ${e.toString()}'
      };
    }
  }

  Future<Map<String, dynamic>> emailRegister(
      String email, String password, String displayName) async {
    try {
      final headers = ApiConfig.getHeaders(null);
      final body = jsonEncode({
        'email': email,
        'password': password,
        'displayName': displayName,
      });

      print('📝 ========== REGISTRATION REQUEST ==========');
      print('📝 Base URL: ${ApiConfig.baseUrl}');
      print('📝 Email: $email');
      print('📝 DisplayName: $displayName');

      final response = await _executeWithRetry(
        () => http.post(
          Uri.parse('${ApiConfig.baseUrl}${ApiConfig.emailRegister}'),
          headers: headers,
          body: body,
        ),
        operation: 'Registration',
      );

      print('📡 ========== REGISTRATION RESPONSE ==========');
      print('📡 Status code: ${response.statusCode}');
      print('📡 Response headers: ${response.headers}');
      print('📡 Response body: ${response.body}');

      if (response.statusCode == 0 || response.body.isEmpty) {
        return {
          'success': false,
          'message': 'Сервер не отвечает. Проверьте интернет-соединение.'
        };
      }

      if (_looksLikeHtml(response)) {
        return {
          'success': false,
          'message': 'Сервер вернул некорректный ответ. Проверьте доступность API.'
        };
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      
      if (response.statusCode == 200 && data['success'] == true) {
        _token = data['token'] as String;
        print('✅ Registration successful, token saved');
        return {
          'success': true,
          'token': data['token'],
          'user': User.fromJson(data['user'] as Map<String, dynamic>),
        };
      }
      
      final errorMessage = data['message'] as String? ?? 'Ошибка регистрации';
      print('❌ Registration failed: $errorMessage (status: ${response.statusCode})');
      return {
        'success': false,
        'message': errorMessage
      };
    } on http.ClientException catch (e) {
      print('💥 ========== REGISTRATION NETWORK ERROR ==========');
      print('💥 Error: $e');
      print('💥 Error type: ${e.runtimeType}');
      print('💥 Message: ${e.message}');
      final isCellular = await _isCellularNetwork();
      final errorMsg = e.toString();
      
      if (errorMsg.contains('Failed host lookup') || errorMsg.contains('Network is unreachable')) {
        return {
          'success': false,
          'message': 'Нет подключения к интернету. Проверьте настройки сети.'
        };
      }
      
      return {
        'success': false,
        'message': 'Ошибка сети: ${e.message}. Проверьте интернет-соединение.'
      };
    } on FormatException catch (e) {
      print('💥 ========== REGISTRATION JSON PARSING ERROR ==========');
      print('💥 Error: $e');
      return {
        'success': false,
        'message': 'Ошибка обработки ответа сервера.'
      };
    } catch (e, stackTrace) {
      print('💥 ========== REGISTRATION EXCEPTION ==========');
      print('💥 Error: $e');
      print('💥 Error type: ${e.runtimeType}');
      print('💥 Stack trace: $stackTrace');
      final errorMsg = e.toString();
      final isCellular = await _isCellularNetwork();
      
      if (errorMsg.contains('Failed host lookup') || errorMsg.contains('Network is unreachable')) {
        return {
          'success': false,
          'message': 'Нет подключения к интернету. Проверьте настройки сети.'
        };
      }
      
      // Проверяем ошибки подключения
      if (errorMsg.contains('Connection refused') || 
          errorMsg.contains('Connection reset') ||
          errorMsg.contains('SocketException') ||
          errorMsg.contains('Failed host lookup') ||
          errorMsg.contains('Network is unreachable')) {
        return {
          'success': false,
          'message': 'Не удалось подключиться к серверу.\n\n'
                     'Проверьте интернет-соединение и убедитесь, что сервер доступен.'
        };
      }
      
      // Проверяем ошибки подключения
      if (errorMsg.contains('Connection refused') || 
          errorMsg.contains('Connection reset') ||
          errorMsg.contains('SocketException') ||
          errorMsg.contains('Failed host lookup') ||
          errorMsg.contains('Network is unreachable')) {
        return {
          'success': false,
          'message': 'Не удалось подключиться к серверу.\n\n'
                     'Проверьте интернет-соединение и убедитесь, что сервер доступен.'
        };
      }
      
      return {
        'success': false,
        'message': 'Ошибка регистрации: ${e.toString()}'
      };
    }
  }

  Future<Map<String, dynamic>> sendOtp(String phoneNumber) async {
    try {
      print('📱 Sending OTP to: $phoneNumber');
      final headers = ApiConfig.getHeaders(null);

      final response = await _executeWithRetry(
        () => http.post(
          Uri.parse('${ApiConfig.baseUrl}${ApiConfig.sendOtp}'),
          headers: headers,
          body: jsonEncode({'phoneNumber': phoneNumber}),
        ),
        operation: 'Send OTP',
      );

      print('📡 Send OTP response status: ${response.statusCode}');
      print('📡 Send OTP response body: ${response.body}');

      if (response.statusCode == 0 || response.body.isEmpty) {
        return {
          'success': false,
          'message': 'Сервер не отвечает. Проверьте интернет-соединение.'
        };
      }

      if (_looksLikeHtml(response)) {
        return {
          'success': false,
          'message': 'Сервер вернул некорректный ответ. Проверьте доступность API.'
        };
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return {
        'success': data['success'] ?? false,
        'message': data['message'] ?? '',
      };
    } on http.ClientException catch (e) {
      print('💥 Send OTP network error: $e');
      return {
        'success': false,
        'message': 'Ошибка сети: ${e.message}. Проверьте интернет-соединение.'
      };
    } catch (e) {
      print('💥 Send OTP exception: $e');
      return {
        'success': false,
        'message': 'Ошибка отправки SMS: ${e.toString()}'
      };
    }
  }

  Future<Map<String, dynamic>> verifyOtp(
      String phoneNumber, String code, String? displayName) async {
    try {
      print('🔐 Verifying OTP for: $phoneNumber');
      final headers = ApiConfig.getHeaders(null);

      final response = await _executeWithRetry(
        () => http.post(
          Uri.parse('${ApiConfig.baseUrl}${ApiConfig.verifyOtp}'),
          headers: headers,
          body: jsonEncode({
            'phoneNumber': phoneNumber,
            'code': code,
            if (displayName != null) 'displayName': displayName,
          }),
        ),
        operation: 'Verify OTP',
      );

      print('📡 Verify OTP response status: ${response.statusCode}');
      print('📡 Verify OTP response body: ${response.body}');

      if (response.statusCode == 0 || response.body.isEmpty) {
        return {
          'success': false,
          'message': 'Сервер не отвечает. Проверьте интернет-соединение.'
        };
      }

      if (_looksLikeHtml(response)) {
        return {
          'success': false,
          'message': 'Сервер вернул некорректный ответ. Проверьте доступность API.'
        };
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode == 200 && data['success'] == true) {
        _token = data['token'] as String;
        return {
          'success': true,
          'token': data['token'],
          'user': User.fromJson(data['user'] as Map<String, dynamic>),
        };
      }
      return {'success': false, 'message': data['message'] ?? 'Неверный код'};
    } on http.ClientException catch (e) {
      print('💥 Verify OTP network error: $e');
      return {
        'success': false,
        'message': 'Ошибка сети: ${e.message}. Проверьте интернет-соединение.'
      };
    } catch (e) {
      print('💥 Verify OTP exception: $e');
      return {
        'success': false,
        'message': 'Ошибка проверки кода: ${e.toString()}'
      };
    }
  }

  // Users
  Future<List<User>> searchUsers(String query) async {
    try {
      final response = await http.get(
        Uri.parse('${ApiConfig.baseUrl}${ApiConfig.searchUsers}?q=$query'),
        headers: ApiConfig.getHeaders(_token),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data is List) {
          return data.map((json) => User.fromJson(json)).toList();
        }
      }
    } catch (e) {
      print('Error searching users: $e');
    }
    return [];
  }

  Future<User?> getUser(String userId) async {
    try {
      print('📡 Requesting user info: $userId');
      print('📡 Token present: ${_token != null && _token!.isNotEmpty}');
      
      final url = '${ApiConfig.baseUrl}${ApiConfig.getUser}/$userId';
      print('📡 URL: $url');
      
      final response = await http.get(
        Uri.parse(url),
        headers: ApiConfig.getHeaders(_token),
      );

      print('📡 Response status: ${response.statusCode}');
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        print('📡 User data: $data');
        final user = User.fromJson(data);
        print('✅ User parsed: ${user.displayName ?? user.email ?? user.phoneNumber}');
        return user;
      } else {
        print('❌ Failed to get user: ${response.statusCode}');
        print('❌ Response body: ${response.body}');
      }
    } catch (e, stackTrace) {
      print('❌ Error getting user: $e');
      print('❌ Stack trace: $stackTrace');
    }
    return null;
  }

  Future<bool> updateUser({
    required String id,
    String? displayName,
    String? status,
    String? photoUrl,
  }) async {
    final response = await http.post(
      Uri.parse('${ApiConfig.baseUrl}${ApiConfig.updateUser}'),
      headers: ApiConfig.getHeaders(_token),
      body: jsonEncode({
        'id': id,
        if (displayName != null) 'displayName': displayName,
        if (status != null) 'status': status,
        if (photoUrl != null) 'photoUrl': photoUrl,
      }),
    );

    return response.statusCode == 200;
  }

  Future<bool> linkEmail(String email, String password) async {
    final response = await http.post(
      Uri.parse('${ApiConfig.baseUrl}${ApiConfig.linkEmail}'),
      headers: ApiConfig.getHeaders(_token),
      body: jsonEncode({'email': email, 'password': password}),
    );

    return response.statusCode == 200;
  }

  Future<bool> linkPhone(String phoneNumber, String code) async {
    final response = await http.post(
      Uri.parse('${ApiConfig.baseUrl}${ApiConfig.linkPhone}'),
      headers: ApiConfig.getHeaders(_token),
      body: jsonEncode({'phoneNumber': phoneNumber, 'code': code}),
    );

    return response.statusCode == 200;
  }

  Future<bool> updateFcmToken(String userId, String fcmToken) async {
    final response = await http.post(
      Uri.parse('${ApiConfig.baseUrl}${ApiConfig.updateFcmToken}'),
      headers: ApiConfig.getHeaders(_token),
      body: jsonEncode({'id': userId, 'fcmToken': fcmToken}),
    );

    return response.statusCode == 200;
  }

  // Block user
  Future<Map<String, dynamic>> blockUser(String userId) async {
    try {
      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}${ApiConfig.blockUser}'),
        headers: ApiConfig.getHeaders(_token),
        body: jsonEncode({'userId': userId}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return {
          'success': data['success'] ?? true,
          'message': data['message'] ?? 'Пользователь заблокирован',
        };
      }
      return {
        'success': false,
        'message': 'Ошибка блокировки пользователя',
      };
    } catch (e) {
      print('Error blocking user: $e');
      return {
        'success': false,
        'message': 'Ошибка блокировки: ${e.toString()}',
      };
    }
  }

  // Report user or message
  Future<Map<String, dynamic>> reportUser({
    required String userId,
    required String reason,
    String? details,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}${ApiConfig.reportUser}'),
        headers: ApiConfig.getHeaders(_token),
        body: jsonEncode({
          'userId': userId,
          'reason': reason,
          if (details != null) 'details': details,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return {
          'success': data['success'] ?? true,
          'message': data['message'] ?? 'Жалоба отправлена',
        };
      }
      return {
        'success': false,
        'message': 'Ошибка отправки жалобы',
      };
    } catch (e) {
      print('Error reporting user: $e');
      return {
        'success': false,
        'message': 'Ошибка отправки жалобы: ${e.toString()}',
      };
    }
  }

  Future<Map<String, dynamic>> reportMessage({
    required String messageId,
    required String chatId,
    required String reason,
    String? details,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}${ApiConfig.reportMessage}'),
        headers: ApiConfig.getHeaders(_token),
        body: jsonEncode({
          'messageId': messageId,
          'chatId': chatId,
          'reason': reason,
          if (details != null) 'details': details,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return {
          'success': data['success'] ?? true,
          'message': data['message'] ?? 'Жалоба отправлена',
        };
      }
      return {
        'success': false,
        'message': 'Ошибка отправки жалобы',
      };
    } catch (e) {
      print('Error reporting message: $e');
      return {
        'success': false,
        'message': 'Ошибка отправки жалобы: ${e.toString()}',
      };
    }
  }

  // Chats
  Future<Chat?> createChat(List<String> participants) async {
    final response = await http.post(
      Uri.parse('${ApiConfig.baseUrl}${ApiConfig.createChat}'),
      headers: ApiConfig.getHeaders(_token),
      body: jsonEncode({'participants': participants}),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return Chat.fromJson(data);
    }
    return null;
  }

  Future<Chat?> createGroupChat(
      List<String> participants, String groupName, String adminId) async {
    final response = await http.post(
      Uri.parse('${ApiConfig.baseUrl}${ApiConfig.createGroupChat}'),
      headers: ApiConfig.getHeaders(_token),
      body: jsonEncode({
        'participants': participants,
        'groupName': groupName,
        'adminId': adminId,
      }),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return Chat.fromJson(data);
    }
    return null;
  }

  Future<List<Chat>> getChats() async {
    try {
      final response = await http.get(
        Uri.parse('${ApiConfig.baseUrl}${ApiConfig.getChats}'),
        headers: ApiConfig.getHeaders(_token),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data is List) {
          return data.map((json) => Chat.fromJson(json)).toList();
        }
      }
    } catch (e) {
      print('Error loading chats: $e');
    }
    return [];
  }

  Future<List<Message>> getChatMessages(String chatId) async {
    try {
      print('📡 Requesting messages for chat: $chatId');
      final response = await http.get(
        Uri.parse(
            '${ApiConfig.baseUrl}${ApiConfig.getChatMessages}/$chatId/messages'),
        headers: ApiConfig.getHeaders(_token),
      );

      print('📡 Response status: ${response.statusCode}');
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data is List) {
          final messages = data.map((json) => Message.fromJson(json)).toList();
          print('📡 Parsed ${messages.length} messages');
          return messages;
        }
      } else {
        print('❌ Failed to load messages: ${response.statusCode}');
        print('❌ Response body: ${response.body}');
      }
    } catch (e, stackTrace) {
      print('💥 Error loading messages: $e');
      print('💥 Stack trace: $stackTrace');
    }
    return [];
  }

  Future<bool> addParticipant(String chatId, String userId) async {
    final response = await http.post(
      Uri.parse(
          '${ApiConfig.baseUrl}${ApiConfig.addParticipant}/$chatId/add-participant'),
      headers: ApiConfig.getHeaders(_token),
      body: jsonEncode({'userId': userId}),
    );

    return response.statusCode == 200;
  }

  Future<bool> removeParticipant(String chatId, String userId) async {
    final response = await http.post(
      Uri.parse(
          '${ApiConfig.baseUrl}${ApiConfig.removeParticipant}/$chatId/remove-participant'),
      headers: ApiConfig.getHeaders(_token),
      body: jsonEncode({'userId': userId}),
    );

    return response.statusCode == 200;
  }

  Future<bool> deleteChat(String chatId) async {
    final response = await http.delete(
      Uri.parse('${ApiConfig.baseUrl}${ApiConfig.deleteChat}/$chatId'),
      headers: ApiConfig.getHeaders(_token),
    );

    return response.statusCode == 200;
  }

  Future<bool> deleteMessage(String chatId, String messageId) async {
    final response = await http.delete(
      Uri.parse(
          '${ApiConfig.baseUrl}${ApiConfig.deleteMessage}/$chatId/messages/$messageId'),
      headers: ApiConfig.getHeaders(_token),
    );

    return response.statusCode == 200;
  }

  Future<bool> updateGroupChat({
    required String chatId,
    String? groupName,
    String? groupPhotoUrl,
  }) async {
    try {
      final body = <String, dynamic>{};
      if (groupName != null) body['groupName'] = groupName;
      if (groupPhotoUrl != null) body['groupPhotoUrl'] = groupPhotoUrl;

      final response = await http.put(
        Uri.parse('${ApiConfig.baseUrl}${ApiConfig.updateGroupChat}/$chatId/group'),
        headers: ApiConfig.getHeaders(_token),
        body: jsonEncode(body),
      );

      return response.statusCode == 200;
    } catch (e) {
      print('Error updating group: $e');
      return false;
    }
  }

  HttpClient _newUploadHttpClient() {
    final hc = HttpClient();
    hc.findProxy = (_) => 'DIRECT';
    hc.maxConnectionsPerHost = 1;
    hc.connectionTimeout = const Duration(seconds: 20);
    hc.idleTimeout = const Duration(seconds: 20);
    return hc;
  }

  // Upload
  Future<String?> uploadFile(String filePath) async {
    // Prefer base64 JSON on iOS because multipart can hang on some network paths.
    if (!kIsWeb && Platform.isIOS) {
      final url = await _uploadFileBase64(filePath);
      if (url != null) return url;
    }

    final uri = Uri.parse('${ApiConfig.baseUrl}${ApiConfig.uploadFile}');
    final headers = ApiConfig.getMultipartHeaders(_token);

    Future<String?> attempt(String label, HttpClient httpClient) async {
      try {
        final response = await MultipartUploader.uploadFile(
          httpClient: httpClient,
          uri: uri,
          filePath: filePath,
          headers: headers,
          timeout: const Duration(seconds: 25),
        );

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          final url = data['url'] as String?;
          print('📤 File uploaded ($label): $url');
          return url;
        }
        final prefix = response.body.length > 200 ? response.body.substring(0, 200) : response.body;
        print('❌ Upload failed ($label): ${response.statusCode} body="$prefix"');
        return null;
      } on TimeoutException catch (e) {
        print('⏱️ Upload timeout ($label): $e');
        return null;
      } catch (e) {
        print('💥 Upload exception ($label): $e');
        return null;
      } finally {
        try {
          httpClient.close(force: true);
        } catch (_) {}
      }
    }

    // Attempt 1: normal client (uses global HttpOverrides, DoH+edge fallback).
    final url1 = await attempt('overrides', _newUploadHttpClient());
    if (url1 != null) return url1;

    // Attempt 2: bypass overrides (system DNS / default TLS). This helps when an edge IP
    // selected by DoH is flaky for large POST bodies.
    final url2 = await HttpOverrides.runZoned(
      () async => await attempt('system_dns', _newUploadHttpClient()),
      createHttpClient: _PlainHttpOverrides().createHttpClient,
    );
    if (url2 != null) return url2;

    // Attempt 3: JSON base64 fallback (requires backend /api/upload-base64).
    // This avoids multipart parsing issues on some iOS network paths.
    return await _uploadFileBase64(filePath);
  }

  Future<String?> _uploadFileBase64(String filePath) async {
    try {
      if (_token == null || _token!.isEmpty) {
        print('❌ Upload(base64): missing token');
        return null;
      }
      final file = File(filePath);
      final fileLen = await file.length();
      // Avoid blowing up payloads unexpectedly.
      if (fileLen > 8 * 1024 * 1024) {
        print('❌ Upload(base64): file too large ($fileLen bytes)');
        return null;
      }
      final filename = file.uri.pathSegments.isNotEmpty ? file.uri.pathSegments.last : 'file.bin';

      final uri = Uri.parse('${ApiConfig.baseUrl}${ApiConfig.uploadFileBase64}');
      print('📤 Upload(base64): POST $uri bytes=$fileLen');
      final headers = ApiConfig.getHeaders(_token);
      
      // Prefer chunked JSON first on iOS for non-trivial payloads: avoids long "hanging" POST close on some networks.
      if (!kIsWeb && Platform.isIOS && fileLen > 32 * 1024) {
        try {
          print('📤 Upload(base64 chunks): start fileLen=$fileLen chunkBytes=8192');
          final chunkUrl = await JsonUploader.uploadFileBase64Chunked(
            baseUri: Uri.parse(ApiConfig.baseUrl),
            token: _token!,
            filePath: filePath,
            chunkBytes: 8192,
            timeoutPerReq: const Duration(seconds: 20),
          );
          if (chunkUrl != null) {
            print('📤 File uploaded (base64 chunks): $chunkUrl');
            return chunkUrl;
          }
        } catch (e) {
          print('💥 Upload(base64 chunks) exception: $e');
        }
      }

      final bytes = await file.readAsBytes();
      final payload = <String, dynamic>{
        'filename': filename,
        'dataBase64': base64Encode(bytes),
      };

      final pinnedIps = <InternetAddress>[
        InternetAddress('172.67.154.188'),
        InternetAddress('104.21.5.195'),
      ];
      for (final ip in pinnedIps) {
        final hc = JsonUploader.pinnedTlsClient(host: uri.host, ip: ip);
        try {
          print('📤 Upload(base64): trying pinned edge ${ip.address}');
          final res = await JsonUploader.postJson(
            httpClient: hc,
            uri: uri,
            headers: headers,
            bodyJson: payload,
            timeout: const Duration(seconds: 12),
          );
          if (res.statusCode == 200) {
            final data = jsonDecode(res.body) as Map<String, dynamic>;
            final url = data['url'] as String?;
            print('📤 File uploaded (base64): $url');
            return url;
          }
          final prefix = res.body.length > 200 ? res.body.substring(0, 200) : res.body;
          print('❌ Upload(base64) failed pinned ${ip.address}: ${res.statusCode} body="$prefix"');
        } catch (e) {
          print('💥 Upload(base64) exception pinned ${ip.address}: $e');
        } finally {
          try {
            hc.close(force: true);
          } catch (_) {}
        }
      }

      // Last resort: default client (uses global HttpOverrides).
      final res = await http
          .post(uri, headers: headers, body: jsonEncode(payload))
          .timeout(const Duration(seconds: 12));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final url = data['url'] as String?;
        print('📤 File uploaded (base64): $url');
        return url;
      }
      final prefix = res.body.length > 200 ? res.body.substring(0, 200) : res.body;
      print('❌ Upload(base64) failed: ${res.statusCode} body="$prefix"');
      // Attempt: chunked base64 upload (many small JSON requests).
      try {
        print('📤 Upload(base64 chunks): start fileLen=$fileLen chunkBytes=8192');
        final chunkUrl = await JsonUploader.uploadFileBase64Chunked(
          baseUri: Uri.parse(ApiConfig.baseUrl),
          token: _token!,
          filePath: filePath,
          chunkBytes: 8192,
          timeoutPerReq: const Duration(seconds: 20),
        );
        if (chunkUrl != null) {
          print('📤 File uploaded (base64 chunks): $chunkUrl');
          return chunkUrl;
        }
      } catch (e) {
        print('💥 Upload(base64 chunks) exception: $e');
      }
      return null;
    } catch (e) {
      print('💥 Upload(base64) exception: $e');
      return null;
    }
  }
}
