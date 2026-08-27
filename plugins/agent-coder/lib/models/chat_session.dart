class ChatSessionModel {
  final String id;
  final String title;
  final bool isPinned;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int messageCount;
  final String? workingDirScope;

  ChatSessionModel({
    required this.id,
    required this.title,
    this.isPinned = false,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.messageCount = 0,
    this.workingDirScope,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  factory ChatSessionModel.fromJson(Map<String, dynamic> json) {
    return ChatSessionModel(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? 'Cuộc hội thoại',
      isPinned: json['is_pinned'] == true || json['is_pinned'] == 1,
      createdAt: json['created_at'] != null
          ? (DateTime.tryParse(json['created_at'].toString()) ?? DateTime.now())
          : DateTime.now(),
      updatedAt: json['updated_at'] != null
          ? (DateTime.tryParse(json['updated_at'].toString()) ?? DateTime.now())
          : DateTime.now(),
      messageCount: int.tryParse(json['message_count']?.toString() ?? '0') ?? 0,
      workingDirScope: json['working_dir']?.toString() ?? json['working_dir_scope']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'is_pinned': isPinned,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
        'message_count': messageCount,
        if (workingDirScope != null && workingDirScope!.isNotEmpty)
          'working_dir': workingDirScope,
      };

  ChatSessionModel copyWith({
    String? id,
    String? title,
    bool? isPinned,
    DateTime? createdAt,
    DateTime? updatedAt,
    int? messageCount,
    String? workingDirScope,
    bool clearWorkingDirScope = false,
  }) {
    return ChatSessionModel(
      id: id ?? this.id,
      title: title ?? this.title,
      isPinned: isPinned ?? this.isPinned,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      messageCount: messageCount ?? this.messageCount,
      workingDirScope: clearWorkingDirScope ? null : (workingDirScope ?? this.workingDirScope),
    );
  }
}
