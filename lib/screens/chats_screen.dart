import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../providers/auth_provider.dart';
import '../providers/chat_provider.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../utils/image_utils.dart';
import '../widgets/adaptive_avatar.dart';
import 'chat_screen.dart';
import 'profile_screen.dart';
import 'create_chat_screen.dart';
import 'group_profile_screen.dart';

class ChatsScreen extends StatefulWidget {
  const ChatsScreen({super.key});

  @override
  State<ChatsScreen> createState() => _ChatsScreenState();
}

class _ChatsScreenState extends State<ChatsScreen> {
  final Map<String, Future<Map<String, String>?>> _userInfoFutures =
      <String, Future<Map<String, String>?>>{};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final authProvider = context.read<AuthProvider>();
      final chatProvider = context.read<ChatProvider>();
      
      // Убеждаемся, что SocketService и ApiService переданы в ChatProvider
      chatProvider.setSocketService(authProvider.socketService);
      chatProvider.setApiService(authProvider.apiService);
      
      // Устанавливаем текущего пользователя для отслеживания непрочитанных сообщений
      if (authProvider.currentUser != null) {
        chatProvider.setCurrentUserId(authProvider.currentUser!.id);
      }
      
      // Устанавливаем слушатели после подключения socket
      final socketService = authProvider.socketService;
      if (socketService.isConnected) {
        print('✅ Socket already connected, setting up listeners immediately');
        chatProvider.setupSocketListeners(force: true);
      } else {
        print('⏳ Socket not connected yet, waiting for connection...');
        // Ждем подключения socket перед установкой слушателей
        socketService.waitForConnection(() {
          print('✅ Socket connected, setting up listeners now');
          chatProvider.setupSocketListeners(force: true);
        });
      }
      
