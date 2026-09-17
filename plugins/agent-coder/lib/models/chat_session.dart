import 'dart:convert';

class ChatSessionModel {
  final String id;
  final String title;
  final bool isPinned;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int messageCount;
  final int questionCount;
  final int answerCount;
  final String? workingDirScope;
  final List<String> docFiles;
  final String? targetServer;

  ChatSessionModel({
    required this.id,
    required this.title,
    this.isPinned = false,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.messageCount = 0,
    this.questionCount = 0,
    this.answerCount = 0,
    this.workingDirScope,
    this.docFiles = const [],
    this.targetServer,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  factory ChatSessionModel.fromJson(Map<String, dynamic> json) {
    final mCount = int.tryParse(json['message_count']?.toString() ?? '0') ?? 0;
    final qCount = int.tryParse(json['question_count']?.toString() ?? '0') ?? 0;
    final aCount = int.tryParse(json['answer_count']?.toString() ?? '0') ?? 0;

    List<String> parseDocs(dynamic raw) {
      if (raw == null) return const [];
      if (raw is List) {
        return raw.map((e) => e.toString().trim()).where((e) => e.isNotEmpty).toList();
      }
      if (raw is String && raw.trim().isNotEmpty) {
        try {
          final decoded = jsonDecode(raw);
          if (decoded is List) {
            return decoded.map((e) => e.toString().trim()).where((e) => e.isNotEmpty).toList();
          }
        } catch (_) {
          return raw.split(';').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
        }
      }
      return const [];
    }

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
      messageCount: mCount,
      questionCount: qCount > 0 ? qCount : (mCount > 0 ? (mCount / 2).ceil() : 0),
      answerCount: aCount > 0 ? aCount : (mCount > 0 ? (mCount / 2).floor() : 0),
      workingDirScope: json['working_dir']?.toString() ?? json['working_dir_scope']?.toString(),
      docFiles: parseDocs(json['doc_files'] ?? json['scope_doc_files']),
      targetServer: json['target_server']?.toString() ?? json['server_name']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'is_pinned': isPinned,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
        'message_count': messageCount,
        'question_count': questionCount,
        'answer_count': answerCount,
        if (workingDirScope != null && workingDirScope!.isNotEmpty)
          'working_dir': workingDirScope,
        if (docFiles.isNotEmpty) 'doc_files': jsonEncode(docFiles),
        if (targetServer != null && targetServer!.isNotEmpty)
          'target_server': targetServer,
      };

  ChatSessionModel copyWith({
    String? id,
    String? title,
    bool? isPinned,
    DateTime? createdAt,
    DateTime? updatedAt,
    int? messageCount,
    int? questionCount,
    int? answerCount,
    String? workingDirScope,
    bool clearWorkingDirScope = false,
    List<String>? docFiles,
    bool clearDocFiles = false,
    String? targetServer,
    bool clearTargetServer = false,
  }) {
    return ChatSessionModel(
      id: id ?? this.id,
      title: title ?? this.title,
      isPinned: isPinned ?? this.isPinned,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      messageCount: messageCount ?? this.messageCount,
      questionCount: questionCount ?? this.questionCount,
      answerCount: answerCount ?? this.answerCount,
      workingDirScope: clearWorkingDirScope ? null : (workingDirScope ?? this.workingDirScope),
      docFiles: clearDocFiles ? const [] : (docFiles ?? this.docFiles),
      targetServer: clearTargetServer ? null : (targetServer ?? this.targetServer),
    );
  }
}
