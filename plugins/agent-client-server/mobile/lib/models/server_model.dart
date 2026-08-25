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
    this.secretToken = '',
    this.isSelected = false,
    this.status = 'unknown',
  });

  factory ServerModel.fromJson(Map<String, dynamic> json, {bool isCurrent = false}) {
    return ServerModel(
      id: json['id']?.toString() ?? json['server_ip']?.toString() ?? UniqueKey().toString(),
      name: json['name']?.toString() ?? json['server_name']?.toString() ?? json['server_ip']?.toString() ?? 'VPS Server',
      serverIp: json['server_ip']?.toString() ?? '',
      sshPort: int.tryParse(json['ssh_port']?.toString() ?? '22') ?? 22,
      sshUser: json['ssh_user']?.toString() ?? 'root',
      sshPass: json['ssh_pass']?.toString() ?? '',
      sshKey: json['ssh_key']?.toString(),
      aiModel: json['ai_model']?.toString() ?? 'glm-5.3',
      remoteWorkDir: json['remote_work_dir']?.toString() ?? '/root',
      apiPort: int.tryParse(json['api_port']?.toString() ?? '8000') ?? 8000,
      secretToken: json['secret_token']?.toString() ?? '',
      isSelected: isCurrent || (json['is_selected'] == true),
      status: json['status']?.toString() ?? 'online',
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
