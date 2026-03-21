import 'package:flutter/foundation.dart';
import '../models/chat.dart';
import '../models/message.dart';
import '../models/user.dart';
import '../services/api_service.dart';
import '../services/socket_service.dart';
import '../services/auth_service.dart';

class ChatProvider with ChangeNotifier {
  ApiService? _apiService;
  SocketService? _socketService;
  Function()? _reconnectCallbackRef;
  
  void setSocketService(SocketService socketService) {
    // Если это тот же socketService, не делаем ничего
    if (_socketService == socketService) {
      print('✅ SocketService already set, skipping');
      return;
    }
    
    // Если socketService изменился, сбрасываем флаг установки слушателей
    _listenersSetup = false;
    // Удаляем старый callback, если был
    if (_reconnectCallbackRef != null && _socketService != null) {
      _socketService!.removeReconnectCallback(_reconnectCallbackRef!);
    }
    
    _socketService = socketService;
    // Создаем и сохраняем callback для переустановки слушателей при переподключении
    _reconnectCallbackRef = () {
      print('🔄 Socket reconnected, re-setting up listeners...');
      if (_socketService != null && _socketService!.isConnected) {
        setupSocketListeners(force: true);
      }
    };
    // Регистрируем callback для переустановки слушателей при переподключении
    socketService.onReconnect(_reconnectCallbackRef!);
    print('✅ SocketService set and reconnect callback registered');
  }
  
  void setApiService(ApiService apiService) {
    _apiService = apiService;
  }
  
  SocketService? get socketService => _socketService;

  List<Chat> _chats = [];
  Map<String, List<Message>> _messages = {};
  Map<String, User> _userCache = {}; // Кэш пользователей
  Map<String, int> _unreadCounts = {}; // Количество непрочитанных сообщений по chatId
  String? _currentOpenChatId; // ID открытого в данный момент чата
  String? _currentUserId; // ID текущего пользователя
  bool _isLoading = false;

  List<Chat> get chats => _chats;
  bool get isLoading => _isLoading;
  
  // Установить ID текущего пользователя
  void setCurrentUserId(String userId) {
    print('👤 Setting current user ID: $userId');
    _currentUserId = userId;
  }
  
  // Получить количество непрочитанных сообщений для чата
  int getUnreadCount(String chatId) {
    final count = _unreadCounts[chatId] ?? 0;
    return count;
  }
  
  // Получить все счетчики непрочитанных (для отладки)
  Map<String, int> get unreadCounts => Map.unmodifiable(_unreadCounts);
  
  // Установить текущий открытый чат
  void setCurrentChat(String? chatId) {
    final oldChatId = _currentOpenChatId;
    _currentOpenChatId = chatId;
    if (chatId != null) {
      print('📖 Setting current chat to: $chatId (old: $oldChatId)');
      markAsRead(chatId);
    } else {
      print('📖 Clearing current chat (old: $oldChatId)');
    }
  }
  
  // Отметить чат как прочитанный
  void markAsRead(String chatId) {
    final oldCount = _unreadCounts[chatId] ?? 0;
    if (oldCount > 0) {
      _unreadCounts[chatId] = 0;
      print('✅ Marked chat $chatId as read (was $oldCount unread)');
      notifyListeners();
    }
  }
  
  // Получить пользователя из кэша или загрузить
  Future<User?> getUser(String userId) async {
    // Проверяем кэш
    if (_userCache.containsKey(userId)) {
      print('📦 User from cache: $userId');
      return _userCache[userId];
    }
    
    // Загружаем пользователя
    if (_apiService == null) {
      print('⚠️ ApiService is null, cannot load user');
      return null;
    }
    
    try {
      final user = await _apiService!.getUser(userId);
      if (user != null) {
        _userCache[userId] = user;
        print('✅ User loaded and cached: $userId');
      }
      return user;
    } catch (e) {
      print('❌ Error loading user: $e');
      return null;
    }
  }

  List<Message> getMessages(String chatId) {
    return _messages[chatId] ?? [];
  }

