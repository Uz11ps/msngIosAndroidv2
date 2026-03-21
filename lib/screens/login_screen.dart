import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import 'register_screen.dart';
import 'chats_screen.dart';
import 'diagnostics_screen.dart';

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
  
  bool _isPhoneLogin = false;
  bool _otpSent = false;
  int _countdown = 0;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _phoneController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  void _startCountdown() {
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
    
    final success = await authProvider.sendOtp(phoneNumber);
    
    if (success) {
      setState(() {
        _otpSent = true;
      });
      _startCountdown();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('SMS код отправлен'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(authProvider.errorMessage ?? 'Ошибка отправки SMS'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _verifyOtp() async {
    if (!_formKey.currentState!.validate()) return;

    final phoneNumber = _normalizePhoneNumber(_phoneController.text.trim());
    final code = _codeController.text.trim();
    final authProvider = context.read<AuthProvider>();
    
    final success = await authProvider.verifyOtp(phoneNumber, code);

    if (success) {
      await Future.delayed(const Duration(milliseconds: 200));
      
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const ChatsScreen()),
        );
      }
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

    if (success) {
      // Небольшая задержка для гарантии обновления состояния
      await Future.delayed(const Duration(milliseconds: 200));
      
      if (mounted) {
        print('📱 LoginScreen: Navigating to ChatsScreen...');
        print('📱 LoginScreen: Final check - isLoggedIn: ${authProvider.isLoggedIn}');
        print('📱 LoginScreen: Final check - currentUser: ${authProvider.currentUser?.id}');
        
        // Используем pushReplacement для замены экрана логина на экран чатов
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const ChatsScreen()),
        );
      } else {
        print('⚠️ LoginScreen: Widget not mounted, cannot navigate');
      }
    } else if (mounted) {
      print('📱 LoginScreen: Showing error: ${authProvider.errorMessage}');
      final errorMessage = authProvider.errorMessage ?? 'Ошибка входа';
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                errorMessage,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              if (errorMessage.contains('Сервер') || 
                  errorMessage.contains('подключения') ||
                  errorMessage.contains('сеть'))
                const SizedBox(height: 4),
              if (errorMessage.contains('Сервер') || 
                  errorMessage.contains('подключения') ||
                  errorMessage.contains('сеть'))
                TextButton(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const DiagnosticsScreen(),
                      ),
                    );
                  },
                  child: const Text(
                    'Проверить подключение',
                    style: TextStyle(color: Colors.white70),
                  ),
                ),
            ],
          ),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 8),
          action: SnackBarAction(
            label: 'Диагностика',
            textColor: Colors.white,
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const DiagnosticsScreen(),
                ),
              );
            },
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
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
                    selected: {_isPhoneLogin},
                    onSelectionChanged: (Set<bool> newSelection) {
                      setState(() {
                        _isPhoneLogin = newSelection.first;
                        _otpSent = false;
                        _countdown = 0;
                        _codeController.clear();
                      });
                    },
                  ),
                  const SizedBox(height: 24),
                  if (!_isPhoneLogin) ...[
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
                    if (!_otpSent)
                      Consumer<AuthProvider>(
                        builder: (context, authProvider, _) {
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
                        },
                      )
                    else ...[
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
                            child: Consumer<AuthProvider>(
                              builder: (context, authProvider, _) {
                                return ElevatedButton(
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
                                );
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          TextButton(
                            onPressed: _countdown > 0
                                ? null
                                : () {
                                    setState(() {
                                      _otpSent = false;
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
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const DiagnosticsScreen(),
                        ),
                      );
                    },
                    icon: const Icon(Icons.bug_report, size: 18),
                    label: const Text('Диагностика подключения'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
