import 'package:flutter/foundation.dart';
import '../models/user.dart';
import '../services/auth_service.dart';
import '../services/api_service.dart';
import '../services/socket_service.dart';

class AuthProvider with ChangeNotifier {
  final AuthService _authService = AuthService();
  final ApiService _apiService = ApiService();
  final SocketService _socketService = SocketService();

  User? _currentUser;
  bool _isLoading = false;
  String? _errorMessage;

  User? get currentUser => _currentUser;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  bool get isLoggedIn => _currentUser != null;
  SocketService get socketService => _socketService;
  ApiService get apiService => _apiService;

  Future<void> init() async {
    _isLoading = true;
    notifyListeners();

    try {
      final token = await _authService.getToken();
      if (token != null) {
        _apiService.setToken(token);
        _currentUser = await _authService.getUser();
        if (_currentUser != null) {
          _socketService.initialize(_currentUser!.id, token);
        }
      }
    } catch (e) {
      print('Error initializing auth: $e');
    }

    _isLoading = false;
    notifyListeners();
  }

  Future<bool> login(String email, String password) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      print('👤 AuthProvider: Starting login...');
      final success = await _authService.login(email, password);
      print('👤 AuthProvider: Login success: $success');
      
      if (success) {
        // Небольшая задержка для гарантии сохранения данных
        await Future.delayed(const Duration(milliseconds: 100));
        
        _currentUser = await _authService.getUser();
        final token = await _authService.getToken();
        print('👤 AuthProvider: User loaded: ${_currentUser?.id}');
        print('👤 AuthProvider: Token loaded: ${token != null}');
        
        if (_currentUser != null && token != null) {
          _apiService.setToken(token);
          // Инициализируем Socket только если он еще не подключен или подключен с другими данными
          if (!_socketService.isConnected || _socketService.socket == null) {
            _socketService.initialize(_currentUser!.id, token);
            print('👤 AuthProvider: Socket initialized');
          } else {
            print('👤 AuthProvider: Socket already connected, skipping initialization');
          }
          _isLoading = false;
          notifyListeners();
          print('👤 AuthProvider: Returning true');
          return true;
        } else {
          print('⚠️ AuthProvider: User or token is null! Retrying...');
          // Повторная попытка через небольшую задержку
          await Future.delayed(const Duration(milliseconds: 200));
          _currentUser = await _authService.getUser();
          final retryToken = await _authService.getToken();
          
          if (_currentUser != null && retryToken != null) {
            _apiService.setToken(retryToken);
            if (!_socketService.isConnected || _socketService.socket == null) {
              _socketService.initialize(_currentUser!.id, retryToken);
            }
            _isLoading = false;
            notifyListeners();
            print('👤 AuthProvider: Retry successful, returning true');
            return true;
          } else {
            _errorMessage = 'Ошибка загрузки данных пользователя';
            _isLoading = false;
            notifyListeners();
            print('👤 AuthProvider: Retry failed, returning false');
            return false;
          }
        }
      } else {
        // Получаем детальное сообщение об ошибке из API
        final apiError = _authService.errorMessage;
        if (apiError != null && (apiError.contains('Сервер вернул') || apiError.contains('Ошибка сети'))) {
          _errorMessage = apiError;
        } else {
          _errorMessage = apiError ?? 'Неверный email или пароль';
        }
        _isLoading = false;
        notifyListeners();
        print('👤 AuthProvider: Returning false: $_errorMessage');
        return false;
      }
    } catch (e, stackTrace) {
      print('💥 AuthProvider login exception: $e');
      print('💥 Stack trace: $stackTrace');
      
      // Формируем понятное сообщение об ошибке
      String errorMsg = 'Ошибка входа';
      if (e.toString().contains('timeout') || e.toString().contains('Timeout')) {
        errorMsg = 'Превышено время ожидания. Проверьте интернет-соединение.';
      } else if (e.toString().contains('Failed host lookup') || e.toString().contains('Connection refused')) {
        errorMsg = 'Не удалось подключиться к серверу. Проверьте интернет-соединение и доступность сервера.';
      } else if (e.toString().contains('FormatException')) {
        errorMsg = 'Сервер вернул неверный формат данных. Возможно, сервер недоступен.';
      } else {
        errorMsg = 'Ошибка входа: $e';
      }
      
      _errorMessage = errorMsg;
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> register(
      String email, String password, String displayName) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final success =
          await _authService.register(email, password, displayName);
      if (success) {
        _currentUser = await _authService.getUser();
        final token = await _authService.getToken();
        if (_currentUser != null && token != null) {
          _apiService.setToken(token);
          _socketService.initialize(_currentUser!.id, token);
        }
        _isLoading = false;
        notifyListeners();
        return true;
      } else {
        _errorMessage = 'Ошибка регистрации';
        _isLoading = false;
        notifyListeners();
        return false;
      }
    } catch (e) {
      _errorMessage = 'Ошибка регистрации: $e';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<void> logout() async {
    await _authService.logout();
    _socketService.disconnect();
    _currentUser = null;
    _apiService.setToken(null);
    notifyListeners();
  }

  Future<void> refreshUser() async {
    final token = await _authService.getToken();
    if (token != null) {
      _apiService.setToken(token);
      _currentUser = await _authService.getUser();
      notifyListeners();
    }
  }

  Future<bool> sendOtp(String phoneNumber) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final success = await _authService.sendOtp(phoneNumber);
      if (success) {
        _isLoading = false;
        notifyListeners();
        return true;
      } else {
        _errorMessage = _authService.errorMessage ?? 'Ошибка отправки SMS';
        _isLoading = false;
        notifyListeners();
        return false;
      }
    } catch (e) {
      _errorMessage = 'Ошибка отправки SMS: $e';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> verifyOtp(String phoneNumber, String code, {String? displayName}) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      print('👤 AuthProvider: Starting phone login...');
      final success = await _authService.verifyOtp(phoneNumber, code, displayName: displayName);
      print('👤 AuthProvider: Phone login success: $success');
      
      if (success) {
        await Future.delayed(const Duration(milliseconds: 100));
        
        _currentUser = await _authService.getUser();
        final token = await _authService.getToken();
        print('👤 AuthProvider: User loaded: ${_currentUser?.id}');
        print('👤 AuthProvider: Token loaded: ${token != null}');
        
        if (_currentUser != null && token != null) {
          _apiService.setToken(token);
          if (!_socketService.isConnected || _socketService.socket == null) {
            _socketService.initialize(_currentUser!.id, token);
            print('👤 AuthProvider: Socket initialized');
          }
          _isLoading = false;
          notifyListeners();
          print('👤 AuthProvider: Returning true');
          return true;
        } else {
          await Future.delayed(const Duration(milliseconds: 200));
          _currentUser = await _authService.getUser();
          final retryToken = await _authService.getToken();
          
          if (_currentUser != null && retryToken != null) {
            _apiService.setToken(retryToken);
            if (!_socketService.isConnected || _socketService.socket == null) {
              _socketService.initialize(_currentUser!.id, retryToken);
            }
            _isLoading = false;
            notifyListeners();
            return true;
          } else {
            _errorMessage = 'Ошибка загрузки данных пользователя';
            _isLoading = false;
            notifyListeners();
            return false;
          }
        }
      } else {
        _errorMessage = _authService.errorMessage ?? 'Неверный код подтверждения';
        _isLoading = false;
        notifyListeners();
        return false;
      }
    } catch (e, stackTrace) {
      print('💥 AuthProvider verifyOtp exception: $e');
      print('💥 Stack trace: $stackTrace');
      _errorMessage = 'Ошибка проверки кода: $e';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }
}
