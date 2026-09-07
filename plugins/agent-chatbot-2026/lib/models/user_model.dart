class UserModel {
  final int? id;
  final String email;
  final String name;
  final String passwordHash;
  final String salt;
  final String createdAt;

  UserModel({
    this.id,
    required this.email,
    required this.name,
    required this.passwordHash,
    required this.salt,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'email': email.trim().toLowerCase(),
      'name': name.trim(),
      'password_hash': passwordHash,
      'salt': salt,
      'created_at': createdAt,
    };
  }

  factory UserModel.fromMap(Map<String, dynamic> map) {
    return UserModel(
      id: map['id'] is int ? map['id'] as int : int.tryParse(map['id']?.toString() ?? ''),
      email: map['email']?.toString() ?? '',
      name: map['name']?.toString() ?? '',
      passwordHash: map['password_hash']?.toString() ?? '',
      salt: map['salt']?.toString() ?? '',
      createdAt: map['created_at']?.toString() ?? '',
    );
  }
}
