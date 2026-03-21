import 'package:socket_io_client/socket_io_client.dart' as IO;
import '../models/message.dart';
import '../config/api_config.dart';

class SocketService {
  IO.Socket? _socket;
  String? _userId;
  String? _token;
  final List<Function()> _onReconnectCallbacks = [];
  
  IO.Socket? get socket => _socket;
  
  // Регистрация callback для переустановки слушателей при переподключении
  void onReconnect(Function() callback) {
    if (!_onReconnectCallbacks.contains(callback)) {
      _onReconnectCallbacks.add(callback);
      print('📝 Registered reconnect callback (total: ${_onReconnectCallbacks.length})');
    }
  }
  
  void removeReconnectCallback(Function() callback) {
    _onReconnectCallbacks.remove(callback);
    print('🗑️ Removed reconnect callback (remaining: ${_onReconnectCallbacks.length})');
  }

  void initialize(String userId, String token) {
    // Если уже подключены с теми же данными, не переподключаемся
    if (_socket != null && _socket!.connected && _userId == userId && _token == token) {
      print('✅ Socket already connected with same credentials, skipping reconnection');
      return;
    }
    
    _userId = userId;
    _token = token;
    _connect();
  }

  void _connect() {
    if (_userId == null || _token == null) {
      print('⚠️ Cannot connect: userId or token is null');
      return;
    }

    // Отключаем старое соединение, если есть
    if (_socket != null) {
      print('🔄 Disconnecting old socket connection...');
      _socket!.disconnect();
      _socket!.dispose();
      _socket = null;
    }

    print('🔌 Connecting to ${ApiConfig.wsUrl}...');
    print('🔌 Token: ${_token?.substring(0, 20)}...');
    print('🔌 UserId: $_userId');
    
    _socket = IO.io(
      ApiConfig.wsUrl,
      IO.OptionBuilder()
          .setTransports(['websocket', 'polling']) // Добавляем polling для надежности на Android
          .enableAutoConnect()
          .setAuth({'token': _token}) // Используем setAuth для Android
          .setExtraHeaders({'Authorization': 'Bearer $_token'}) // Также в headers для совместимости
          .setQuery({'token': _token}) // И в query параметрах
          .enableReconnection()
          .setReconnectionAttempts(5)
          .setReconnectionDelay(1000)
          .setReconnectionDelayMax(5000)
          .build(),
    );

    _socket!.onConnect((_) {
      print('✅ Socket connected successfully');
      print('✅ Socket ID: ${_socket!.id}');
      // Переустанавливаем слушатели при переподключении
      if (_newMessageCallback != null) {
        print('🔄 Re-setting up new_message listener after reconnect');
        _setupNewMessageListener();
      }
      // Вызываем все зарегистрированные callback'и при переподключении
      print('🔄 Calling ${_onReconnectCallbacks.length} reconnect callbacks...');
      for (final callback in _onReconnectCallbacks) {
        try {
          callback();
        } catch (e) {
          print('❌ Error in reconnect callback: $e');
        }
      }
    });

    _socket!.onDisconnect((reason) {
      print('❌ Socket disconnected: $reason');
      // Автоматическое переподключение при отключении
      if (_userId != null && _token != null) {
        print('🔄 Attempting to reconnect...');
        Future.delayed(const Duration(seconds: 2), () {
          if (_socket != null && !_socket!.connected) {
            _connect();
          }
        });
      }
    });

    _socket!.onError((error) {
      print('💥 Socket error: $error');
    });

    _socket!.onConnectError((error) {
      print('💥 Socket connect error: $error');
      // Повторная попытка подключения при ошибке
      if (_userId != null && _token != null) {
        Future.delayed(const Duration(seconds: 3), () {
          if (_socket != null && !_socket!.connected) {
            print('🔄 Retrying connection after error...');
            _connect();
          }
        });
      }
    });
    
    // Добавляем обработчик для проверки подключения
    _socket!.on('connect', (_) {
      print('✅ Socket connect event received');
      print('✅ Socket ID: ${_socket!.id}');
      print('✅ Socket connected status: ${_socket!.connected}');
    });
  }
  
  bool get isConnected => _socket != null && _socket!.connected;
  
  void waitForConnection(Function() callback) {
    if (_socket == null) {
      _connect();
    }
    
    if (_socket != null && _socket!.connected) {
      callback();
    } else {
      // Используем once для одноразового слушателя
      _socket?.once('connect', (_) {
        callback();
      });
    }
  }

  void joinChat(String chatId) {
    if (_socket == null) {
      print('⚠️ Socket is null, reconnecting...');
      _connect();
      // Ждем подключения и затем присоединяемся
      waitForConnection(() {
        print('🔗 Joining chat after reconnect: $chatId');
        _socket?.emit('join_chat', chatId);
      });
      return;
    }
    
    if (!_socket!.connected) {
      print('⚠️ Socket not connected, waiting for connection...');
      waitForConnection(() {
        print('🔗 Joining chat after connection: $chatId');
        _socket?.emit('join_chat', chatId);
      });
      return;
    }
    
    print('🔗 Joining chat: $chatId');
    _socket?.emit('join_chat', chatId);
  }

  void sendMessage({
    required String chatId,
    String? text,
    required String type,
    String? mediaUrl,
    String? replyToMessageId,
  }) {
    if (_socket == null) {
      print('⚠️ Socket is null, reconnecting...');
      _connect();
      // Ждем подключения и затем отправляем
      waitForConnection(() {
        _sendMessageNow(chatId, text, type, mediaUrl, replyToMessageId);
      });
      return;
    }
    
    if (!_socket!.connected) {
      print('⚠️ Socket not connected, waiting for connection...');
      waitForConnection(() {
        _sendMessageNow(chatId, text, type, mediaUrl, replyToMessageId);
      });
      return;
    }
    
    _sendMessageNow(chatId, text, type, mediaUrl, replyToMessageId);
  }
  
