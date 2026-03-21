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

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'] as String,
      phoneNumber: json['phoneNumber'] as String?,
      email: json['email'] as String?,
      displayName: json['displayName'] as String?,
      photoUrl: json['photoUrl'] as String?,
      status: json['status'] as String?,
      lastSeen: json['lastSeen'] as int?,
      fcmToken: json['fcmToken'] as String?,
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
