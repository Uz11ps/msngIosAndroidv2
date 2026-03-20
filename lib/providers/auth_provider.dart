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
  bool _otpSent = false;
  String? _otpPhoneNumber;
  bool _isPhoneLogin = false;

  User? get currentUser => _currentUser;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  bool get isLoggedIn => _currentUser != null;
  bool get otpSent => _otpSent;
  String? get otpPhoneNumber => _otpPhoneNumber;
  bool get isPhoneLogin => _isPhoneLogin;
  SocketService get socketService => _socketService;
  ApiService get apiService => _apiService;
  
  void setPhoneLogin(bool value) {
    _isPhoneLogin = value;
    notifyListeners();
  }

  Future<void> init() async {
    _isLoading = true;
    notifyListeners();

    try {
      print('👤 AuthProvider: Initializing...');
      // Добавляем таймаут для предотвращения зависания при проблемах с сетью
      final token = await _authService.getToken()
          .timeout(
            const Duration(seconds: 5),
            onTimeout: () {
              print('⚠️ AuthProvider: Token retrieval timeout');
              return null;
            },
          );
      
      if (token != null) {
        print('👤 AuthProvider: Token found, loading user...');
        _apiService.setToken(token);
        _currentUser = await _authService.getUser()
            .timeout(
              const Duration(seconds: 5),
              onTimeout: () {
                print('⚠️ AuthProvider: User retrieval timeout');
                return null;
              },
            );
        
        if (_currentUser != null) {
          print('👤 AuthProvider: User loaded, initializing socket...');
          // Инициализация Socket не должна блокировать запуск приложения
          try {
            _socketService.initialize(_currentUser!.id, token);
          } catch (e) {
            print('⚠️ AuthProvider: Socket initialization error (non-critical): $e');
            // Не прерываем запуск приложения из-за ошибки Socket
          }
        } else {
          print('⚠️ AuthProvider: User is null after loading');
        }
      } else {
        print('👤 AuthProvider: No token found, user needs to login');
      }
    } catch (e, stackTrace) {
      print('💥 AuthProvider: Initialization error: $e');
      print('💥 Stack trace: $stackTrace');
      // Не блокируем запуск приложения из-за ошибки инициализации
    } finally {
      _isLoading = false;
      notifyListeners();
      print('👤 AuthProvider: Initialization completed');
    }
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
        _errorMessage = _authService.errorMessage ?? 'Неверный email или пароль';
        _isLoading = false;
        notifyListeners();
        print('👤 AuthProvider: Returning false: $_errorMessage');
        return false;
      }
    } catch (e, stackTrace) {
      print('💥 AuthProvider login exception: $e');
      print('💥 Stack trace: $stackTrace');
      _errorMessage = 'Ошибка входа: $e';
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
      print('👤 AuthProvider: Starting registration...');
      print('👤 AuthProvider: Email: $email');
      print('👤 AuthProvider: DisplayName: $displayName');
      
      final success =
          await _authService.register(email, password, displayName);
      
      print('👤 AuthProvider: Registration success: $success');
      
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
          print('👤 AuthProvider: Registration completed successfully');
          return true;
        } else {
          print('⚠️ AuthProvider: User or token is null after registration!');
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
            print('👤 AuthProvider: Retry successful after registration');
            return true;
          } else {
            _errorMessage = 'Ошибка загрузки данных пользователя';
            _isLoading = false;
            notifyListeners();
            print('👤 AuthProvider: Retry failed after registration');
            return false;
          }
        }
      } else {
        _errorMessage = _authService.errorMessage ?? 'Ошибка регистрации';
        _isLoading = false;
        notifyListeners();
        print('👤 AuthProvider: Registration failed: $_errorMessage');
        return false;
      }
    } catch (e, stackTrace) {
      print('💥 AuthProvider register exception: $e');
      print('💥 Stack trace: $stackTrace');
      _errorMessage = _authService.errorMessage ?? 'Ошибка регистрации: $e';
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
        _otpSent = true;
        _otpPhoneNumber = phoneNumber;
        _isLoading = false;
        notifyListeners();
        return true;
      } else {
        _errorMessage = _authService.errorMessage ?? 'Ошибка отправки SMS';
        _otpSent = false;
        _otpPhoneNumber = null;
        _isLoading = false;
        notifyListeners();
        return false;
      }
    } catch (e) {
      _errorMessage = 'Ошибка отправки SMS: $e';
      _otpSent = false;
      _otpPhoneNumber = null;
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }
  
  void resetOtpState() {
    _otpSent = false;
    _otpPhoneNumber = null;
    notifyListeners();
  }
  
  void resetLoginState() {
    _otpSent = false;
    _otpPhoneNumber = null;
    _isPhoneLogin = false;
    notifyListeners();
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
          // Сбрасываем состояние OTP после успешного входа
          _otpSent = false;
          _otpPhoneNumber = null;
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