  void _sendMessageNow(String chatId, String? text, String type, String? mediaUrl, String? replyToMessageId) {
    if (_socket == null || !_socket!.connected) {
      print('⚠️ Socket not connected, cannot send message');
      // Пытаемся переподключиться
      _connect();
      waitForConnection(() {
        _sendMessageNow(chatId, text, type, mediaUrl, replyToMessageId);
      });
      return;
    }
    
    final messageData = {
      'chatId': chatId,
      'text': text,
      'type': type,
      if (mediaUrl != null) 'mediaUrl': mediaUrl,
      if (replyToMessageId != null) 'replyToMessageId': replyToMessageId,
    };
    
    print('📤 Emitting send_message: $messageData');
    print('📤 Socket connected: ${_socket!.connected}');
    print('📤 Socket ID: ${_socket!.id}');
    
    try {
      _socket!.emit('send_message', messageData);
      print('✅ Message emitted successfully');
    } catch (e) {
      print('💥 Error emitting message: $e');
    }
  }

  void callUser({
    required String to,
    required String channelName,
    required String type, // 'audio' or 'video'
  }) {
    if (_socket == null || !_socket!.connected) {
      print('⚠️ Socket not connected, cannot make call');
      _connect();
      waitForConnection(() {
        callUser(to: to, channelName: channelName, type: type);
      });
      return;
    }
    
    final callData = {
      'to': to,
      'channelName': channelName,
      'type': type,
    };
    
    print('📞 Emitting call_user: $callData');
    print('📞 Socket connected: ${_socket!.connected}');
    
    try {
      _socket!.emit('call_user', callData);
      print('✅ Call event emitted successfully');
    } catch (e) {
      print('💥 Error emitting call: $e');
    }
  }

  void acceptCall({
    required String chatId,
    required String from,
  }) {
    _socket?.emit('call_accepted', {
      'chatId': chatId,
      'from': from,
    });
  }

  void groupCall({
    required String chatId,
    required String channelName,
    required String type,
    List<String>? participants,
  }) {
    if (_socket == null || !_socket!.connected) {
      print('⚠️ Socket not connected, cannot make group call');
      _connect();
      waitForConnection(() {
        groupCall(chatId: chatId, channelName: channelName, type: type, participants: participants);
      });
      return;
    }
    
    final callData = {
      'chatId': chatId,
      'channelName': channelName,
      'type': type,
      'participants': participants,
    };
    
    print('📞 Emitting group_call: $callData');
    print('📞 Socket connected: ${_socket!.connected}');
    
    try {
      _socket!.emit('group_call', callData);
      print('✅ Group call event emitted successfully');
    } catch (e) {
      print('💥 Error emitting group call: $e');
    }
  }

  // Listeners
  Function(Message)? _newMessageCallback;
  
  void onNewMessage(Function(Message) callback) {
    _newMessageCallback = callback;
    _setupNewMessageListener();
  }
  
  void _setupNewMessageListener() {
    if (_socket == null || !_socket!.connected) {
      print('⚠️ Cannot setup new_message listener: socket is null or not connected');
      return;
    }
    
    // Удаляем старый слушатель перед добавлением нового
    _socket!.off('new_message');
    
    print('🎧 Setting up new_message listener on socket');
    _socket!.on('new_message', (data) {
      print('📨 Socket received new_message event: $data');
      if (_newMessageCallback != null) {
        try {
          final message = Message.fromJson(Map<String, dynamic>.from(data));
          _newMessageCallback!(message);
        } catch (e) {
          print('💥 Error parsing new_message: $e');
          print('💥 Data: $data');
        }
      } else {
        print('⚠️ new_message callback is null, ignoring message');
      }
    });
  }

  void onIncomingCall(Function(Map<String, dynamic>) callback) {
    _socket?.on('incoming_call', (data) {
      callback(Map<String, dynamic>.from(data));
    });
  }

  void onCallAccepted(Function(Map<String, dynamic>) callback) {
    _socket?.on('call_accepted', (data) {
      callback(Map<String, dynamic>.from(data));
    });
  }

  void onGroupCall(Function(Map<String, dynamic>) callback) {
    _socket?.on('group_call', (data) {
      callback(Map<String, dynamic>.from(data));
    });
  }

  void onIncomingGroupCall(Function(Map<String, dynamic>) callback) {
    _socket?.on('incoming_group_call', (data) {
      callback(Map<String, dynamic>.from(data));
    });
  }

  void onChatCreated(Function(Map<String, dynamic>) callback) {
    _socket?.on('chat_created', (data) {
      callback(Map<String, dynamic>.from(data));
    });
  }

  void onUserStatusChanged(Function(Map<String, dynamic>) callback) {
    _socket?.on('user_status_changed', (data) {
      callback(Map<String, dynamic>.from(data));
    });
  }

  void onCallOffer(Function(Map<String, dynamic>) callback) {
    _socket?.on('call-offer', (data) {
      callback(Map<String, dynamic>.from(data));
    });
  }

  void onCallAnswer(Function(Map<String, dynamic>) callback) {
    _socket?.on('call-answer', (data) {
      callback(Map<String, dynamic>.from(data));
    });
  }

  void onIceCandidate(Function(Map<String, dynamic>) callback) {
    _socket?.on('ice-candidate', (data) {
      callback(Map<String, dynamic>.from(data));
    });
  }

  void disconnect() {
    _socket?.disconnect();
    _socket = null;
  }
}
