class PersonaProfile {
  final String ip;
  final String name;
  final int age;
  final String gender;
  final String bio;
  final String avatarPrompt;

  PersonaProfile({
    required this.ip,
    required this.name,
    required this.age,
    required this.gender,
    required this.bio,
    required this.avatarPrompt,
  });

  Map<String, dynamic> toJson() => {
    'ip': ip,
    'name': name,
    'age': age,
    'gender': gender,
    'bio': bio,
    'avatar_prompt': avatarPrompt,
  };

  factory PersonaProfile.fromJson(Map<String, dynamic> json) => PersonaProfile(
    ip: json['ip']?.toString() ?? '',
    name: json['name']?.toString() ?? '',
    age: (json['age'] is num) ? (json['age'] as num).toInt() : (int.tryParse(json['age']?.toString() ?? '') ?? 25),
    gender: json['gender']?.toString() ?? 'Nam',
    bio: json['bio']?.toString() ?? '',
    avatarPrompt: json['avatar_prompt']?.toString() ?? json['avatarPrompt']?.toString() ?? '',
  );
}
