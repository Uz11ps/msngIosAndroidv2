import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/user.dart';
import '../widgets/adaptive_avatar.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';

class UserProfileScreen extends StatelessWidget {
  final User user;

  const UserProfileScreen({super.key, required this.user});

  Future<void> _blockUser(BuildContext context, ApiService apiService) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Заблокировать пользователя?'),
        content: Text(
          'Вы уверены, что хотите заблокировать ${user.displayName ?? user.email ?? user.phoneNumber ?? "этого пользователя"}? '
          'Заблокированный пользователь не сможет отправлять вам сообщения. '
          'Администрация будет уведомлена о блокировке.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Отмена'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Заблокировать'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final result = await apiService.blockUser(user.id);
    
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result['message'] ?? 'Пользователь заблокирован'),
          backgroundColor: result['success'] == true ? Colors.green : Colors.red,
        ),
      );
      
      if (result['success'] == true) {
        Navigator.of(context).pop();
      }
    }
  }

  Future<void> _reportUser(BuildContext context, ApiService apiService) async {
    String? selectedReason;
    final detailsController = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Пожаловаться на пользователя'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Причина жалобы:'),
                const SizedBox(height: 8),
                ...['Спам', 'Оскорбления', 'Неприемлемый контент', 'Мошенничество', 'Другое']
                    .map((reason) => RadioListTile<String>(
                          title: Text(reason),
                          value: reason,
                          groupValue: selectedReason,
                          onChanged: (value) => setState(() => selectedReason = value),
                        )),
                const SizedBox(height: 8),
                TextField(
                  controller: detailsController,
                  decoration: const InputDecoration(
                    labelText: 'Дополнительные детали (необязательно)',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 3,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Отмена'),
            ),
            ElevatedButton(
              onPressed: selectedReason == null
                  ? null
                  : () => Navigator.of(context).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
              ),
              child: const Text('Отправить жалобу'),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true || selectedReason == null) {
      detailsController.dispose();
      return;
    }

    final result = await apiService.reportUser(
      userId: user.id,
      reason: selectedReason!,
      details: detailsController.text.trim().isEmpty ? null : detailsController.text.trim(),
    );
    
    detailsController.dispose();

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result['message'] ?? 'Жалоба отправлена'),
          backgroundColor: result['success'] == true ? Colors.green : Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final apiService = authProvider.apiService;
    final currentUser = authProvider.currentUser;
    final isCurrentUser = currentUser?.id == user.id;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Профиль пользователя'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const SizedBox(height: 24),
          Center(
            child: AdaptiveAvatar(
              photoUrl: user.photoUrl,
              radius: 50,
              backgroundColor: Colors.blue,
              fallbackChild: Text(
                user.displayName?[0].toUpperCase() ?? 'U',
                style: const TextStyle(
                  fontSize: 32,
                  color: Colors.white,
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
          Card(
            child: ListTile(
              leading: const Icon(Icons.person),
              title: const Text('Имя'),
              subtitle: Text(user.displayName ?? 'Не указано'),
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.email),
              title: const Text('Email'),
              subtitle: Text(user.email ?? 'Не указано'),
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.phone),
              title: const Text('Телефон'),
              subtitle: Text(user.phoneNumber ?? 'Не указано'),
            ),
          ),
          if (user.status != null && user.status!.isNotEmpty)
            Card(
              child: ListTile(
                leading: const Icon(Icons.info),
                title: const Text('Статус'),
                subtitle: Text(user.status!),
              ),
            ),
          if (!isCurrentUser) ...[
            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 8),
            Card(
              color: Colors.red.shade50,
              child: ListTile(
                leading: Icon(Icons.block, color: Colors.red.shade700),
                title: const Text('Заблокировать пользователя'),
                subtitle: const Text('Заблокированный пользователь не сможет отправлять вам сообщения'),
                onTap: () => _blockUser(context, apiService),
              ),
            ),
            const SizedBox(height: 8),
            Card(
              color: Colors.orange.shade50,
              child: ListTile(
                leading: Icon(Icons.flag, color: Colors.orange.shade700),
                title: const Text('Пожаловаться на пользователя'),
                subtitle: const Text('Отправить жалобу администрации на неприемлемое поведение'),
                onTap: () => _reportUser(context, apiService),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