  Future<void> loadChats() async {
    if (_apiService == null) {
      print('⚠️ ApiService is null, cannot load chats');
      return;
    }
    
    // Убеждаемся что токен установлен перед запросом
    final authService = AuthService();
    final token = await authService.getToken();
    if (token != null) {
      _apiService!.setToken(token);
    }
    
    _isLoading = true;
    notifyListeners();

    try {
      final loadedChats = await _apiService!.getChats();
      
      // Удаляем дубликаты по ID чата
      final Map<String, Chat> uniqueChats = {};
      for (final chat in loadedChats) {
        if (!uniqueChats.containsKey(chat.id)) {
          uniqueChats[chat.id] = chat;
        } else {
          // Если чат уже есть, берем тот, у которого более свежее последнее сообщение
          final existing = uniqueChats[chat.id]!;
          if ((chat.lastMessageTimestamp ?? 0) > (existing.lastMessageTimestamp ?? 0)) {
            uniqueChats[chat.id] = chat;
          }
        }
      }
      
      _chats = uniqueChats.values.toList();
      // Сортируем по времени последнего сообщения (от новых к старым)
      _chats.sort((a, b) => (b.lastMessageTimestamp ?? 0).compareTo(a.lastMessageTimestamp ?? 0));
      
      print('✅ Loaded ${_chats.length} unique chats (removed ${loadedChats.length - _chats.length} duplicates)');
      
      // Присоединяемся ко всем чатам через socket для получения сообщений
      if (_socketService != null && _socketService!.isConnected) {
        print('🔗 Joining all ${_chats.length} chats...');
        for (final chat in _chats) {
          joinChat(chat.id);
        }
      } else if (_socketService != null) {
        // Если socket еще не подключен, ждем подключения и затем присоединяемся
        print('⏳ Socket not connected yet, will join chats after connection...');
        _socketService!.waitForConnection(() {
          print('🔗 Socket connected, joining all ${_chats.length} chats...');
          for (final chat in _chats) {
            joinChat(chat.id);
          }
        });
      }
      
      _isLoading = false;
      notifyListeners();
    } catch (e) {
      print('❌ Error loading chats: $e');
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> loadMessages(String chatId) async {
    if (_apiService == null) {
      print('⚠️ ApiService is null, cannot load messages');
      return;
    }
    
    try {
      // Убеждаемся что токен установлен перед запросом
      final authService = AuthService();
      final token = await authService.getToken();
      if (token != null) {
        _apiService!.setToken(token);
      }
      
      print('📥 Loading messages for chat: $chatId');
      final messages = await _apiService!.getChatMessages(chatId);
      print('📥 Loaded ${messages.length} messages from server');
      
      // Сообщения приходят в порядке DESC (от новых к старым), переворачиваем
      final sortedMessages = messages.reversed.toList();
      
      // Объединяем с существующими сообщениями, избегая дубликатов
      if (!_messages.containsKey(chatId)) {
        _messages[chatId] = [];
      }
      
      // Создаем Set для быстрой проверки существующих ID
      final existingIds = _messages[chatId]!.map((m) => m.id).toSet();
      
      // Добавляем только новые сообщения
      // При загрузке старых сообщений из API не увеличиваем счетчик непрочитанных
      for (final message in sortedMessages) {
        if (!existingIds.contains(message.id)) {
          _messages[chatId]!.add(message);
        }
      }
      
      // Сортируем по времени (от старых к новым)
      _messages[chatId]!.sort((a, b) => a.timestamp.compareTo(b.timestamp));
      
      print('📥 Total messages in chat now: ${_messages[chatId]!.length}');
      // При загрузке сообщений не увеличиваем счетчик непрочитанных, так как это старые сообщения
      notifyListeners();
    } catch (e) {
      print('❌ Error loading messages: $e');
    }
  }

  void sendMessage({
    required String chatId,
    String? text,
    required String type,
    String? mediaUrl,
    String? replyToMessageId,
    String? currentUserId,
  }) {
    // Оптимистичное обновление - сразу показываем сообщение в UI
    if (currentUserId != null) {
      final tempMessage = Message(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        chatId: chatId,
        senderId: currentUserId,
        text: text,
        type: type,
        mediaUrl: mediaUrl,
        timestamp: DateTime.now().millisecondsSinceEpoch,
        isRead: false,
        replyToMessageId: replyToMessageId,
      );
      
      print('💬 Adding optimistic message: ${tempMessage.text ?? tempMessage.type}');
      // Добавляем временное сообщение
      addMessage(tempMessage);
    }
    
    // Отправляем через Socket
    if (_socketService != null) {
      _socketService!.sendMessage(
        chatId: chatId,
        text: text,
        type: type,
        mediaUrl: mediaUrl,
        replyToMessageId: replyToMessageId,
      );
    } else {
      print('⚠️ SocketService is null, cannot send message');
    }
  }

  void addMessage(Message message) {
    if (!_messages.containsKey(message.chatId)) {
      _messages[message.chatId] = [];
    }
    
    // Проверяем, нет ли уже такого сообщения (чтобы избежать дубликатов)
    // Сравниваем по ID или по комбинации chatId + timestamp + senderId + text
    final existingIndex = _messages[message.chatId]!.indexWhere((m) {
      // Если ID совпадает - это точно то же сообщение
      if (m.id == message.id) return true;
      // Если временное сообщение (оптимистичное) и пришло с сервера с тем же текстом и временем
      // Проверяем по senderId, text и близкому timestamp (в пределах 10 секунд)
      if (m.senderId == message.senderId && 
          m.text == message.text && 
          m.chatId == message.chatId &&
          (m.timestamp - message.timestamp).abs() < 10000) {
        return true;
      }
      return false;
    });
    
    if (existingIndex == -1) {
      // Добавляем новое сообщение
      _messages[message.chatId]!.add(message);
      // Сортируем по времени (от старых к новым)
      _messages[message.chatId]!.sort((a, b) => a.timestamp.compareTo(b.timestamp));
      print('💬 New message added to chat ${message.chatId}: ${message.text ?? message.type} (total: ${_messages[message.chatId]!.length})');
      
      // Увеличиваем счетчик непрочитанных, если сообщение не от текущего пользователя и чат не открыт
      print('🔍 Checking unread count:');
      print('   currentUserId=$_currentUserId');
      print('   senderId=${message.senderId}');
      print('   currentOpenChatId=$_currentOpenChatId');
      print('   chatId=${message.chatId}');
      print('   isSameSender=${message.senderId == _currentUserId}');
      print('   isChatOpen=${_currentOpenChatId == message.chatId}');
      
      final shouldIncrease = _currentUserId != null && 
          message.senderId != _currentUserId && 
          _currentOpenChatId != message.chatId;
      
      if (shouldIncrease) {
        _unreadCounts[message.chatId] = (_unreadCounts[message.chatId] ?? 0) + 1;
        print('🔴✅ Unread count INCREASED for chat ${message.chatId}: ${_unreadCounts[message.chatId]}');
        notifyListeners(); // Явно обновляем UI
      } else {
        print('⚠️❌ Unread count NOT increased:');
        print('   currentUserId is null: ${_currentUserId == null}');
        print('   same sender: ${message.senderId == _currentUserId}');
        print('   chat is open: ${_currentOpenChatId == message.chatId}');
      }
    } else {
      // Обновляем существующее сообщение (заменяем оптимистичное на реальное с сервера)
      final oldMessage = _messages[message.chatId]![existingIndex];
      final wasOptimistic = oldMessage.id != message.id; // Проверяем, было ли это оптимистичное сообщение
      _messages[message.chatId]![existingIndex] = message;
      // Пересортировываем на случай изменения timestamp
      _messages[message.chatId]!.sort((a, b) => a.timestamp.compareTo(b.timestamp));
      print('💬 Message updated in chat ${message.chatId}: ${message.text ?? message.type} (old id: ${oldMessage.id}, new id: ${message.id})');
      
      // Если это было оптимистичное сообщение от текущего пользователя, счетчик не увеличиваем
      // Но если это новое сообщение от другого пользователя, которое пришло с сервера, увеличиваем счетчик
      print('🔍 Checking unread for updated message:');
      print('   wasOptimistic=$wasOptimistic');
      print('   currentUserId=$_currentUserId');
      print('   senderId=${message.senderId}');
      print('   currentOpenChatId=$_currentOpenChatId');
      print('   chatId=${message.chatId}');
      
      if (wasOptimistic && _currentUserId != null && 
          message.senderId != _currentUserId && 
          _currentOpenChatId != message.chatId) {
        _unreadCounts[message.chatId] = (_unreadCounts[message.chatId] ?? 0) + 1;
        print('🔴✅ Unread count INCREASED for updated message in chat ${message.chatId}: ${_unreadCounts[message.chatId]}');
        notifyListeners(); // Явно обновляем UI
      } else if (!wasOptimistic && _currentUserId != null && 
          message.senderId != _currentUserId && 
          _currentOpenChatId != message.chatId) {
        // Если это не оптимистичное сообщение, но от другого пользователя и чат не открыт - увеличиваем счетчик
        _unreadCounts[message.chatId] = (_unreadCounts[message.chatId] ?? 0) + 1;
        print('🔴✅ Unread count INCREASED for non-optimistic message in chat ${message.chatId}: ${_unreadCounts[message.chatId]}');
        notifyListeners(); // Явно обновляем UI
      } else {
        print('⚠️❌ Unread count NOT increased for updated message');
      }
    }
    
    // Обновляем последнее сообщение в чате
    final chatIndex = _chats.indexWhere((c) => c.id == message.chatId);
    if (chatIndex != -1) {
      _chats[chatIndex] = Chat(
        id: _chats[chatIndex].id,
        participants: _chats[chatIndex].participants,
        lastMessage: message.text ?? message.type,
        lastMessageTimestamp: message.timestamp,
        isGroup: _chats[chatIndex].isGroup,
        groupName: _chats[chatIndex].groupName,
        groupAdminId: _chats[chatIndex].groupAdminId,
        groupPhotoUrl: _chats[chatIndex].groupPhotoUrl,
      );
      // Перемещаем чат в начало списка (самый свежий)
      final chat = _chats.removeAt(chatIndex);
      _chats.insert(0, chat);
    }
    
    // Всегда вызываем notifyListeners для обновления UI
    print('📢 Notifying listeners after addMessage');
    print('📊 Current unread counts: $_unreadCounts');
    print('📊 Unread counts entries: ${_unreadCounts.entries.map((e) => '${e.key}:${e.value}').join(', ')}');
    notifyListeners();
  }

  Future<Chat?> createChat(List<String> participants) async {
    if (_apiService == null) {
      print('⚠️ ApiService is null, cannot create chat');
      return null;
    }
    
    try {
      final chat = await _apiService!.createChat(participants);
      if (chat != null) {
        _chats.add(chat);
        notifyListeners();
      }
      return chat;
    } catch (e) {
      return null;
    }
  }

  Future<Chat?> createGroupChat(
      List<String> participants, String groupName, String adminId) async {
    if (_apiService == null) {
      print('⚠️ ApiService is null, cannot create group chat');
      return null;
    }
    
    try {
      final chat =
          await _apiService!.createGroupChat(participants, groupName, adminId);
      if (chat != null) {
        _chats.add(chat);
        notifyListeners();
      }
      return chat;
    } catch (e) {
      return null;
    }
  }

  bool _listenersSetup = false;
  
  void setupSocketListeners({bool force = false}) {
    if (_socketService == null) {
      print('⚠️ SocketService is null, cannot setup listeners');
      return;
    }
    
    if (!_socketService!.isConnected) {
      print('⚠️ Socket not connected, cannot setup listeners');
      return;
    }
    
    if (_listenersSetup && !force) {
      print('⚠️ Socket listeners already setup, skipping (use force=true to re-setup)');
      return;
    }
    
    print('🎧 Setting up socket listeners...');
    print('🎧 Socket connected: ${_socketService!.isConnected}');
    print('🎧 Socket ID: ${_socketService!.socket?.id}');
    print('🎧 Current user ID: $_currentUserId');
    print('🎧 Force re-setup: $force');
    
    // Удаляем старые слушатели перед добавлением новых
    _socketService!.socket?.off('new_message');
    _socketService!.socket?.off('chat_created');
    
    _socketService!.onNewMessage((message) {
      print('📨 New message received from server: ${message.id}, chatId: ${message.chatId}, senderId: ${message.senderId}, text: ${message.text}');
      print('📨 Current user ID: $_currentUserId, Current open chat: $_currentOpenChatId');
      print('📨 Is from current user: ${message.senderId == _currentUserId}');
      print('📨 Is chat open: ${_currentOpenChatId == message.chatId}');
      addMessage(message);
    });

    _socketService!.onChatCreated((data) {
      print('💬 Chat created event received');
      final chat = Chat.fromJson(data);
      _chats.add(chat);
      notifyListeners();
    });
    
    _listenersSetup = true;
    print('✅ Socket listeners setup completed');
  }
  
  void joinChat(String chatId) {
    if (_socketService == null) {
      print('⚠️ SocketService is null, cannot join chat');
      return;
    }
    print('🔗 ChatProvider: Joining chat $chatId');
    _socketService!.joinChat(chatId);
  }
}
