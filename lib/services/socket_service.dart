import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import '../models/message.dart';
import '../config/api_config.dart';

class SocketService {
  IO.Socket? _socket;
  String? _userId;
  String? _token;
  final List<Function()> _onReconnectCallbacks = [];
  final Connectivity _connectivity = Connectivity();
  int _connectSeq = 0;
  int _pollingSendSeq = 0;
  
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
    final seq = ++_connectSeq;

    // Отключаем старое соединение, если есть
    if (_socket != null) {
      print('🔄 Disconnecting old socket connection...');
      _socket!.disconnect();
      _socket!.dispose();
      _socket = null;
    }

    print('🔌 ========== SOCKET CONNECTION ==========');
    final endpoint = ApiConfig.wsUrl;
    print('🔌 Connecting to $endpoint...');
    print('🔌 WS URL: $endpoint');
    print('🔌 Using HTTPS: ${endpoint.startsWith('https://')}');
    print('🔌 Will use WSS: ${endpoint.startsWith('https://')}');
    print('🔌 Token: ${_token?.substring(0, 20)}...');
    print('🔌 UserId: $_userId');
    
    // Socket.IO автоматически использует WSS при HTTPS URL
    // Для мобильных сетей важно использовать WebSocket как основной транспорт
    final extraHeaders = <String, String>{
      'Authorization': 'Bearer $_token',
    };

    // Decide transports based on current network type.
    // On some carrier networks (e.g. Megafon), WebSocket upgrades can be unreliable,
    // while polling works fine through HTTPS.
    _connectivity.checkConnectivity().then((results) {
      if (seq != _connectSeq) return;
      final isCellular = results.contains(ConnectivityResult.mobile) ||
          results.contains(ConnectivityResult.other);
      final transports = isCellular ? <String>['polling'] : <String>['polling', 'websocket'];
      print('📡 Socket transports: $transports (isCellular=$isCellular)');

      _probeSocketIoPolling(endpoint, extraHeaders, token: _token!, seq: seq);

      // Use options map to support flags not exposed by OptionBuilder in older socket_io_client.
      // For cellular networks we disable upgrade to websocket (polling-only).
      final options = <String, dynamic>{
        'path': '/socket.io/',
        'transports': transports,
        'autoConnect': false,
        'forceNew': true,
        'reconnection': true,
        'reconnectionAttempts': 20,
        'reconnectionDelay': 2000,
        'reconnectionDelayMax': 30000,
        'timeout': 60000,
        'extraHeaders': extraHeaders,
        // Ensure token reaches the server regardless of transport quirks.
        'query': {'token': _token},
        'auth': {'token': _token},
        if (isCellular) 'upgrade': false,
      };

      _socket = IO.io(endpoint, options);

      _attachListeners();
      try {
        _socket!.connect();
      } catch (e) {
        print('💥 Socket connect() threw: $e');
      }

      // Watchdog: if we don't get connect/connect_error within a short window, force reconnect.
      Future.delayed(const Duration(seconds: 8), () {
        if (seq != _connectSeq) return;
        final s = _socket;
        if (s == null) return;
        if (s.connected) return;
        print('⏱️ Socket watchdog: still not connected after 8s, forcing reconnect...');
        try {
          s.disconnect();
        } catch (_) {}
        try {
          s.connect();
        } catch (e) {
          print('💥 Socket watchdog connect() threw: $e');
        }
      });
    }).catchError((e) {
      if (seq != _connectSeq) return;
      print('⚠️ Failed to detect connectivity for socket, defaulting to polling: $e');
      _probeSocketIoPolling(endpoint, extraHeaders, token: _token!, seq: seq);
      final options = <String, dynamic>{
        'path': '/socket.io/',
        'transports': ['polling'],
        'autoConnect': false,
        'forceNew': true,
        'reconnection': true,
        'reconnectionAttempts': 20,
        'reconnectionDelay': 2000,
        'reconnectionDelayMax': 30000,
        'timeout': 60000,
        'extraHeaders': extraHeaders,
        'query': {'token': _token},
        'auth': {'token': _token},
        'upgrade': false,
      };
      _socket = IO.io(endpoint, options);
      _attachListeners();
      _socket!.connect();
    });
  }

  Future<void> _probeSocketIoPolling(
    String endpoint,
    Map<String, String> headers, {
    required String token,
    required int seq,
  }) async {
    try {
      final base = Uri.parse(endpoint);
      final handshakeUri = base.replace(
        path: '/socket.io/',
        queryParameters: <String, String>{
          ...base.queryParameters,
          'EIO': '4',
          'transport': 'polling',
          'token': token,
          't': DateTime.now().millisecondsSinceEpoch.toString(),
        },
      );
      final res = await http.get(handshakeUri, headers: headers)
          .timeout(const Duration(seconds: 8));
      final ct = res.headers['content-type'] ?? '';
      final bodyPrefix = res.body.length > 200 ? res.body.substring(0, 200) : res.body;
      print('🧪 Socket probe(seq=$seq): ${res.statusCode} ct=$ct body="$bodyPrefix"');

      // If the handshake looks correct, try the next steps the real client would do
      // so we can see whether auth fails vs the client just timing out.
      if (res.statusCode == 200 && res.body.startsWith('0{')) {
        final jsonStart = res.body.indexOf('{');
        final jsonEnd = res.body.lastIndexOf('}');
        if (jsonStart >= 0 && jsonEnd > jsonStart) {
          final handshakeJson = res.body.substring(jsonStart, jsonEnd + 1);
          final sid = (jsonDecode(handshakeJson) as Map<String, dynamic>)['sid'] as String?;
          if (sid != null && sid.isNotEmpty) {
            final postUri = base.replace(
              path: '/socket.io/',
              queryParameters: <String, String>{
                ...base.queryParameters,
                'EIO': '4',
                'transport': 'polling',
                'sid': sid,
                'token': token,
                't': DateTime.now().millisecondsSinceEpoch.toString(),
              },
            );
            final postRes = await http
                .post(
                  postUri,
                  headers: <String, String>{
                    ...headers,
                    'Content-Type': 'text/plain;charset=UTF-8',
                  },
                  body: '40',
                )
                .timeout(const Duration(seconds: 8));
            print('🧪 Socket probe(seq=$seq) POST 40: ${postRes.statusCode} body="${postRes.body}"');

            final pollUri = base.replace(
              path: '/socket.io/',
              queryParameters: <String, String>{
                ...base.queryParameters,
                'EIO': '4',
                'transport': 'polling',
                'sid': sid,
                'token': token,
                't': DateTime.now().millisecondsSinceEpoch.toString(),
              },
            );
            final pollRes = await http.get(pollUri, headers: headers).timeout(const Duration(seconds: 8));
            final pollPrefix = pollRes.body.length > 200 ? pollRes.body.substring(0, 200) : pollRes.body;
            print('🧪 Socket probe(seq=$seq) GET poll: ${pollRes.statusCode} body="$pollPrefix"');
          }
        }
      }
    } catch (e) {
      print('🧪 Socket probe(seq=$seq) failed: $e');
    }
  }

  void _attachListeners() {
    if (_socket == null) return;

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
      _maybeFallbackEndpoint('socket_error', error);
    });

