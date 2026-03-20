import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:intl/date_symbol_data_local.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'config/api_config.dart';
import 'services/http_overrides_setup.dart';
import 'providers/auth_provider.dart';
import 'providers/chat_provider.dart';
import 'screens/login_screen.dart';
import 'screens/chats_screen.dart';
import 'screens/eula_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await setupNetworkOverrides();
  await ApiConfig.init();
  // Инициализируем форматирование дат для русского языка (только для не-веб платформ)
  if (!kIsWeb) {
    try {
      await initializeDateFormatting('ru', null);
    } catch (e) {
      print('⚠️ Failed to initialize date formatting: $e');
      // Продолжаем работу без инициализации форматирования дат
    }
    
    // Запрашиваем разрешения при запуске приложения
    try {
      print('🔐 Requesting permissions on app start...');
      await _requestPermissions();
    } catch (e) {
      print('⚠️ Error requesting permissions: $e');
    }
  }
  runApp(const MyApp());
}

Future<void> _requestPermissions() async {
  if (kIsWeb) return;
  
  try {
    // На iOS проверяем статус разрешений при запуске (но не запрашиваем)
    // Разрешения будут запрошены при использовании функций (рекомендация Apple)
    
    final microphoneStatus = await Permission.microphone.status;
    print('🎤 Microphone permission status on startup: $microphoneStatus');
    if (microphoneStatus.isPermanentlyDenied) {
      print('⚠️ WARNING: Microphone permission is permanently denied. Please delete the app and reinstall it, or enable it in Settings.');
    }
    
    final cameraStatus = await Permission.camera.status;
    print('📷 Camera permission status on startup: $cameraStatus');
    if (cameraStatus.isPermanentlyDenied) {
      print('⚠️ WARNING: Camera permission is permanently denied. Please delete the app and reinstall it, or enable it in Settings.');
    }
    
    // Для Android 13+ запрашиваем разрешение на уведомления при запуске
    // На iOS уведомления запрашиваются автоматически при первом использовании
    if (!kIsWeb) {
      try {
        final notificationStatus = await Permission.notification.status;
        if (notificationStatus.isDenied) {
          print('🔔 Requesting notification permission...');
          final result = await Permission.notification.request();
          print('🔔 Notification permission: ${result.toString()}');
        } else if (notificationStatus.isGranted) {
          print('✅ Notification permission already granted');
        }
      } catch (e) {
        // На iOS может быть ошибка, это нормально
        print('ℹ️ Notification permission check skipped (may not be available on this platform): $e');
      }
    }
  } catch (e) {
    print('❌ Error checking permissions: $e');
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProxyProvider<AuthProvider, ChatProvider>(
          create: (_) => ChatProvider(),
          update: (_, authProvider, chatProvider) {
            chatProvider ??= ChatProvider();
            // Передаем SocketService и ApiService из AuthProvider в ChatProvider
            chatProvider.setSocketService(authProvider.socketService);
            chatProvider.setApiService(authProvider.apiService);
            // Устанавливаем текущего пользователя для отслеживания непрочитанных сообщений
            if (authProvider.currentUser != null) {
              chatProvider.setCurrentUserId(authProvider.currentUser!.id);
            }
            return chatProvider;
          },
        ),
      ],
      child: MaterialApp(
        title: 'Мессенджер',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
          useMaterial3: true,
        ),
        home: const AuthWrapper(),
        debugShowCheckedModeBanner: false,
      ),
    );
  }
}

class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  bool _eulaAccepted = false;
  bool _checkingEula = true;

  @override
  void initState() {
    super.initState();
    _checkEulaStatus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Добавляем таймаут для предотвращения зависания при проблемах с сетью
      context.read<AuthProvider>().init().timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          print('⚠️ AuthWrapper: Initialization timeout, showing login screen');
          if (mounted) {
            setState(() {}); // Обновляем состояние для показа экрана входа
          }
        },
      ).catchError((error) {
        print('💥 AuthWrapper: Initialization error: $error');
        // Не блокируем запуск приложения, показываем экран входа
        if (mounted) {
          setState(() {});
        }
      });
    });
  }

  Future<void> _checkEulaStatus() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final accepted = prefs.getBool('eula_accepted') ?? false;
      if (mounted) {
        setState(() {
          _eulaAccepted = accepted;
          _checkingEula = false;
        });
      }
    } catch (e) {
      print('⚠️ Error checking EULA status: $e');
      if (mounted) {
        setState(() {
          _eulaAccepted = false;
          _checkingEula = false;
        });
      }
    }
  }

  void _onEulaAccepted() {
    setState(() {
      _eulaAccepted = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    // Показываем загрузку пока проверяем EULA
    if (_checkingEula) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    // Если EULA не принят, показываем экран EULA
    if (!_eulaAccepted) {
      return EulaScreen(onAccept: _onEulaAccepted);
    }

    final authProvider = context.watch<AuthProvider>();

    if (authProvider.isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    // Если пользователь авторизован, показываем ChatsScreen
    if (authProvider.isLoggedIn) {
      return const ChatsScreen();
    }

    return const LoginScreen();
  }
}
