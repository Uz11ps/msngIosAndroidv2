import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:permission_handler/permission_handler.dart';
import 'dart:async';
import '../providers/auth_provider.dart';
import '../providers/chat_provider.dart';
import '../services/auth_service.dart';
import '../services/audio_service.dart';
import '../services/agora_service.dart';
import '../utils/image_utils.dart';
import '../models/chat.dart';
import '../models/user.dart';
import 'user_profile_screen.dart';
import 'group_profile_screen.dart';
import 'call_screen.dart';

class ChatScreen extends StatefulWidget {
  final String chatId;

  const ChatScreen({super.key, required this.chatId});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  final ImagePicker _picker = ImagePicker();
  final AudioService _audioService = AudioService();
  AgoraService? _agoraService;
  
  AgoraService get agoraService {
    _agoraService ??= AgoraService();
    return _agoraService!;
  }
  Chat? _chat;
  User? _otherUser;
  bool _isRecording = false;
  Timer? _recordingTimer;
  int _recordingDuration = 0;
  String? _playingMessageId;
  Map<String, bool> _playingStates = {};
  ChatProvider? _chatProvider;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final authProvider = context.read<AuthProvider>();
      final chatProvider = context.read<ChatProvider>();
      _chatProvider = chatProvider; // Сохраняем ссылку для dispose
      
      // Убеждаемся, что SocketService и ApiService переданы в ChatProvider
      chatProvider.setSocketService(authProvider.socketService);
      chatProvider.setApiService(authProvider.apiService);
      
      // Устанавливаем текущего пользователя для отслеживания непрочитанных сообщений
      if (authProvider.currentUser != null) {
        chatProvider.setCurrentUserId(authProvider.currentUser!.id);
      }
      
      // Устанавливаем текущий открытый чат и сбрасываем счетчик непрочитанных
      chatProvider.setCurrentChat(widget.chatId);
      
      // Agora инициализируется лениво при первом звонке
      // Не инициализируем здесь, чтобы избежать ошибок при hot restart
      
      // Устанавливаем токен для AudioService
      final authService = AuthService();
      final token = await authService.getToken();
      if (token != null) {
        _audioService.setToken(token);
      }
      
      // Настраиваем слушатели звонков
      _setupCallListeners();
      
      await _loadChatInfo();
      
      // Загружаем сообщения и ждем завершения
      await chatProvider.loadMessages(widget.chatId);
      
      // Настраиваем слушатели Socket
      chatProvider.setupSocketListeners();
      
      // Ждем немного перед присоединением к чату, чтобы Socket успел подключиться
      await Future.delayed(const Duration(milliseconds: 500));
      _joinChat();
      