    _socket!.onConnectError((error) {
      print('💥 Socket connect error: $error');
      _maybeFallbackEndpoint('socket_connect_error', error);
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

    // Extra low-level diagnostics
    _socket!.on('connect_error', (e) => print('💥 socket.io connect_error: $e'));
    _socket!.on('connect_timeout', (e) => print('💥 socket.io connect_timeout: $e'));
    _socket!.on('reconnect_attempt', (e) => print('🔄 socket.io reconnect_attempt: $e'));
    _socket!.on('reconnect_error', (e) => print('💥 socket.io reconnect_error: $e'));
    _socket!.on('reconnect_failed', (e) => print('💥 socket.io reconnect_failed: $e'));
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
    // 1) If socket is connected, use it (best UX).
    if (_socket != null && _socket!.connected) {
      _sendMessageNow(chatId, text, type, mediaUrl, replyToMessageId);
      return;
    }

    // 2) Socket isn't connected (common on some networks). Keep trying to connect,
    // but send the message right away via polling fallback so the chat works.
    print('⚠️ Socket not connected, sending via polling fallback (and reconnecting in background)...');
    _connect();

    final seq = ++_pollingSendSeq;
    // Fire-and-forget. UI is already updated optimistically in ChatProvider.
    unawaited(_sendMessageViaPollingFallback(
      chatId: chatId,
      text: text,
      type: type,
      mediaUrl: mediaUrl,
      replyToMessageId: replyToMessageId,
      seq: seq,
    ));
  }
  
  void _sendMessageNow(String chatId, String? text, String type, String? mediaUrl, String? replyToMessageId) {
    if (_socket == null || !_socket!.connected) return;
    
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

  Future<void> _sendMessageViaPollingFallback({
    required String chatId,
    String? text,
    required String type,
    String? mediaUrl,
    String? replyToMessageId,
    required int seq,
  }) async {
    final token = _token;
    if (token == null || token.isEmpty) {
      print('🛟 Polling fallback(seq=$seq): token missing, cannot send.');
      return;
    }

    final base = Uri.parse(ApiConfig.wsUrl);
    final headers = <String, String>{
      // Backend supports query token, but keep header too (best-effort).
      'Authorization': 'Bearer $token',
      'Accept': 'text/plain, application/json',
    };

    try {
      // 1) Engine.IO handshake (GET)
      final handshakeUri = base.replace(
        path: '/socket.io/',
        queryParameters: <String, String>{
          ...base.queryParameters,
          'EIO': '4',
          'transport': 'polling',
          'token': token,
          't': DateTime.now().millisecondsSinceEpoch.toString(),
        },
      );
      final hs = await http.get(handshakeUri, headers: headers).timeout(const Duration(seconds: 8));
      if (hs.statusCode != 200 || !hs.body.startsWith('0{')) {
        final prefix = hs.body.length > 160 ? hs.body.substring(0, 160) : hs.body;
        print('🛟 Polling fallback(seq=$seq): handshake failed ${hs.statusCode} body="$prefix"');
        return;
      }
      final jsonStart = hs.body.indexOf('{');
      final jsonEnd = hs.body.lastIndexOf('}');
      if (jsonStart < 0 || jsonEnd <= jsonStart) {
        print('🛟 Polling fallback(seq=$seq): handshake parse failed.');
        return;
      }
      final sid = (jsonDecode(hs.body.substring(jsonStart, jsonEnd + 1)) as Map<String, dynamic>)['sid'] as String?;
      if (sid == null || sid.isEmpty) {
        print('🛟 Polling fallback(seq=$seq): no sid in handshake.');
        return;
      }

      // 2) Socket.IO connect (POST "40")
      final pollUri = base.replace(
        path: '/socket.io/',
        queryParameters: <String, String>{
          ...base.queryParameters,
          'EIO': '4',
          'transport': 'polling',
          'sid': sid,
          'token': token,
          't': DateTime.now().millisecondsSinceEpoch.toString(),
        },
      );
      final c = await http
          .post(
            pollUri,
            headers: <String, String>{
              ...headers,
              'Content-Type': 'text/plain;charset=UTF-8',
            },
            body: '40',
          )
          .timeout(const Duration(seconds: 8));
      if (c.statusCode != 200) {
        final prefix = c.body.length > 160 ? c.body.substring(0, 160) : c.body;
        print('🛟 Polling fallback(seq=$seq): connect failed ${c.statusCode} body="$prefix"');
        return;
      }

      // 3) Read the connect ack (GET poll). If auth fails, server sends 44{"message":"Auth error"}.
      final ack = await http.get(pollUri, headers: headers).timeout(const Duration(seconds: 8));
      if (ack.statusCode != 200) {
        print('🛟 Polling fallback(seq=$seq): ack poll failed ${ack.statusCode}');
        return;
      }
      if (ack.body.startsWith('44')) {
        final prefix = ack.body.length > 160 ? ack.body.substring(0, 160) : ack.body;
        print('🛟 Polling fallback(seq=$seq): auth rejected: "$prefix"');
        return;
      }

      // Optional: join chat room so the sender also receives its own new_message.
      final joinPayload = jsonEncode(<dynamic>['join_chat', chatId]);
      await http
          .post(
            pollUri,
            headers: <String, String>{
              ...headers,
              'Content-Type': 'text/plain;charset=UTF-8',
            },
            body: '42$joinPayload',
          )
          .timeout(const Duration(seconds: 8));

      // 4) Emit send_message (POST "42[...]")
      final payload = jsonEncode(<dynamic>[
        'send_message',
        <String, dynamic>{
          'chatId': chatId,
          'text': text,
          'type': type,
          if (mediaUrl != null) 'mediaUrl': mediaUrl,
          if (replyToMessageId != null) 'replyToMessageId': replyToMessageId,
        }
      ]);
      final sendBody = '42$payload';
      final s = await http
          .post(
            pollUri,
            headers: <String, String>{
              ...headers,
              'Content-Type': 'text/plain;charset=UTF-8',
            },
            body: sendBody,
          )
          .timeout(const Duration(seconds: 8));
      if (s.statusCode != 200) {
        final prefix = s.body.length > 160 ? s.body.substring(0, 160) : s.body;
        print('🛟 Polling fallback(seq=$seq): send failed ${s.statusCode} body="$prefix"');
        return;
      }

      print('🛟 Polling fallback(seq=$seq): message sent.');
    } catch (e) {
      print('🛟 Polling fallback(seq=$seq): exception: $e');
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

  void _maybeFallbackEndpoint(String source, Object? error) {
    // Best-effort: if the primary domain is blocked/broken on the current network,
    // switching to the fallback endpoint can restore connectivity.
    if (ApiConfig.isUsingFallback) return;
    ApiConfig.rotateToNextBaseUrl(reason: source).then((next) {
      print('🛟 SocketService: endpoint switched to $next after $source: $error');
    }).catchError((_) {});
  }
}
