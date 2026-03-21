import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user.dart';
import 'api_service.dart';

class AuthService {
  final ApiService _apiService = ApiService();
  final String _tokenKey = 'auth_token';
  final String _userKey = 'user_data';
  String? _lastError;
  
  String? get errorMessage => _lastError;

  Future<bool> login(String email, String password) async {
    try {
      print('🔑 AuthService: Starting login...');
      final result = await _apiService.emailLogin(email, password);
      print('🔑 AuthService: Login result: $result');
      
      if (result['success'] == true) {
        final token = result['token'] as String;
        final user = result['user'] as User;
        print('🔑 AuthService: Saving auth data...');
        await _saveAuthData(token, user);
        _apiService.setToken(token);
        print('🔑 AuthService: Login successful!');
        _lastError = null;
        return true;
      }
      _lastError = result['message'] as String? ?? 'Ошибка входа';
      print('🔑 AuthService: Login failed: $_lastError');
      return false;
    } catch (e, stackTrace) {
      print('💥 AuthService login exception: $e');
      print('💥 Stack trace: $stackTrace');
      return false;
    }
  }

  Future<bool> register(
      String email, String password, String displayName) async {
    final result =
        await _apiService.emailRegister(email, password, displayName);
    if (result['success'] == true) {
      final token = result['token'] as String;
      final user = result['user'] as User;
      await _saveAuthData(token, user);
      _apiService.setToken(token);
      return true;
    }
    return false;
  }

  Future<bool> sendOtp(String phoneNumber) async {
    try {
      print('📱 AuthService: Sending OTP to $phoneNumber');
      final result = await _apiService.sendOtp(phoneNumber);
      print('📱 AuthService: Send OTP result: $result');
      if (result['success'] == true) {
        _lastError = null;
        return true;
      }
      _lastError = result['message'] as String? ?? 'Ошибка отправки SMS';
      return false;
    } catch (e) {
      print('💥 AuthService sendOtp exception: $e');
      _lastError = 'Ошибка отправки SMS: $e';
      return false;
    }
  }

  Future<bool> verifyOtp(String phoneNumber, String code, {String? displayName}) async {
    try {
      print('📱 AuthService: Verifying OTP for $phoneNumber');
      final result = await _apiService.verifyOtp(phoneNumber, code, displayName);
      print('📱 AuthService: Verify OTP result: $result');
      
      if (result['success'] == true) {
        final token = result['token'] as String;
        final user = result['user'] as User;
        print('📱 AuthService: Saving auth data...');
        await _saveAuthData(token, user);
        _apiService.setToken(token);
        print('📱 AuthService: Phone login successful!');
        _lastError = null;
        return true;
      }
      _lastError = result['message'] as String? ?? 'Неверный код подтверждения';
      print('📱 AuthService: Phone login failed: $_lastError');
      return false;
    } catch (e, stackTrace) {
      print('💥 AuthService verifyOtp exception: $e');
      print('💥 Stack trace: $stackTrace');
      _lastError = 'Ошибка проверки кода: $e';
      return false;
    }
  }

  Future<void> _saveAuthData(String token, User user) async {
    try {
      print('💾 AuthService: Saving auth data...');
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_tokenKey, token);
      final userJson = userToJson(user);
      print('💾 AuthService: User JSON: $userJson');
      await prefs.setString(_userKey, userJson);
      print('💾 AuthService: Auth data saved successfully');
      
      // Проверяем, что данные сохранились
      final savedToken = await prefs.getString(_tokenKey);
      final savedUser = await prefs.getString(_userKey);
      print('💾 AuthService: Verification - token saved: ${savedToken != null}');
      print('💾 AuthService: Verification - user saved: ${savedUser != null}');
    } catch (e, stackTrace) {
      print('💥 AuthService _saveAuthData exception: $e');
      print('💥 Stack trace: $stackTrace');
      rethrow;
    }
  }

  Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_tokenKey);
  }

  Future<User?> getUser() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userJson = prefs.getString(_userKey);
      print('🔍 AuthService: getUser - userJson: ${userJson != null ? "exists" : "null"}');
      if (userJson != null) {
        final user = userFromJson(userJson);
        print('🔍 AuthService: getUser - user loaded: ${user.id}');
        return user;
      }
      print('🔍 AuthService: getUser - no user data found');
      return null;
    } catch (e, stackTrace) {
      print('💥 AuthService getUser exception: $e');
      print('💥 Stack trace: $stackTrace');
      return null;
    }
  }

  Future<bool> isLoggedIn() async {
    final token = await getToken();
    return token != null && token.isNotEmpty;
  }

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    await prefs.remove(_userKey);
    _apiService.setToken(null);
  }

  String userToJson(User user) {
    return jsonEncode(user.toJson());
  }

  User userFromJson(String jsonString) {
    final json = jsonDecode(jsonString) as Map<String, dynamic>;
    return User.fromJson(json);
  }
}