      // Прокручиваем вниз после загрузки сообщений
      if (mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _scrollToBottom();
        });
      }
    });
  }
  
  void _setupCallListeners() {
    final socketService = context.read<AuthProvider>().socketService;
    
    // Входящий звонок
    socketService.onIncomingCall((data) {
      if (mounted) {
        _handleIncomingCall(data);
      }
    });
    
    // Звонок принят
    socketService.onCallAccepted((data) {
      if (mounted) {
        _handleCallAccepted(data);
      }
    });
    
    // Входящий групповой звонок
    socketService.onIncomingGroupCall((data) {
      if (mounted) {
        _handleIncomingGroupCall(data);
      }
    });
    
    // Изменение статуса пользователя
    socketService.onUserStatusChanged((data) {
      if (mounted && _otherUser != null && _otherUser!.id == data['userId']) {
        setState(() {
          _otherUser = User(
            id: _otherUser!.id,
            phoneNumber: _otherUser!.phoneNumber,
            email: _otherUser!.email,
            displayName: _otherUser!.displayName,
            photoUrl: _otherUser!.photoUrl,
            status: data['status'] as String?,
            lastSeen: data['lastSeen'] as int?,
            fcmToken: _otherUser!.fcmToken,
          );
        });
      }
    });
  }
  
  void _handleIncomingCall(Map<String, dynamic> data) {
    // Показываем диалог входящего звонка
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text('Входящий ${data['type'] == 'video' ? 'видео' : 'аудио'} звонок'),
        content: const Text('Звонок от пользователя'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              _rejectCall();
            },
            child: const Text('Отклонить'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              _acceptIncomingCall(data);
            },
            child: const Text('Принять'),
          ),
        ],
      ),
    );
  }
  
  void _handleCallAccepted(Map<String, dynamic> data) {
    // Звонок принят получателем, инициатор присоединяется к каналу
    print('Call accepted by recipient');
    if (_agoraService != null && _agoraService!.isCallActive) {
      final isVideo = _agoraService!.callType == 'video';
      _showCallScreen(isVideo);
    }
  }

  void _handleIncomingGroupCall(Map<String, dynamic> data) {
    // Показываем диалог входящего группового звонка
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text('Входящий групповой ${data['type'] == 'video' ? 'видео' : 'аудио'} звонок'),
        content: Text('Звонок в группе ${_chat?.groupName ?? "Группа"}'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              _rejectCall();
            },
            child: const Text('Отклонить'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              _acceptIncomingGroupCall(data);
            },
            child: const Text('Принять'),
          ),
        ],
      ),
    );
  }

  Future<void> _acceptIncomingGroupCall(Map<String, dynamic> data) async {
    if (kIsWeb) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Звонки не поддерживаются в веб-версии. Используйте мобильное приложение.')),
        );
      }
      return;
    }
    
    final authProvider = context.read<AuthProvider>();
    final currentUserId = authProvider.currentUser?.id;
    if (currentUserId == null) return;
    
    try {
      final channelName = data['channelName'] as String;
      final isVideo = data['type'] == 'video';
      final uid = int.tryParse(currentUserId) ?? currentUserId.hashCode;
      
      // Присоединяемся к групповому каналу Agora
      await agoraService.joinCall(channelName, isVideo, uid);
      
      if (mounted) {
        _showCallScreen(isVideo);
      }
    } catch (e) {
      print('💥 Error accepting group call: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка принятия группового звонка: $e')),
        );
      }
    }
  }
  
  Future<void> _acceptIncomingCall(Map<String, dynamic> data) async {
    if (kIsWeb) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Звонки не поддерживаются в веб-версии. Используйте мобильное приложение.')),
        );
      }
      return;
    }
    
    final authProvider = context.read<AuthProvider>();
    final currentUserId = authProvider.currentUser?.id;
    if (currentUserId == null) return;
    
    try {
      final channelName = data['channelName'] as String;
      final isVideo = data['type'] == 'video';
      final uid = int.tryParse(currentUserId) ?? currentUserId.hashCode;
      
      // Присоединяемся к каналу Agora
      // AgoraService создается и инициализируется здесь при необходимости
      await agoraService.joinCall(channelName, isVideo, uid);
      
      // Отправляем подтверждение принятия звонка
      final socketService = authProvider.socketService;
      socketService.acceptCall(
        chatId: channelName,
        from: data['from'] as String,
      );
      
      if (mounted) {
        _showCallScreen(isVideo);
      }
    } catch (e) {
      print('💥 Error accepting call: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка принятия звонка: $e')),
        );
      }
    }
  }
  
  void _rejectCall() {
    // Отклоняем звонок
  }
  
  void _showCallScreen(bool isVideo) {
    if (!mounted || _agoraService == null) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CallScreen(
          agoraService: _agoraService!,
          isVideo: isVideo,
          onEndCall: () async {
            await _agoraService?.endCall();
            if (mounted) {
              Navigator.of(context).pop();
            }
          },
        ),
      ),
    );
  }
  
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Слушаем изменения в сообщениях и прокручиваем вниз при новых сообщениях
    final chatProvider = context.watch<ChatProvider>();
    final messages = chatProvider.getMessages(widget.chatId);
    if (messages.isNotEmpty && mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToBottom();
      });
    }
  }

  Future<void> _loadChatInfo() async {
    try {
      final chatProvider = context.read<ChatProvider>();
      final chats = chatProvider.chats;
      
      if (chats.isNotEmpty) {
        try {
          _chat = chats.firstWhere((c) => c.id == widget.chatId);
        } catch (e) {
          // Чат не найден в списке, загружаем чаты заново
          await chatProvider.loadChats();
          final updatedChats = chatProvider.chats;
          try {
            _chat = updatedChats.firstWhere((c) => c.id == widget.chatId);
          } catch (e) {
            print('Chat not found: ${widget.chatId}');
          }
        }
      } else {
        // Если список чатов пуст, загружаем его
        await chatProvider.loadChats();
        final updatedChats = chatProvider.chats;
        try {
          _chat = updatedChats.firstWhere((c) => c.id == widget.chatId);
        } catch (e) {
          print('Chat not found after reload: ${widget.chatId}');
        }
      }
      
      if (_chat != null && !_chat!.isGroup) {
        final authProvider = context.read<AuthProvider>();
        final currentUserId = authProvider.currentUser?.id ?? '';
        final otherParticipant = _chat!.participants
            .firstWhere((id) => id != currentUserId, orElse: () => '');
        
        if (otherParticipant.isNotEmpty) {
          final chatProvider = context.read<ChatProvider>();
          
          print('🔍 Loading other user info for userId: $otherParticipant');
          _otherUser = await chatProvider.getUser(otherParticipant);
          
          // Определяем статус на основе lastSeen и наличия в userSockets
          if (_otherUser != null) {
            print('✅ Other user loaded: ${_otherUser!.displayName ?? _otherUser!.email ?? _otherUser!.phoneNumber}');
            print('📸 Photo URL: ${_otherUser!.photoUrl}');
            
            final now = DateTime.now().millisecondsSinceEpoch;
            final lastSeen = _otherUser!.lastSeen ?? 0;
            final timeDiff = now - lastSeen;
            
            // Если lastSeen обновлен недавно (менее 5 минут), считаем онлайн
            // Иначе показываем "Был(а) недавно" или время последнего визита
            String status;
            if (timeDiff < 5 * 60 * 1000) { // 5 минут
              status = 'В сети';
            } else if (timeDiff < 60 * 60 * 1000) { // 1 час
              status = 'Был(а) недавно';
            } else {
              final hours = (timeDiff / (60 * 60 * 1000)).floor();
              status = 'Был(а) $hours ${hours == 1 ? 'час' : 'часов'} назад';
            }
            
            _otherUser = User(
              id: _otherUser!.id,
              phoneNumber: _otherUser!.phoneNumber,
              email: _otherUser!.email,
              displayName: _otherUser!.displayName,
              photoUrl: _otherUser!.photoUrl,
              status: _otherUser!.status ?? status,
              lastSeen: _otherUser!.lastSeen,
              fcmToken: _otherUser!.fcmToken,
            );
          } else {
            print('❌ Other user not found for userId: $otherParticipant');
          }
          
          if (mounted) {
            setState(() {});
          }
        }
      } else if (_chat != null && mounted) {
        setState(() {});
      }
    } catch (e) {
      print('Error loading chat info: $e');
    }
  }

  void _joinChat() {
    final chatProvider = context.read<ChatProvider>();
    final socketService = chatProvider.socketService;
    
    if (socketService == null) {
      print('⚠️ SocketService is null, cannot join chat');
      return;
    }
    
    // Проверяем подключение Socket
    print('🔍 Checking socket connection...');
    print('🔍 Socket is null: ${socketService.socket == null}');
    print('🔍 Socket connected: ${socketService.isConnected}');
    
    if (!socketService.isConnected) {
      print('⚠️ Socket not connected, waiting...');
      // Ждем подключения с таймаутом
      socketService.waitForConnection(() {
        print('✅ Socket connected, joining chat now');
        chatProvider.joinChat(widget.chatId);
      });
      
      // Таймаут на подключение
      Future.delayed(const Duration(seconds: 5), () {
        if (mounted && !socketService.isConnected) {
          print('⚠️ Socket connection timeout, trying to reconnect...');
          final authProvider = context.read<AuthProvider>();
          final currentUserId = authProvider.currentUser?.id;
          final token = authProvider.currentUser != null 
              ? authProvider.socketService.socket?.id 
              : null;
          if (currentUserId != null && token == null) {
            // Переподключаемся
            final authService = AuthService();
            authService.getToken().then((t) {
              if (t != null && mounted) {
                authProvider.socketService.initialize(currentUserId, t);
                socketService.waitForConnection(() {
                  chatProvider.joinChat(widget.chatId);
                });
              }
            });
          }
        }
      });
    } else {
      print('✅ Socket is connected, joining chat');
      chatProvider.joinChat(widget.chatId);
    }
  }

  @override
  void dispose() {
    // Сбрасываем текущий открытый чат при закрытии экрана
    _chatProvider?.setCurrentChat(null);
    
    _messageController.dispose();
    _scrollController.dispose();
    _recordingTimer?.cancel();
    _audioService.dispose();
    _agoraService?.dispose();
    super.dispose();
  }

  void _sendMessage() {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    print('📤 Sending message: $text to chat: ${widget.chatId}');
    
    try {
      final authProvider = context.read<AuthProvider>();
      final currentUserId = authProvider.currentUser?.id;
      
      if (currentUserId == null) {
        print('⚠️ Current user ID is null, cannot send message');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ошибка: пользователь не авторизован')),
        );
        return;
      }
      
      // Проверяем подключение Socket перед отправкой
      final socketService = authProvider.socketService;
      if (!socketService.isConnected) {
        print('⚠️ Socket not connected, waiting before sending message...');
        socketService.waitForConnection(() {
          if (mounted) {
            context.read<ChatProvider>().sendMessage(
              chatId: widget.chatId,
              text: text,
              type: 'text',
              currentUserId: currentUserId,
            );
            _messageController.clear();
            _scrollToBottom();
          }
        });
        return;
      }
      
      print('✅ Socket is connected, sending message');
      context.read<ChatProvider>().sendMessage(
            chatId: widget.chatId,
            text: text,
            type: 'text',
            currentUserId: currentUserId,
          );

      _messageController.clear();
      _scrollToBottom();
      print('✅ Message sent successfully');
    } catch (e, stackTrace) {
      print('❌ Error sending message: $e');
      print('❌ Stack trace: $stackTrace');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка отправки: $e')),
        );
      }
    }
  }

  Future<void> _pickAndSendImage() async {
    if (kIsWeb) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Выбор изображений не поддерживается в веб-версии')),
        );
      }
      return;
    }
    
    try {
      // Запрашиваем разрешение на доступ к галерее (для iOS 14+)
      if (!kIsWeb) {
        var photosStatus = await Permission.photos.status;
        print('📷 Photos permission status: $photosStatus');
        
        // На iOS всегда запрашиваем разрешение, если оно не предоставлено
        if (!photosStatus.isGranted) {
          print('📷 Requesting photos permission...');
          photosStatus = await Permission.photos.request();
          print('📷 Photos permission after request: $photosStatus');
        }
        
        // Если разрешение на фото не предоставлено, пробуем запросить разрешение на медиа
        if (!photosStatus.isGranted) {
          var mediaStatus = await Permission.mediaLibrary.status;
          if (!mediaStatus.isGranted) {
            mediaStatus = await Permission.mediaLibrary.request();
          }
          if (!mediaStatus.isGranted) {
            print('❌ Photos/media permission not granted');
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: const Text('Необходимо разрешение на доступ к галерее'),
                  action: SnackBarAction(
                    label: 'Настройки',
                    onPressed: () => openAppSettings(),
                  ),
                  duration: const Duration(seconds: 5),
                ),
              );
            }
            return;
          }
        }
      }
      
      final XFile? image = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 85,
      );

      if (image == null) return;

      final authProvider = context.read<AuthProvider>();
      final authService = AuthService();
      final token = await authService.getToken();

      if (token == null || authProvider.currentUser == null) return;

      final apiService = authProvider.apiService;
      final url = await apiService.uploadFile(image.path);

      if (url != null) {
        final currentUserId = authProvider.currentUser?.id;
        
        context.read<ChatProvider>().sendMessage(
              chatId: widget.chatId,
              text: null,
              type: 'image',
              mediaUrl: url,
              currentUserId: currentUserId,
            );
        _scrollToBottom();
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка загрузки: $e')),
      );
    }
  }

  Future<void> _startCall(bool isVideo) async {
    if (kIsWeb) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Звонки не поддерживаются в веб-версии. Используйте мобильное приложение.')),
        );
      }
      return;
    }
    
    if (_chat == null) {
      print('⚠️ Chat is null, cannot start call');
      return;
    }
    
    final authProvider = context.read<AuthProvider>();
    final currentUserId = authProvider.currentUser?.id;
    if (currentUserId == null) {
      print('⚠️ Current user ID is null, cannot start call');
      return;
    }

    try {
      // Запрашиваем разрешения для звонка
      if (!kIsWeb) {
        // Проверяем и запрашиваем разрешение на микрофон
        var microphoneStatus = await Permission.microphone.status;
        print('🎤 Microphone permission status: $microphoneStatus');
        
        // На iOS всегда запрашиваем разрешение явно
        // Это важно для эмулятора и устройств, где разрешение может быть не определено
        print('🎤 Requesting microphone permission...');
        microphoneStatus = await Permission.microphone.request();
        print('🎤 Microphone permission after request: $microphoneStatus');
        
        // Проверяем статус еще раз после запроса
        microphoneStatus = await Permission.microphone.status;
        print('🎤 Microphone permission final status: $microphoneStatus');
        
        if (!microphoneStatus.isGranted) {
          print('❌ Microphone permission not granted: $microphoneStatus');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text('Необходимо разрешение на использование микрофона'),
                action: SnackBarAction(
                  label: 'Настройки',
                  onPressed: () => openAppSettings(),
                ),
                duration: const Duration(seconds: 5),
              ),
            );
          }
          return;
        }
        print('✅ Microphone permission granted');
        
        // Для видеозвонка проверяем и запрашиваем разрешение на камеру
        if (isVideo) {
          var cameraStatus = await Permission.camera.status;
          print('📷 Camera permission status: $cameraStatus');
          
          // На iOS всегда запрашиваем разрешение явно
          print('📷 Requesting camera permission...');
          cameraStatus = await Permission.camera.request();
          print('📷 Camera permission after request: $cameraStatus');
          
          // Проверяем статус еще раз после запроса
          cameraStatus = await Permission.camera.status;
          print('📷 Camera permission final status: $cameraStatus');
          
          if (!cameraStatus.isGranted) {
            print('❌ Camera permission not granted: $cameraStatus');
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: const Text('Необходимо разрешение на использование камеры'),
                  action: SnackBarAction(
                    label: 'Настройки',
                    onPressed: () => openAppSettings(),
                  ),
                  duration: const Duration(seconds: 5),
                ),
              );
            }
            return;
          }
          print('✅ Camera permission granted');
        }
      }
      
      // Проверяем подключение Socket перед звонком
      final socketService = authProvider.socketService;
      if (!socketService.isConnected) {
        print('⚠️ Socket not connected, waiting before call...');
        socketService.waitForConnection(() {
          _startCall(isVideo);
        });
        return;
      }
      
      print('📞 Starting ${isVideo ? "video" : "audio"} call...');
      print('📞 Chat ID: ${widget.chatId}');
      print('📞 Is Group: ${_chat!.isGroup}');
      
      // Генерируем UID для Agora (используем hash от userId)
      final uid = int.tryParse(currentUserId) ?? currentUserId.hashCode;
      
      // Начинаем Agora звонок (присоединяемся к каналу)
      await agoraService.startCall(widget.chatId, isVideo, uid);
      print('✅ Agora call started');
      
      // Отправляем событие звонка через Socket
      if (_chat!.isGroup) {
        // Групповой звонок - отправляем всем участникам группы
        print('📞 Sending group call to ${_chat!.participants.length} participants');
        socketService.groupCall(
          chatId: _chat!.id,
          channelName: widget.chatId,
          type: isVideo ? 'video' : 'audio',
          participants: _chat!.participants,
        );
      } else {
        // Личный звонок
        if (_otherUser == null) {
          print('⚠️ Other user is null, cannot start call');
          return;
        }
        print('📞 Sending call to user: ${_otherUser!.id}');
        socketService.callUser(
          to: _otherUser!.id,
          channelName: widget.chatId,
          type: isVideo ? 'video' : 'audio',
        );
      }
      
      // Показываем экран звонка
      if (mounted) {
        _showCallScreen(isVideo);
      }
    } catch (e, stackTrace) {
      print('💥 Error starting call: $e');
      print('💥 Stack trace: $stackTrace');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка звонка: $e')),
        );
      }
    }
  }
  
  Future<void> _startRecording() async {
    if (kIsWeb) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Запись голосовых сообщений не поддерживается в веб-версии. Используйте мобильное приложение.')),
        );
      }
      return;
    }
    
    try {
      // Проверяем и запрашиваем разрешение на микрофон
      var microphoneStatus = await Permission.microphone.status;
      print('🎤 Microphone permission status for recording: $microphoneStatus');
      
      // На iOS всегда запрашиваем разрешение явно
      // Это важно для эмулятора и устройств, где разрешение может быть не определено
      print('🎤 Requesting microphone permission for recording...');
      microphoneStatus = await Permission.microphone.request();
      print('🎤 Microphone permission after request: $microphoneStatus');
      
      // Проверяем статус еще раз после запроса
      microphoneStatus = await Permission.microphone.status;
      print('🎤 Microphone permission final status: $microphoneStatus');
      
      if (!microphoneStatus.isGranted) {
        print('❌ Microphone permission not granted for recording: $microphoneStatus');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Необходимо разрешение на использование микрофона для записи голосовых сообщений'),
              action: SnackBarAction(
                label: 'Настройки',
                onPressed: () => openAppSettings(),
              ),
              duration: const Duration(seconds: 5),
            ),
          );
        }
        return;
      }
      print('✅ Microphone permission granted for recording');
      
      final path = await _audioService.startRecording();
      if (path != null) {
        setState(() {
          _isRecording = true;
          _recordingDuration = 0;
        });
        
        _recordingTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
          if (mounted) {
            setState(() {
              _recordingDuration++;
            });
          }
        });
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Не удалось начать запись. Проверьте разрешения микрофона в настройках.'),
              duration: Duration(seconds: 3),
            ),
          );
        }
      }
    } catch (e) {
      print('💥 Error in _startRecording: $e');
      if (mounted) {
        final errorMessage = e.toString();
        String message;
        
        if (errorMessage.contains('PLUGIN_NOT_AVAILABLE') || 
            errorMessage.contains('MissingPluginException')) {
          message = 'Для работы с голосовыми сообщениями требуется полный перезапуск приложения.\n\nОстановите приложение (кнопка Stop) и запустите заново (flutter run).';
        } else if (errorMessage.contains('permission') || errorMessage.contains('Permission')) {
          message = 'Необходимо разрешение на запись аудио. Проверьте настройки приложения.';
        } else {
          message = 'Ошибка записи: ${e.toString().split('\n').first}';
        }
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            duration: const Duration(seconds: 5),
            action: SnackBarAction(
              label: 'OK',
              onPressed: () {},
            ),
          ),
        );
      }
    }
  }
  
  Future<void> _stopRecording(bool send) async {
    _recordingTimer?.cancel();
    
    if (!_isRecording) return;
    
    setState(() {
      _isRecording = false;
    });
    
    if (!send) {
      await _audioService.cancelRecording();
      return;
    }
    
    try {
      final path = await _audioService.stopRecording();
      if (path == null) return;
      
      // Загружаем аудио файл
      final url = await _audioService.uploadAudio(path);
      if (url == null) return;
      
      // Отправляем голосовое сообщение
      final authProvider = context.read<AuthProvider>();
      final currentUserId = authProvider.currentUser?.id;
      
      if (currentUserId != null) {
        context.read<ChatProvider>().sendMessage(
          chatId: widget.chatId,
          text: null,
          type: 'audio',
          mediaUrl: url,
          currentUserId: currentUserId,
        );
        _scrollToBottom();
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка отправки: $e')),
      );
    }
  }
  
  Future<void> _playAudio(String messageId, String url) async {
    if (_playingMessageId == messageId) {
      // Останавливаем воспроизведение
      await _audioService.stopPlaying();
      setState(() {
        _playingMessageId = null;
        _playingStates[messageId] = false;
      });
    } else {
      // Останавливаем предыдущее воспроизведение
      if (_playingMessageId != null) {
        await _audioService.stopPlaying();
        setState(() {
          _playingStates[_playingMessageId!] = false;
        });
      }
      
      // Начинаем новое воспроизведение
      String fullUrl;
      if (url.startsWith('http://') || url.startsWith('https://')) {
        fullUrl = url;
      } else {
        fullUrl = ImageUtils.getFullImageUrl(url);
      }
      await _audioService.playAudio(fullUrl);
      setState(() {
        _playingMessageId = messageId;
        _playingStates[messageId] = true;
      });
    }
  }
  
  String _formatDuration(int seconds) {
    final minutes = seconds ~/ 60;
    final secs = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  String _formatTime(int timestamp) {
    final date = DateTime.fromMillisecondsSinceEpoch(timestamp);
    return DateFormat('HH:mm').format(date);
  }

  String _getChatTitle() {
    if (_chat == null) return 'Чат';
    if (_chat!.isGroup) return _chat!.groupName ?? 'Группа';
    if (_otherUser != null) {
      return _otherUser!.displayName ?? 
             _otherUser!.email ?? 
             _otherUser!.phoneNumber ?? 
             'Пользователь';
    }
    return 'Пользователь';
  }

  Widget? _getChatAvatar() {
    if (_chat == null) return null;
    if (_chat!.isGroup) {
      return CircleAvatar(
        backgroundColor: Colors.blue,
        backgroundImage: _chat!.groupPhotoUrl != null && _chat!.groupPhotoUrl!.isNotEmpty
            ? NetworkImage(ImageUtils.getFullImageUrl(_chat!.groupPhotoUrl!))
            : null,
        child: _chat!.groupPhotoUrl == null || _chat!.groupPhotoUrl!.isEmpty
            ? const Icon(Icons.group, color: Colors.white)
            : null,
      );
    }
    if (_otherUser != null) {
      return CircleAvatar(
        backgroundColor: Colors.blue,
        backgroundImage: _otherUser!.photoUrl != null && _otherUser!.photoUrl!.isNotEmpty
            ? NetworkImage(ImageUtils.getFullImageUrl(_otherUser!.photoUrl))
            : null,
        child: _otherUser!.photoUrl == null || _otherUser!.photoUrl!.isEmpty
            ? Text(
                (_otherUser!.displayName?[0] ?? 'U').toUpperCase(),
                style: const TextStyle(color: Colors.white),
              )
            : null,
      );
    }
    return const CircleAvatar(
      backgroundColor: Colors.blue,
      child: Icon(Icons.person, color: Colors.white),
    );
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();
    final chatProvider = context.watch<ChatProvider>();
    final messages = chatProvider.getMessages(widget.chatId);
    final currentUserId = authProvider.currentUser?.id ?? '';

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: GestureDetector(
          onTap: () {
            if (_chat != null) {
              if (_chat!.isGroup) {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => GroupProfileScreen(chat: _chat!),
                  ),
                );
              } else if (_otherUser != null) {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => UserProfileScreen(user: _otherUser!),
                  ),
                );
              }
            }
          },
          child: Row(
            children: [
              _getChatAvatar() ?? const SizedBox.shrink(),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _getChatTitle(),
                      style: const TextStyle(fontSize: 16),
                    ),
                    if (_chat != null && !_chat!.isGroup && _otherUser != null)
                      Text(
                        _otherUser!.status ?? 'В сети',
                        style: const TextStyle(fontSize: 12),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          if (_chat != null && !kIsWeb)
            IconButton(
              icon: const Icon(Icons.phone),
              onPressed: () => _startCall(false),
              tooltip: _chat!.isGroup ? 'Групповой аудио звонок' : 'Аудио звонок',
            ),
          if (_chat != null && !kIsWeb)
            IconButton(
              icon: const Icon(Icons.videocam),
              onPressed: () => _startCall(true),
              tooltip: _chat!.isGroup ? 'Групповой видео звонок' : 'Видео звонок',
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: messages.isEmpty
                ? const Center(child: Text('Нет сообщений'))
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(16),
                    itemCount: messages.length,
                    itemBuilder: (context, index) {
                      final message = messages[index];
                      final isMe = message.senderId == currentUserId;

                      return Align(
                        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: isMe ? Colors.blue : Colors.grey[300],
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (message.text != null)
                                Text(
                                  message.text!,
                                  style: TextStyle(
                                    color: isMe ? Colors.white : Colors.black,
                                  ),
                                ),
                              if (message.mediaUrl != null)
                                message.type == 'audio'
                                    ? Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 16,
                                          vertical: 12,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.white.withOpacity(0.2),
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            IconButton(
                                              icon: Icon(
                                                _playingStates[message.id] == true
                                                    ? Icons.pause
                                                    : Icons.play_arrow,
                                                color: isMe ? Colors.white : Colors.blue,
                                              ),
                                              onPressed: () => _playAudio(
                                                message.id,
                                                message.mediaUrl!,
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Text(
                                              '🎤 Голосовое сообщение',
                                              style: TextStyle(
                                                color: isMe ? Colors.white : Colors.black,
                                              ),
                                            ),
                                          ],
                                        ),
                                      )
                                    : ClipRRect(
                                        borderRadius: BorderRadius.circular(8),
                                        child: Image.network(
                                          ImageUtils.getFullImageUrl(message.mediaUrl),
                                          width: 200,
                                          height: 200,
                                          fit: BoxFit.cover,
                                          errorBuilder: (context, error, stackTrace) {
                                            return Container(
                                              width: 200,
                                              height: 200,
                                              color: Colors.grey[300],
                                              child: const Icon(Icons.error),
                                            );
                                          },
                                        ),
                                      ),
                              const SizedBox(height: 4),
                              Text(
                                _formatTime(message.timestamp),
                                style: TextStyle(
                                  fontSize: 12,
                                  color: isMe
                                      ? Colors.white70
                                      : Colors.black54,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.grey[100],
              boxShadow: [
                BoxShadow(
                  color: Colors.grey.withOpacity(0.2),
                  spreadRadius: 1,
                  blurRadius: 5,
                ),
              ],
            ),
            child: _isRecording
                ? Container(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        const Icon(Icons.mic, color: Colors.red),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            _formatDuration(_recordingDuration),
                            style: const TextStyle(fontSize: 16),
                          ),
                        ),
                        TextButton(
                          onPressed: () => _stopRecording(false),
                          child: const Text('Отменить'),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: () => _stopRecording(true),
                          child: const Text('Отправить'),
                        ),
                      ],
                    ),
                  )
                : Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.image),
                        onPressed: _pickAndSendImage,
                        color: Colors.blue,
                        tooltip: 'Отправить изображение',
                      ),
                      if (!kIsWeb)
                        IconButton(
                          icon: const Icon(Icons.mic),
                          onPressed: _startRecording,
                          color: Colors.blue,
                          tooltip: 'Голосовое сообщение',
                        ),
                      Expanded(
                        child: TextField(
                          controller: _messageController,
                          decoration: const InputDecoration(
                            hintText: 'Введите сообщение...',
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                          ),
                          onSubmitted: (_) => _sendMessage(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.send),
                        onPressed: _sendMessage,
                        color: Colors.blue,
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
