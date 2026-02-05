import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/chat_provider.dart';
import '../services/api_service.dart';
import '../models/user.dart';
import '../utils/image_utils.dart';
import 'chat_screen.dart';

class CreateChatScreen extends StatefulWidget {
  final bool isGroup;
  final List<String>? existingParticipants; // Для режима выбора участников группы

  const CreateChatScreen({super.key, this.isGroup = false, this.existingParticipants});

  @override
  State<CreateChatScreen> createState() => _CreateChatScreenState();
}

class _CreateChatScreenState extends State<CreateChatScreen> {
  final _searchController = TextEditingController();
  final _groupNameController = TextEditingController();
  List<User> _searchResults = [];
  List<String> _selectedUsers = [];
  bool _isSearching = false;

  @override
  void dispose() {
    _searchController.dispose();
    _groupNameController.dispose();
    super.dispose();
  }

  Future<void> _searchUsers(String query) async {
    if (query.isEmpty) {
      setState(() {
        _searchResults = [];
      });
      return;
    }

    setState(() {
      _isSearching = true;
    });

    try {
      final authProvider = context.read<AuthProvider>();
      final apiService = authProvider.apiService;
      final users = await apiService.searchUsers(query);
      setState(() {
        _searchResults = users;
        _isSearching = false;
      });
    } catch (e) {
      setState(() {
        _isSearching = false;
      });
    }
  }

  void _toggleUser(String userId) {
    setState(() {
      if (_selectedUsers.contains(userId)) {
        _selectedUsers.remove(userId);
      } else {
        _selectedUsers.add(userId);
      }
    });
  }

  Future<void> _createChat() async {
    final authProvider = context.read<AuthProvider>();
    final chatProvider = context.read<ChatProvider>();
    final currentUserId = authProvider.currentUser?.id;

    if (currentUserId == null) return;

    final participants = [currentUserId, ..._selectedUsers];

    if (widget.isGroup) {
      if (_groupNameController.text.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Введите название группы')),
        );
        return;
      }

      final chat = await chatProvider.createGroupChat(
        participants,
        _groupNameController.text.trim(),
        currentUserId,
      );

      if (chat != null && mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => ChatScreen(chatId: chat.id)),
        );
      }
    } else {
      if (_selectedUsers.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Выберите пользователя')),
        );
        return;
      }

      final chat = await chatProvider.createChat(_selectedUsers);

      if (chat != null && mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => ChatScreen(chatId: chat.id)),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isGroup ? 'Создать группу' : 'Новый чат'),
      ),
      body: Column(
        children: [
          if (widget.isGroup)
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: TextField(
                controller: _groupNameController,
                decoration: const InputDecoration(
                  labelText: 'Название группы',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.group),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                labelText: 'Поиск пользователей',
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          _searchUsers('');
                        },
                      )
                    : null,
              ),
              onChanged: _searchUsers,
            ),
          ),
          if (_isSearching)
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: CircularProgressIndicator(),
            )
          else if (_searchResults.isEmpty && _searchController.text.isNotEmpty)
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: Text('Пользователи не найдены'),
            )
          else
            Expanded(
              child: ListView.builder(
                itemCount: _searchResults.length,
                itemBuilder: (context, index) {
                  final user = _searchResults[index];
                  final isSelected = _selectedUsers.contains(user.id);

                  // Исключаем уже существующих участников из списка
                  final isExisting = widget.existingParticipants?.contains(user.id) ?? false;
                  
                  return ListTile(
                    leading: CircleAvatar(
                      backgroundColor: Colors.blue,
                      backgroundImage: user.photoUrl != null
                          ? NetworkImage(ImageUtils.getFullImageUrl(user.photoUrl))
                          : null,
                      child: user.photoUrl == null
                          ? Text(
                              user.displayName?[0].toUpperCase() ?? 'U',
                              style: const TextStyle(color: Colors.white),
                            )
                          : null,
                    ),
                    title: Text(user.displayName ?? 'Без имени'),
                    subtitle: Text(user.email ?? user.phoneNumber ?? ''),
                    trailing: isExisting
                        ? const Text('Уже в группе', style: TextStyle(color: Colors.grey, fontSize: 12))
                        : (isSelected
                            ? const Icon(Icons.check_circle, color: Colors.blue)
                            : const Icon(Icons.circle_outlined)),
                    onTap: isExisting ? null : () => _toggleUser(user.id),
                  );
                },
              ),
            ),
          if (_selectedUsers.isNotEmpty || widget.existingParticipants == null)
            Container(
              padding: const EdgeInsets.all(16.0),
              child: ElevatedButton(
                onPressed: _createChat,
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 50),
                ),
                child: Text(widget.existingParticipants != null 
                    ? 'Добавить участников' 
                    : (widget.isGroup ? 'Создать группу' : 'Создать чат')),
              ),
            ),
        ],
      ),
    );
  }
}
