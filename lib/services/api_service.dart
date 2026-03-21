import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';
import '../models/user.dart';
import '../models/chat.dart';
import '../models/message.dart';

class ApiService {
  String? _token;

  void setToken(String? token) {
    _token = token;
  }

  // Auth
  Future<Map<String, dynamic>> emailLogin(String email, String password) async {
    try {
      print('🔐 Attempting login with email: $email');
      print('🌐 API URL: ${ApiConfig.baseUrl}${ApiConfig.emailLogin}');
      
      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}${ApiConfig.emailLogin}'),
        headers: ApiConfig.getHeaders(null),
        body: jsonEncode({'email': email, 'password': password}),
      ).timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          throw Exception('Превышено время ожидания ответа от сервера. Проверьте интернет-соединение.');
        },
      );

      print('📡 Response status: ${response.statusCode}');
      print('📡 Response headers: ${response.headers}');
      print('📡 Response body length: ${response.body.length}');
      print('📡 Response body: ${response.body.substring(0, response.body.length > 500 ? 500 : response.body.length)}');

      // Проверяем Content-Type
      final contentType = response.headers['content-type'] ?? '';
      if (!contentType.contains('application/json')) {
        print('❌ Server returned non-JSON. Content-Type: $contentType');
        return {
          'success': false,
          'message': 'Сервер вернул неверный формат данных. Возможно, сервер недоступен или эндпоинт изменился.',
          'debug': 'Content-Type: $contentType, Status: ${response.statusCode}',
        };
      }

      // Проверяем формат ответа
      final trimmedBody = response.body.trim();
      if (trimmedBody.isEmpty) {
        return {
          'success': false,
          'message': 'Сервер вернул пустой ответ. Проверьте доступность сервера.',
        };
      }

      if (!trimmedBody.startsWith('{') && !trimmedBody.startsWith('[')) {
        print('❌ Response is not JSON. First 200 chars: ${trimmedBody.substring(0, trimmedBody.length > 200 ? 200 : trimmedBody.length)}');
        return {
          'success': false,
          'message': 'Сервер вернул HTML вместо JSON. Возможно, сервер недоступен или URL неверный.',
          'debug': 'Response starts with: ${trimmedBody.substring(0, 50)}',
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
      return {
        'success': false,
        'message': errorMessage,
        'statusCode': response.statusCode,
      };
    } on http.ClientException catch (e) {
      print('💥 Network error: $e');
      return {
        'success': false,
        'message': 'Ошибка сети: ${e.message}. Проверьте интернет-соединение и доступность сервера.',
        'error': e.toString(),
      };
    } on FormatException catch (e) {
      print('💥 Format error: $e');
      return {
        'success': false,
        'message': 'Сервер вернул неверный формат данных. Возможно, сервер недоступен.',
        'error': e.toString(),
      };
    } on Exception catch (e) {
      print('💥 Exception: $e');
      return {
        'success': false,
        'message': e.toString(),
        'error': e.toString(),
      };
    } catch (e, stackTrace) {
      print('💥 Unknown error: $e');
      print('💥 Stack trace: $stackTrace');
      return {
        'success': false,
        'message': 'Неизвестная ошибка: $e. Проверьте интернет-соединение и попробуйте позже.',
        'error': e.toString(),
      };
    }
  }

  Future<Map<String, dynamic>> emailRegister(
      String email, String password, String displayName) async {
    try {
      print('🔐 Attempting registration with email: $email');
      print('🌐 API URL: ${ApiConfig.baseUrl}${ApiConfig.emailRegister}');
      
      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}${ApiConfig.emailRegister}'),
        headers: ApiConfig.getHeaders(null),
        body: jsonEncode({
          'email': email,
          'password': password,
          'displayName': displayName,
        }),
      ).timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          throw Exception('Превышено время ожидания ответа от сервера. Проверьте интернет-соединение.');
        },
      );

      print('📡 Response status: ${response.statusCode}');
      print('📡 Response headers: ${response.headers}');
      print('📡 Response body length: ${response.body.length}');
      print('📡 Response body: ${response.body.substring(0, response.body.length > 500 ? 500 : response.body.length)}');

      // Проверяем Content-Type
      final contentType = response.headers['content-type'] ?? '';
      if (!contentType.contains('application/json')) {
        print('❌ Server returned non-JSON. Content-Type: $contentType');
        return {
          'success': false,
          'message': 'Сервер вернул неверный формат данных. Возможно, сервер недоступен или эндпоинт изменился.',
          'debug': 'Content-Type: $contentType, Status: ${response.statusCode}',
        };
      }

      // Проверяем формат ответа
      final trimmedBody = response.body.trim();
      if (trimmedBody.isEmpty) {
        return {
          'success': false,
          'message': 'Сервер вернул пустой ответ. Проверьте доступность сервера.',
        };
      }

      if (!trimmedBody.startsWith('{') && !trimmedBody.startsWith('[')) {
        print('❌ Response is not JSON. First 200 chars: ${trimmedBody.substring(0, trimmedBody.length > 200 ? 200 : trimmedBody.length)}');
        return {
          'success': false,
          'message': 'Сервер вернул HTML вместо JSON. Возможно, сервер недоступен или URL неверный.',
          'debug': 'Response starts with: ${trimmedBody.substring(0, 50)}',
        };
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      
      // Обрабатываем успешный ответ (200) или ошибку (400)
      if (response.statusCode == 200 && data['success'] == true) {
        _token = data['token'] as String;
        print('✅ Registration successful, token saved');
        return {
          'success': true,
          'token': data['token'],
          'user': User.fromJson(data['user'] as Map<String, dynamic>),
        };
      }
      
      // Обрабатываем ошибки (400, 500 и т.д.)
      final errorMessage = data['message'] as String? ?? 'Ошибка регистрации';
      print('❌ Registration failed: $errorMessage (status: ${response.statusCode})');
      return {
        'success': false,
        'message': errorMessage,
        'statusCode': response.statusCode,
      };
    } on http.ClientException catch (e) {
      print('💥 Network error: $e');
      return {
        'success': false,
        'message': 'Ошибка сети: ${e.message}. Проверьте интернет-соединение и доступность сервера.',
        'error': e.toString(),
      };
    } on FormatException catch (e) {
      print('💥 Format error: $e');
      return {
        'success': false,
        'message': 'Сервер вернул неверный формат данных. Возможно, сервер недоступен.',
        'error': e.toString(),
      };
    } on Exception catch (e) {
      print('💥 Exception: $e');
      return {
        'success': false,
        'message': e.toString(),
        'error': e.toString(),
      };
    } catch (e, stackTrace) {
      print('💥 Unknown error: $e');
      print('💥 Stack trace: $stackTrace');
      
      // Определяем тип ошибки для более понятного сообщения
      String errorMessage;
      if (e.toString().contains('timeout') || e.toString().contains('Timeout')) {
        errorMessage = 'Превышено время ожидания ответа от сервера. Проверьте интернет-соединение.';
      } else if (e.toString().contains('Failed host lookup') || e.toString().contains('Connection refused')) {
        errorMessage = 'Не удалось подключиться к серверу. Проверьте интернет-соединение и убедитесь, что сервер запущен.';
      } else if (e.toString().contains('FormatException')) {
        errorMessage = 'Сервер вернул неверный формат данных. Возможно, сервер недоступен.';
      } else {
        errorMessage = 'Ошибка подключения: $e';
      }
      
      return {
        'success': false,
        'message': errorMessage,
        'error': e.toString(),
      };
    }
  }

  Future<Map<String, dynamic>> sendOtp(String phoneNumber) async {
    try {
      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}${ApiConfig.sendOtp}'),
        headers: ApiConfig.getHeaders(null),
        body: jsonEncode({'phoneNumber': phoneNumber}),
      );

      // Проверяем формат ответа
      final contentType = response.headers['content-type'] ?? '';
      if (!contentType.contains('application/json')) {
        return {
          'success': false,
          'message': 'Сервер вернул неверный формат данных'
        };
      }

      final trimmedBody = response.body.trim();
      if (!trimmedBody.startsWith('{') && !trimmedBody.startsWith('[')) {
        return {
          'success': false,
          'message': 'Сервер вернул HTML вместо JSON. Проверьте, что сервер запущен.'
        };
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return {
        'success': data['success'] ?? false,
        'message': data['message'] ?? '',
      };
    } catch (e) {
      return {
        'success': false,
        'message': 'Ошибка подключения: $e'
      };
    }
  }

  Future<Map<String, dynamic>> verifyOtp(
      String phoneNumber, String code, String? displayName) async {
    try {
      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}${ApiConfig.verifyOtp}'),
        headers: ApiConfig.getHeaders(null),
        body: jsonEncode({
          'phoneNumber': phoneNumber,
          'code': code,
          if (displayName != null) 'displayName': displayName,
        }),
      );

      // Проверяем формат ответа
      final contentType = response.headers['content-type'] ?? '';
      if (!contentType.contains('application/json')) {
        return {
          'success': false,
          'message': 'Сервер вернул неверный формат данных'
        };
      }

      final trimmedBody = response.body.trim();
      if (!trimmedBody.startsWith('{') && !trimmedBody.startsWith('[')) {
        return {
          'success': false,
          'message': 'Сервер вернул HTML вместо JSON. Проверьте, что сервер запущен.'
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
      return {'success': false, 'message': data['message'] as String? ?? 'Неверный код'};
    } catch (e) {
      return {
        'success': false,
        'message': 'Ошибка подключения: $e'
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

  // Upload
  Future<String?> uploadFile(String filePath) async {
    try {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('${ApiConfig.baseUrl}${ApiConfig.uploadFile}'),
      );
      request.headers.addAll(ApiConfig.getHeaders(_token));
      request.files.add(await http.MultipartFile.fromPath('file', filePath));

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final url = data['url'] as String?;
        print('📤 File uploaded: $url');
        return url;
      }
      print('❌ Upload failed: ${response.statusCode}');
      return null;
    } catch (e) {
      print('💥 Upload exception: $e');
      return null;
    }
  }
}
