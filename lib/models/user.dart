class User {
  final String id;
  final String? phoneNumber;
  final String? email;
  final String? displayName;
  final String? photoUrl;
  final String? status;
  final int? lastSeen;
  final String? fcmToken;

  User({
    required this.id,
    this.phoneNumber,
    this.email,
    this.displayName,
    this.photoUrl,
    this.status,
    this.lastSeen,
    this.fcmToken,
  });

  static String? _asString(dynamic value) {
    if (value == null) return null;
    final text = value.toString().trim();
    return text.isEmpty ? null : text;
  }

  static int? _asInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString());
  }

  factory User.fromJson(Map<String, dynamic> json) {
    final parsedId = _asString(json['id']);
    if (parsedId == null) {
      throw const FormatException('User id is missing in response');
    }
    return User(
      id: parsedId,
      phoneNumber: _asString(json['phoneNumber']),
      email: _asString(json['email']),
      displayName: _asString(json['displayName']),
      photoUrl: _asString(json['photoUrl']),
      status: _asString(json['status']),
      lastSeen: _asInt(json['lastSeen']),
      fcmToken: _asString(json['fcmToken']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'phoneNumber': phoneNumber,
      'email': email,
      'displayName': displayName,
      'photoUrl': photoUrl,
      'status': status,
      'lastSeen': lastSeen,
      'fcmToken': fcmToken,
    };
  }

  User copyWith({
    String? id,
    String? phoneNumber,
    String? email,
    String? displayName,
    String? photoUrl,
    String? status,
    int? lastSeen,
    String? fcmToken,
  }) {
    return User(
      id: id ?? this.id,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      email: email ?? this.email,
      displayName: displayName ?? this.displayName,
      photoUrl: photoUrl ?? this.photoUrl,
      status: status ?? this.status,
      lastSeen: lastSeen ?? this.lastSeen,
      fcmToken: fcmToken ?? this.fcmToken,
    );
  }
}
