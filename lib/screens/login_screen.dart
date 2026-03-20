import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../providers/auth_provider.dart';
import 'register_screen.dart';
import 'chats_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _phoneController = TextEditingController();
  final _codeController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  final _scrollController = ScrollController();
  final Connectivity _connectivity = Connectivity();
  
  int _countdown = 0;
  bool _isCellular = false;
  bool _warningShown = false;

  @override
  void initState() {
    super.initState();
    _checkNetworkType();
    // Слушаем изменения типа сети
    _connectivity.onConnectivityChanged.listen((List<ConnectivityResult> result) {
      _checkNetworkType();
    });
  }

  Future<void> _checkNetworkType() async {
    try {
      final connectivityResult = await _connectivity.checkConnectivity();
      final isCellular = connectivityResult.contains(ConnectivityResult.mobile) ||
                        connectivityResult.contains(ConnectivityResult.other);
      
      if (mounted) {
        final wasCellular = _isCellular;
        setState(() {
          _isCellular = isCellular;
        });
        
        // Показываем предупреждение один раз при использовании мобильных данных
        if (isCellular && !_warningShown) {
          _warningShown = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              _showCellularWarning();
            }
          });
        }
        
        // Если переключились с мобильных данных на Wi-Fi, сбрасываем флаг предупреждения
        if (wasCellular && !isCellular) {
          _warningShown = false;
        }
      }
    } catch (e) {
      print('⚠️ Failed to check network type: $e');
    }
  }

  void _showCellularWarning() {
    // Предупреждение больше не нужно - HTTPS работает через мобильные данные
    // Оставляем метод для совместимости, но не показываем диалог
    print('📱 Using cellular network - HTTPS should work fine');
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _phoneController.dispose();
    _codeController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _startCountdown() {
    if (!mounted) return;
    
    setState(() {
      _countdown = 60;
    });
    
    Future.doWhile(() async {
      await Future.delayed(const Duration(seconds: 1));
      if (mounted) {
        setState(() {
          _countdown--;
        });
        return _countdown > 0;
      }
      return false;
    });
  }

  String _normalizePhoneNumber(String phone) {
    // Убираем все нецифровые символы
    String normalized = phone.replaceAll(RegExp(r'\D'), '');
    
    // Если номер начинается с 8, заменяем на 7
    if (normalized.startsWith('8')) {
      normalized = '7' + normalized.substring(1);
    }
    
    // Если номер не начинается с 7, добавляем 7
    if (!normalized.startsWith('7')) {
      normalized = '7' + normalized;
    }
    
    // Добавляем + в начало
    return '+$normalized';
  }

  Future<void> _sendOtp() async {
    if (!_formKey.currentState!.validate()) return;
    
    final phoneNumber = _normalizePhoneNumber(_phoneController.text.trim());
    final authProvider = context.read<AuthProvider>();
    
    print('📱 Sending OTP to: $phoneNumber');
    
    final success = await authProvider.sendOtp(phoneNumber);
    print('📱 OTP send result: $success');
    
    if (success) {
      print('📱 OTP sent successfully');
      _startCountdown();
      
      // Принудительно обновляем UI через setState
      if (mounted) {
        setState(() {
          // Пустой setState для принудительного обновления
        });
      }
      
      // Используем addPostFrameCallback для гарантии обновления UI
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          // Прокручиваем к полю ввода кода
          if (_scrollController.hasClients) {
            _scrollController.animateTo(
              _scrollController.position.maxScrollExtent,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOut,
            );
          }
          
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('SMS код отправлен'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 2),
            ),
          );
        }
      });
    } else {
      print('❌ OTP send failed');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(authProvider.errorMessage ?? 'Ошибка отправки SMS'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _verifyOtp() async {
    if (!_formKey.currentState!.validate()) return;

    final phoneNumber = _normalizePhoneNumber(_phoneController.text.trim());
    final code = _codeController.text.trim();
    final authProvider = context.read<AuthProvider>();
    
    final success = await authProvider.verifyOtp(phoneNumber, code);

    if (success && mounted) {
      await Future.delayed(const Duration(milliseconds: 200));
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const ChatsScreen()),
        (route) => false,
      );
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(authProvider.errorMessage ?? 'Ошибка проверки кода'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;

    print('📱 LoginScreen: Starting login process...');
    final authProvider = context.read<AuthProvider>();
    final success = await authProvider.login(
      _emailController.text.trim(),
      _passwordController.text,
    );

    print('📱 LoginScreen: Login result: $success');
    print('📱 LoginScreen: Current user: ${authProvider.currentUser?.id}');
    print('📱 LoginScreen: Is logged in: ${authProvider.isLoggedIn}');

    if (success && mounted) {
      // Небольшая задержка для гарантии обновления состояния
      await Future.delayed(const Duration(milliseconds: 200));
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const ChatsScreen()),
        (route) => false,
      );
    } else if (mounted) {
      print('📱 LoginScreen: Showing error: ${authProvider.errorMessage}');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(authProvider.errorMessage ?? 'Ошибка входа'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AuthProvider>(
      builder: (context, authProvider, _) {
        final otpSent = authProvider.otpSent;
        final isPhoneLogin = authProvider.isPhoneLogin;
        print('📱 LoginScreen build: otpSent=$otpSent, isPhoneLogin=$isPhoneLogin');
        print('📱 Will show code input: ${otpSent && isPhoneLogin}');
        return Scaffold(
          body: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                controller: _scrollController,
                padding: const EdgeInsets.all(24.0),
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                  const Icon(
                    Icons.chat_bubble_outline,
                    size: 80,
                    color: Colors.blue,
                  ),
                  const SizedBox(height: 32),
                  const Text(
                    'Мессенджер',
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 48),
                  // Индикатор мобильного интернета (HTTPS работает через мобильные данные)
                  if (_isCellular)
                    Container(
                      padding: const EdgeInsets.all(12),
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        border: Border.all(color: Colors.blue.shade300),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.info_outline, 
                               color: Colors.blue.shade700, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Используется мобильный интернет. Приложение работает через HTTPS.',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.blue.shade900,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment<bool>(
                        value: false,
                        label: Text('Email'),
                        icon: Icon(Icons.email),
                      ),
                      ButtonSegment<bool>(
                        value: true,
                        label: Text('Телефон'),
                        icon: Icon(Icons.phone),
                      ),
                    ],
                    selected: {isPhoneLogin},
                    onSelectionChanged: (Set<bool> newSelection) {
                      final authProvider = context.read<AuthProvider>();
                      authProvider.resetOtpState();
                      authProvider.setPhoneLogin(newSelection.first);
                      setState(() {
                        _countdown = 0;
                        _codeController.clear();
                      });
                    },
                  ),
                  const SizedBox(height: 24),
                  if (!isPhoneLogin) ...[
                    TextFormField(
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(
                        labelText: 'Email',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.email),
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Введите email';
                        }
                        if (!value.contains('@')) {
                          return 'Введите корректный email';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _passwordController,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'Пароль',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.lock),
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Введите пароль';
                        }
                        if (value.length < 6) {
                          return 'Пароль должен быть не менее 6 символов';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 24),
                    Consumer<AuthProvider>(
                      builder: (context, authProvider, _) {
                        return ElevatedButton(
                          onPressed:
                              authProvider.isLoading ? null : _login,
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                          child: authProvider.isLoading
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Text('Войти'),
                        );
                      },
                    ),
                  ] else ...[
                    TextFormField(
                      controller: _phoneController,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                        labelText: 'Номер телефона',
                        hintText: '+7XXXXXXXXXX или 8XXXXXXXXXX',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.phone),
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Введите номер телефона';
                        }
                        final phone = value.replaceAll(RegExp(r'\D'), '');
                        if (phone.length < 10 || phone.length > 11) {
                          return 'Введите корректный номер телефона';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    Builder(
                      builder: (_) {
                        print('📱 Rendering OTP section: otpSent=$otpSent');
                        if (!otpSent) {
                          print('📱 Rendering: Send OTP button');
                          return ElevatedButton(
                        onPressed: authProvider.isLoading || _countdown > 0
                            ? null
                            : _sendOtp,
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        child: authProvider.isLoading
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : Text(_countdown > 0
                                ? 'Повторить через $_countdown сек'
                                : 'Отправить код'),
                          );
                        } else {
                          print('📱 Rendering: Code input field');
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              TextFormField(
                        controller: _codeController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Код подтверждения',
                          hintText: '0000',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.lock_outline),
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Введите код подтверждения';
                          }
                          if (value.length < 4) {
                            return 'Код должен содержать 4 цифры';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton(
                              onPressed: authProvider.isLoading
                                  ? null
                                  : _verifyOtp,
                              style: ElevatedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 16),
                              ),
                              child: authProvider.isLoading
                                  ? const SizedBox(
                                      height: 20,
                                      width: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Text('Войти'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          TextButton(
                            onPressed: _countdown > 0
                                ? null
                                : () {
                                    final authProvider = context.read<AuthProvider>();
                                    authProvider.resetOtpState();
                                    setState(() {
                                      _codeController.clear();
                                    });
                                  },
                            child: Text(_countdown > 0
                                ? '$_countdown сек'
                                : 'Изменить номер'),
                          ),
                        ],
                      ),
                    ],
                  );
                }
              },
            ),
                  ],
              const SizedBox(height: 16),
              TextButton(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const RegisterScreen(),
                    ),
                  );
                },
                child: const Text('Нет аккаунта? Зарегистрироваться'),
              ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
