import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:intl/date_symbol_data_local.dart';
import 'package:permission_handler/permission_handler.dart';
import 'providers/auth_provider.dart';
import 'providers/chat_provider.dart';
import 'screens/login_screen.dart';
import 'screens/chats_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
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
    // На iOS не запрашиваем разрешения при запуске - они будут запрошены при использовании функций
    // Это соответствует рекомендациям Apple - запрашивать разрешения контекстно
    
    // Только проверяем статус и логируем
    final microphoneStatus = await Permission.microphone.status;
    print('🎤 Microphone permission status on startup: $microphoneStatus');
    
    final cameraStatus = await Permission.camera.status;
    print('📷 Camera permission status on startup: $cameraStatus');
    
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
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AuthProvider>().init().then((_) {
        if (mounted) {
          final isLoggedIn = context.read<AuthProvider>().isLoggedIn;
          if (isLoggedIn) {
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(builder: (_) => const ChatsScreen()),
            );
          }
        }
      });
    });
  }

  @override
  Widget build(BuildContext context) {
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
