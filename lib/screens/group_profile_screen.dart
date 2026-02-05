import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import '../models/chat.dart';
import '../models/user.dart';
import '../providers/auth_provider.dart';
import '../providers/chat_provider.dart';
import '../services/api_service.dart';
import '../utils/image_utils.dart';
import 'create_chat_screen.dart';

class GroupProfileScreen extends StatefulWidget {
  final Chat chat;

  const GroupProfileScreen({super.key, required this.chat});

  @override
  State<GroupProfileScreen> createState() => _GroupProfileScreenState();
}

class _GroupProfileScreenState extends State<GroupProfileScreen> {
  final TextEditingController _groupNameController = TextEditingController();
  final ImagePicker _picker = ImagePicker();
  bool _isLoading = false;
  List<User> _participants = [];
  String? _groupPhotoUrl;

  @override
  void initState() {
    super.initState();
    _groupNameController.text = widget.chat.groupName ?? 'Группа';
    _groupPhotoUrl = widget.chat.groupPhotoUrl;
    _loadParticipants();
  }

  Future<void> _loadParticipants() async {
    try {
      final chatProvider = context.read<ChatProvider>();
      final participants = <User>[];
      
      for (final userId in widget.chat.participants) {
        final user = await chatProvider.getUser(userId);
        if (user != null) {
          participants.add(user);
        }
      }
      
      setState(() {
        _participants = participants;
      });
    } catch (e) {
      print('Error loading participants: $e');
    }
  }

  bool get _isAdmin {
    final authProvider = context.read<AuthProvider>();
    return widget.chat.groupAdminId == authProvider.currentUser?.id;
  }

  Future<void> _updateGroupName() async {
    if (_groupNameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Название группы не может быть пустым')),
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      final authProvider = context.read<AuthProvider>();
      final apiService = authProvider.apiService;
      
      final success = await apiService.updateGroupChat(
        chatId: widget.chat.id,
        groupName: _groupNameController.text.trim(),
      );

      if (success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Название группы обновлено')),
        );
        // Обновляем список чатов
        final chatProvider = context.read<ChatProvider>();
        await chatProvider.loadChats();
        Navigator.of(context).pop(true); // Возвращаем true для обновления списка чатов
      } else {
        throw Exception('Failed to update group name');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _updateGroupPhoto() async {
    try {
      final image = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 85,
      );

      if (image == null) return;

      setState(() => _isLoading = true);
      
      final authProvider = context.read<AuthProvider>();
      final apiService = authProvider.apiService;
      
      // Загружаем фото
      final url = await apiService.uploadFile(image.path);
      
      if (url != null) {
        // Обновляем фото группы
        final success = await apiService.updateGroupChat(
          chatId: widget.chat.id,
          groupPhotoUrl: url,
        );

        if (success && mounted) {
          setState(() {
            _groupPhotoUrl = url;
          });
          // Обновляем список чатов
          final chatProvider = context.read<ChatProvider>();
          await chatProvider.loadChats();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Фото группы обновлено')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _addParticipant() async {
    final result = await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CreateChatScreen(
          isGroup: false,
          existingParticipants: widget.chat.participants,
        ),
      ),
    );

    if (result != null && result is List<String>) {
      setState(() => _isLoading = true);
      try {
        final authProvider = context.read<AuthProvider>();
        final apiService = authProvider.apiService;
        
        for (final userId in result) {
          if (!widget.chat.participants.contains(userId)) {
            await apiService.addParticipant(widget.chat.id, userId);
          }
        }
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Участники добавлены')),
          );
          _loadParticipants();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Ошибка: $e')),
          );
        }
      } finally {
        if (mounted) {
          setState(() => _isLoading = false);
        }
      }
    }
  }

  Future<void> _removeParticipant(String userId) async {
    if (!_isAdmin) return;
    
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удалить участника?'),
        content: const Text('Вы уверены, что хотите удалить этого участника из группы?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      setState(() => _isLoading = true);
      try {
        final authProvider = context.read<AuthProvider>();
        final apiService = authProvider.apiService;
        
        final success = await apiService.removeParticipant(widget.chat.id, userId);
        
        if (success && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Участник удален')),
          );
          _loadParticipants();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Ошибка: $e')),
          );
        }
      } finally {
        if (mounted) {
          setState(() => _isLoading = false);
        }
      }
    }
  }

  @override
  void dispose() {
    _groupNameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Профиль группы'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const SizedBox(height: 24),
                Center(
                  child: GestureDetector(
                    onTap: _isAdmin ? _updateGroupPhoto : null,
                    child: Stack(
                      children: [
                        CircleAvatar(
                          radius: 50,
                          backgroundColor: Colors.blue,
                          backgroundImage: _groupPhotoUrl != null && _groupPhotoUrl!.isNotEmpty
                              ? NetworkImage(ImageUtils.getFullImageUrl(_groupPhotoUrl!))
                              : null,
                          child: _groupPhotoUrl == null || _groupPhotoUrl!.isEmpty
                              ? const Icon(Icons.group, size: 50, color: Colors.white)
                              : null,
                        ),
                        if (_isAdmin)
                          Positioned(
                            bottom: 0,
                            right: 0,
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: const BoxDecoration(
                                color: Colors.blue,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.camera_alt, size: 20, color: Colors.white),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Card(
                  child: ListTile(
                    title: TextField(
                      controller: _groupNameController,
                      enabled: _isAdmin,
                      decoration: const InputDecoration(
                        labelText: 'Название группы',
                        border: InputBorder.none,
                      ),
                    ),
                    trailing: _isAdmin
                        ? IconButton(
                            icon: const Icon(Icons.check),
                            onPressed: _updateGroupName,
                          )
                        : null,
                  ),
                ),
                const SizedBox(height: 16),
                Card(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Участники',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            if (_isAdmin)
                              IconButton(
                                icon: const Icon(Icons.person_add),
                                onPressed: _addParticipant,
                                tooltip: 'Добавить участника',
                              ),
                          ],
                        ),
                      ),
                      const Divider(height: 1),
                      ..._participants.map((user) {
                        final isAdmin = user.id == widget.chat.groupAdminId;
                        return ListTile(
                          leading: CircleAvatar(
                            backgroundColor: Colors.blue,
                            backgroundImage: user.photoUrl != null && user.photoUrl!.isNotEmpty
                                ? NetworkImage(ImageUtils.getFullImageUrl(user.photoUrl!))
                                : null,
                            child: user.photoUrl == null || user.photoUrl!.isEmpty
                                ? Text(
                                    (user.displayName?[0] ?? 'U').toUpperCase(),
                                    style: const TextStyle(color: Colors.white),
                                  )
                                : null,
                          ),
                          title: Text(user.displayName ?? user.email ?? user.phoneNumber ?? 'Пользователь'),
                          subtitle: isAdmin ? const Text('Создатель группы') : null,
                          trailing: _isAdmin && !isAdmin
                              ? IconButton(
                                  icon: const Icon(Icons.remove_circle_outline, color: Colors.red),
                                  onPressed: () => _removeParticipant(user.id),
                                )
                              : null,
                        );
                      }),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}
