import '../core/services/encryption_service.dart';

class ServerModel {
  final String id;
  final String name;
  final String serverIp;
  final int sshPort;
  final String sshUser;
  final String sshPass;
  final String? sshKey;
  final String aiModel;
  final String remoteWorkDir;
  final int apiPort;
  final String agentMode; // 'systemd' (Chế độ 1) hoặc 'cli' (Chế độ 2)
  final String cliBinary; // 'agy', 'claude', 'gemini', ... (khi ở chế độ cli)
  final String secretToken;
  final bool isSelected;
  final String status;

  ServerModel({
    required this.id,
    required this.name,
    required this.serverIp,
    this.sshPort = 22,
    this.sshUser = 'root',
    this.sshPass = '',
    this.sshKey,
    this.aiModel = 'glm-5.3',
    this.remoteWorkDir = '/root',
    this.apiPort = 8000,
    this.agentMode = 'systemd',
    this.cliBinary = 'agy',
    this.secretToken = '',
    this.isSelected = false,
    this.status = 'unknown',
  });

  bool get isCliMode => agentMode == 'cli';
  bool get isSystemdMode => agentMode != 'cli';

  factory ServerModel.fromJson(Map<String, dynamic> json, {bool isCurrent = false}) {
    final enc = EncryptionService();
    String dec(dynamic val) {
      if (val == null) return '';
      final s = val.toString();
      if (s.startsWith('enc:')) {
        return enc.decryptValue(s);
      }
      return s;
    }

    final ip = dec(json['server_ip']);
    final rawName = dec(json['name'] ?? json['server_name']);
    final defaultName = ip.isNotEmpty ? ip : 'Máy chủ VPS';

    final sshPortStr = dec(json['ssh_port']);
    final apiPortStr = dec(json['api_port']);
    final modeStr = dec(json['agent_mode']);
    final binStr = dec(json['cli_binary']);

    return ServerModel(
      id: dec(json['id']).isNotEmpty ? dec(json['id']) : (ip.isNotEmpty ? 'srv_$ip' : 'srv_${DateTime.now().millisecondsSinceEpoch}'),
      name: (rawName.isNotEmpty) ? rawName : defaultName,
      serverIp: ip,
      sshPort: int.tryParse(sshPortStr.isNotEmpty ? sshPortStr : '22') ?? 22,
      sshUser: dec(json['ssh_user']).isNotEmpty ? dec(json['ssh_user']) : 'root',
      sshPass: dec(json['ssh_pass']),
      sshKey: json['ssh_key'] != null ? dec(json['ssh_key']) : null,
      aiModel: dec(json['ai_model']).isNotEmpty ? dec(json['ai_model']) : 'glm-5.3',
      remoteWorkDir: dec(json['remote_work_dir']).isNotEmpty ? dec(json['remote_work_dir']) : '/root',
      apiPort: int.tryParse(apiPortStr.isNotEmpty ? apiPortStr : '8000') ?? 8000,
      agentMode: modeStr.isNotEmpty ? modeStr : 'systemd',
      cliBinary: binStr.isNotEmpty ? binStr : 'agy',
      secretToken: dec(json['secret_token']),
      isSelected: isCurrent,
      status: dec(json['status']).isNotEmpty ? dec(json['status']) : 'online',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'server_ip': serverIp,
      'ssh_port': sshPort.toString(),
      'ssh_user': sshUser,
      'ssh_pass': sshPass,
      if (sshKey != null) 'ssh_key': sshKey,
      'ai_model': aiModel,
      'remote_work_dir': remoteWorkDir,
      'api_port': apiPort.toString(),
      'agent_mode': agentMode,
      'cli_binary': cliBinary,
      'secret_token': secretToken,
      'is_selected': isSelected,
    };
  }

  ServerModel copyWith({
    String? id,
    String? name,
    String? serverIp,
    int? sshPort,
    String? sshUser,
    String? sshPass,
    String? sshKey,
    String? aiModel,
    String? remoteWorkDir,
    int? apiPort,
    String? agentMode,
    String? cliBinary,
    String? secretToken,
    bool? isSelected,
    String? status,
  }) {
    return ServerModel(
      id: id ?? this.id,
      name: name ?? this.name,
      serverIp: serverIp ?? this.serverIp,
      sshPort: sshPort ?? this.sshPort,
      sshUser: sshUser ?? this.sshUser,
      sshPass: sshPass ?? this.sshPass,
      sshKey: sshKey ?? this.sshKey,
      aiModel: aiModel ?? this.aiModel,
      remoteWorkDir: remoteWorkDir ?? this.remoteWorkDir,
      apiPort: apiPort ?? this.apiPort,
      agentMode: agentMode ?? this.agentMode,
      cliBinary: cliBinary ?? this.cliBinary,
      secretToken: secretToken ?? this.secretToken,
      isSelected: isSelected ?? this.isSelected,
      status: status ?? this.status,
    );
  }
}
class UniqueKey {
  static int _counter = 0;
  @override
  String toString() => 'server_${++_counter}';
}