      chatProvider.loadChats();
    });
  }

  Future<Map<String, String>?> _loadUserInfo(String userId) async {
    try {
      final chatProvider = context.read<ChatProvider>();
      
      print('🔍 Loading user info for userId: $userId');
      final user = await chatProvider.getUser(userId);
      
      if (user != null) {
        print('✅ User loaded: ${user.displayName ?? user.email ?? user.phoneNumber}');
        print('📸 Photo URL: ${user.photoUrl}');
        return {
          'name': user.displayName ?? user.email ?? user.phoneNumber ?? 'Пользователь',
          'photo': user.photoUrl ?? '',
        };
      } else {
        print('❌ User not found for userId: $userId');
      }
    } catch (e, stackTrace) {
      print('❌ Error loading user info: $e');
      print('❌ Stack trace: $stackTrace');
    }
    return null;
  }

  Future<Map<String, String>?> _getUserInfoFuture(String userId) {
    return _userInfoFutures.putIfAbsent(userId, () => _loadUserInfo(userId));
  }

  String _formatTimestamp(int? timestamp) {
    if (timestamp == null) return '';
    final date = DateTime.fromMillisecondsSinceEpoch(timestamp);
    final now = DateTime.now();
    final difference = now.difference(date);

    try {
      if (difference.inDays == 0) {
        return DateFormat('HH:mm').format(date);
      } else if (difference.inDays == 1) {
        return 'Вчера';
      } else if (difference.inDays < 7) {
        // Используем английские названия дней недели на веб, если русские недоступны
        try {
          return DateFormat('EEEE', 'ru').format(date);
        } catch (e) {
          return DateFormat('EEEE').format(date);
        }
      } else {
        return DateFormat('dd.MM.yyyy').format(date);
      }
    } catch (e) {
      // Fallback форматирование без локализации
      if (difference.inDays == 0) {
        return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
      } else if (difference.inDays == 1) {
        return 'Вчера';
      } else {
        return '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year}';
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();
    final chatProvider = context.watch<ChatProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Чаты'),
        actions: [
          IconButton(
            icon: const Icon(Icons.person),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ProfileScreen()),
              );
            },
          ),
        ],
      ),
      body: chatProvider.isLoading
          ? const Center(child: CircularProgressIndicator())
          : chatProvider.chats.isEmpty
              ? const Center(
                  child: Text('Нет чатов'),
                )
              : RefreshIndicator(
                  onRefresh: () => chatProvider.loadChats(),
                  child: Consumer<ChatProvider>(
                    builder: (context, chatProvider, _) {
                      // Используем ключ, который изменяется при изменении счетчиков непрочитанных
                      final unreadCountsKey = chatProvider.unreadCounts.entries
                          .where((e) => e.value > 0)
                          .map((e) => '${e.key}:${e.value}')
                          .join(',');
                      
                      print('🔄 Consumer rebuilding chats list, unreadCountsKey: $unreadCountsKey');
                      print('🔄 Total chats: ${chatProvider.chats.length}');
                      
                      return ListView.builder(
                        key: ValueKey('chats_list_${chatProvider.chats.length}_$unreadCountsKey'),
                        itemCount: chatProvider.chats.length,
                        itemBuilder: (context, index) {
                          final chat = chatProvider.chats[index];
                          final currentUserId = authProvider.currentUser?.id ?? '';
                          final otherParticipant = chat.participants
                              .firstWhere((id) => id != currentUserId,
                                  orElse: () => '');
                          
                          // Получаем актуальный счетчик непрочитанных для этого чата
                          final unreadCount = chatProvider.getUnreadCount(chat.id);

                          return FutureBuilder<Map<String, String>?>(
                            key: ValueKey('chat_${chat.id}_unread_$unreadCount'),
                            future: !chat.isGroup && otherParticipant.isNotEmpty
                                ? _getUserInfoFuture(otherParticipant)
                                : Future.value(null),
                            builder: (context, snapshot) {
                              final userInfo = snapshot.data;
                              final displayName = chat.isGroup
                                  ? (chat.groupName ?? 'Группа')
                                  : (userInfo?['name'] ?? 'Пользователь');
                              final photoUrl = userInfo?['photo'];
                              
                              // Получаем актуальный счетчик непрочитанных для этого чата (внутри builder для обновления)
                              final currentUnreadCount = chatProvider.getUnreadCount(chat.id);
                              
                              return ListTile(
                                    leading: AdaptiveAvatar(
                                      photoUrl: chat.isGroup ? chat.groupPhotoUrl : photoUrl,
                                      radius: 20,
                                      backgroundColor: Colors.blue,
                                      fallbackChild: chat.isGroup
                                          ? const Icon(Icons.group, color: Colors.white)
                                          : Text(
                                              displayName.isNotEmpty ? displayName[0].toUpperCase() : 'U',
                                              style: const TextStyle(color: Colors.white),
                                            ),
                                    ),
                                    title: Text(displayName),
                                    subtitle: Text(
                                      chat.lastMessage ?? 'Нет сообщений',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    trailing: ConstrainedBox(
                                      constraints: const BoxConstraints(
                                        maxWidth: 80,
                                      ),
                                      child: IntrinsicWidth(
                                        child: Column(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          crossAxisAlignment: CrossAxisAlignment.end,
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text(
                                              _formatTimestamp(chat.lastMessageTimestamp),
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: currentUnreadCount > 0 ? Colors.blue : Colors.grey,
                                                fontWeight: currentUnreadCount > 0 ? FontWeight.bold : FontWeight.normal,
                                              ),
                                              textAlign: TextAlign.end,
                                            ),
                                            const SizedBox(height: 4),
                                            if (currentUnreadCount > 0)
                                              Container(
                                                constraints: const BoxConstraints(
                                                  minWidth: 20,
                                                  minHeight: 20,
                                                ),
                                                padding: EdgeInsets.symmetric(
                                                  horizontal: currentUnreadCount > 9 ? 6 : 4,
                                                  vertical: 2,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: Colors.red,
                                                  borderRadius: BorderRadius.circular(10),
                                                ),
                                                child: Center(
                                                  child: Text(
                                                    currentUnreadCount > 99 
                                                        ? '99+' 
                                                        : currentUnreadCount.toString(),
                                                    style: const TextStyle(
                                                      color: Colors.white,
                                                      fontSize: 11,
                                                      fontWeight: FontWeight.bold,
                                                    ),
                                                    textAlign: TextAlign.center,
                                                  ),
                                                ),
                                              )
                                            else
                                              const SizedBox.shrink(),
                                          ],
                                        ),
                                      ),
                                    ),
                                    onTap: () {
                                      // Всегда открываем чат, профиль можно открыть из самого чата
                                      Navigator.of(context).push(
                                        MaterialPageRoute(
                                          builder: (_) => ChatScreen(chatId: chat.id),
                                        ),
                                      );
                                    },
                                  );
                            },
                          );
                        },
                      );
                    },
                  ),
                ),
      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          FloatingActionButton(
            heroTag: "group",
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const CreateChatScreen(isGroup: true),
                ),
              );
            },
            child: const Icon(Icons.group_add),
          ),
          const SizedBox(height: 10),
          FloatingActionButton(
            heroTag: "chat",
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const CreateChatScreen(isGroup: false),
                ),
              );
            },
            child: const Icon(Icons.chat),
          ),
        ],
      ),
    );
  }
}
