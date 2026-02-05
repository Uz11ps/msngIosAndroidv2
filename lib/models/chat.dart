import 'dart:convert';

class Chat {
  final String id;
  final List<String> participants;
  final String? lastMessage;
  final int? lastMessageTimestamp;
  final bool isGroup;
  final String? groupName;
  final String? groupAdminId;
  final String? groupPhotoUrl;

  Chat({
    required this.id,
    required this.participants,
    this.lastMessage,
    this.lastMessageTimestamp,
    this.isGroup = false,
    this.groupName,
    this.groupAdminId,
    this.groupPhotoUrl,
  });

  factory Chat.fromJson(Map<String, dynamic> json) {
    return Chat(
      id: json['id'] as String,
      participants: json['participants'] is String
          ? List<String>.from(jsonDecode(json['participants'] as String))
          : List<String>.from(json['participants'] as List),
      lastMessage: json['lastMessage'] as String?,
      lastMessageTimestamp: json['lastMessageTimestamp'] as int?,
      isGroup: (json['isGroup'] as int? ?? 0) == 1,
      groupName: json['groupName'] as String?,
      groupAdminId: json['groupAdminId'] as String?,
      groupPhotoUrl: json['groupPhotoUrl'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'participants': participants,
      'lastMessage': lastMessage,
      'lastMessageTimestamp': lastMessageTimestamp,
      'isGroup': isGroup ? 1 : 0,
      'groupName': groupName,
      'groupAdminId': groupAdminId,
      'groupPhotoUrl': groupPhotoUrl,
    };
  }
}
