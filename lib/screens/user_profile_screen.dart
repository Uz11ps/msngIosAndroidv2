import 'package:flutter/material.dart';
import '../models/user.dart';
import '../utils/image_utils.dart';

class UserProfileScreen extends StatelessWidget {
  final User user;

  const UserProfileScreen({super.key, required this.user});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Профиль пользователя'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const SizedBox(height: 24),
          Center(
            child: CircleAvatar(
              radius: 50,
              backgroundColor: Colors.blue,
              backgroundImage: user.photoUrl != null && user.photoUrl!.isNotEmpty
                  ? NetworkImage(ImageUtils.getFullImageUrl(user.photoUrl))
                  : null,
              child: user.photoUrl == null || user.photoUrl!.isEmpty
                  ? Text(
                      user.displayName?[0].toUpperCase() ?? 'U',
                      style: const TextStyle(
                        fontSize: 32,
                        color: Colors.white,
                      ),
                    )
                  : null,
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
        ],
      ),
    );
  }
}
