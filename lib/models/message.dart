import 'dart:convert';

class Message {
  final String id;
  final String chatId;
  final String senderId;
  final String? text;
  final String type; // 'text', 'image', 'audio', 'video'
  final String? mediaUrl;
  final int timestamp;
  final bool isRead;
  final String? replyToMessageId;

  Message({
    required this.id,
    required this.chatId,
    required this.senderId,
    this.text,
    required this.type,
    this.mediaUrl,
    required this.timestamp,
    this.isRead = false,
    this.replyToMessageId,
  });

  factory Message.fromJson(Map<String, dynamic> json) {
    // Обрабатываем timestamp - может быть int или string
    int timestamp;
    if (json['timestamp'] is int) {
      timestamp = json['timestamp'] as int;
    } else if (json['timestamp'] is String) {
      timestamp = int.tryParse(json['timestamp'] as String) ?? DateTime.now().millisecondsSinceEpoch;
    } else {
      timestamp = DateTime.now().millisecondsSinceEpoch;
    }
    
    return Message(
      id: json['id']?.toString() ?? DateTime.now().millisecondsSinceEpoch.toString(),
      chatId: json['chatId']?.toString() ?? '',
      senderId: json['senderId']?.toString() ?? '',
      text: json['text'] as String?,
      type: json['type'] as String? ?? 'text',
      mediaUrl: json['mediaUrl'] as String?,
      timestamp: timestamp,
      isRead: (json['isRead'] is int ? (json['isRead'] as int) : (json['isRead'] == true ? 1 : 0)) == 1,
      replyToMessageId: json['replyToMessageId'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'chatId': chatId,
      'senderId': senderId,
      'text': text,
      'type': type,
      'mediaUrl': mediaUrl,
      'timestamp': timestamp,
      'isRead': isRead ? 1 : 0,
      'replyToMessageId': replyToMessageId,
    };
  }

  Message copyWith({
    String? id,
    String? chatId,
    String? senderId,
    String? text,
    String? type,
    String? mediaUrl,
    int? timestamp,
    bool? isRead,
    String? replyToMessageId,
  }) {
    return Message(
      id: id ?? this.id,
      chatId: chatId ?? this.chatId,
      senderId: senderId ?? this.senderId,
      text: text ?? this.text,
      type: type ?? this.type,
      mediaUrl: mediaUrl ?? this.mediaUrl,
      timestamp: timestamp ?? this.timestamp,
      isRead: isRead ?? this.isRead,
      replyToMessageId: replyToMessageId ?? this.replyToMessageId,
    );
  }
}
