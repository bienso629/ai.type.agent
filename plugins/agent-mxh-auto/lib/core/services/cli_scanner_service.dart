import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;

class LocalCliAgent {
  final String id;
  final String binary;
  final String path;
  final String label;
  final String? version;

  const LocalCliAgent({
    required this.id,
    required this.binary,
    required this.path,
    required this.label,
    this.version,
  });
}

class CliScannerService {
  static final CliScannerService _instance = CliScannerService._internal();
  factory CliScannerService() => _instance;
  CliScannerService._internal();

  static const List<Map<String, dynamic>> _candidateAgents = [
    {
      'id': 'antigravity-cli',
      'binaries': ['agy', 'antigravity-cli'],
      'label': 'Google Antigravity CLI',
    },
    {
      'id': 'claude-cli',
      'binaries': ['claude'],
      'label': 'Anthropic Claude Code CLI',
    },
    {
      'id': 'gemini-cli',
      'binaries': ['gemini'],
      'label': 'Google Gemini CLI',
    },
    {
      'id': 'ollama',
      'binaries': ['ollama'],
      'label': 'Ollama Local LLM',
    },
    {
      'id': 'sgpt-cli',
      'binaries': ['sgpt'],
      'label': 'ShellGPT CLI',
    },
    {
      'id': 'aichat-cli',
      'binaries': ['aichat'],
      'label': 'AIChat CLI',
    },
  ];

  List<String> _getSearchPaths() {
    final searchDirs = <String>[];
    final home = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '';

    if (home.isNotEmpty) {
      searchDirs.add(p.join(home, '.local', 'bin'));
      searchDirs.add(p.join(home, '.cargo', 'bin'));
      searchDirs.add(p.join(home, 'bin'));

      // Check nvm node bin paths
      final nvmNodeDir = Directory(p.join(home, '.nvm', 'versions', 'node'));
      if (nvmNodeDir.existsSync()) {
        try {
          for (final entity in nvmNodeDir.listSync()) {
            if (entity is Directory) {
              final binDir = p.join(entity.path, 'bin');
              if (Directory(binDir).existsSync()) {
                searchDirs.add(binDir);
              }
            }
          }
        } catch (_) {}
      }
    }

    // Common system paths
    searchDirs.addAll([
      '/usr/local/bin',
      '/usr/bin',
      '/bin',
      '/snap/bin',
      '/opt/homebrew/bin',
      '/usr/local/opt',
    ]);

    // Add PATH env variable dirs
    final envPath = Platform.environment['PATH'] ?? '';
    final separator = Platform.isWindows ? ';' : ':';
    for (final part in envPath.split(separator)) {
      if (part.trim().isNotEmpty && !searchDirs.contains(part.trim())) {
        searchDirs.add(part.trim());
      }
    }

    return searchDirs;
  }

  Future<List<LocalCliAgent>> scanInstalledAgents() async {
    final installed = <LocalCliAgent>[];
    final searchPaths = _getSearchPaths();

    for (final candidate in _candidateAgents) {
      final id = candidate['id'] as String;
      final binaries = candidate['binaries'] as List<String>;
      final label = candidate['label'] as String;

      String? foundPath;
      String? foundBinary;

      for (final bin in binaries) {
        // 1. Check direct file existence in search paths
        for (final dirPath in searchPaths) {
          final candidateFile = File(p.join(dirPath, bin));
          final candidateExe = Platform.isWindows ? File(p.join(dirPath, '$bin.exe')) : null;

          if (candidateFile.existsSync()) {
            foundPath = candidateFile.path;
            foundBinary = bin;
            break;
          } else if (candidateExe != null && candidateExe.existsSync()) {
            foundPath = candidateExe.path;
            foundBinary = '$bin.exe';
            break;
          }
        }

        // 2. Try which/where if not found yet
        if (foundPath == null) {
          try {
            final cmd = Platform.isWindows ? 'where' : 'which';
            final res = await Process.run(cmd, [bin]).timeout(const Duration(milliseconds: 600));
            if (res.exitCode == 0 && res.stdout.toString().trim().isNotEmpty) {
              final lines = res.stdout.toString().trim().split('\n');
              if (lines.isNotEmpty && File(lines.first.trim()).existsSync()) {
                foundPath = lines.first.trim();
                foundBinary = bin;
              }
            }
          } catch (_) {}
        }

        if (foundPath != null) break;
      }

      if (foundPath != null && foundBinary != null) {
        String? ver;
        try {
          final verRes = await Process.run(foundPath, ['--version']).timeout(const Duration(seconds: 2));
          if (verRes.exitCode == 0) {
            final output = verRes.stdout.toString().trim();
            if (output.isNotEmpty) {
              final firstLine = output.split('\n').first.trim();
              if (firstLine.length < 40) {
                ver = firstLine;
              }
            }
          }
        } catch (_) {}

        installed.add(LocalCliAgent(
          id: id,
          binary: foundBinary,
          path: foundPath,
          label: label,
          version: ver ?? (id == 'antigravity-cli' ? '1.2.0' : null),
        ));
      }
    }

    // Đảm bảo Google Antigravity CLI luôn có mặt nếu file binary tồn tại trên máy
    final home = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '';
    final agyBinaries = [
      if (home.isNotEmpty) p.join(home, '.local', 'bin', 'agy'),
      if (home.isNotEmpty) p.join(home, 'bin', 'agy'),
      '/usr/local/bin/agy',
      '/snap/bin/antigravity-cli',
    ];
    if (!installed.any((a) => a.id == 'antigravity-cli')) {
      for (final binPath in agyBinaries) {
        if (File(binPath).existsSync()) {
          installed.insert(
            0,
            LocalCliAgent(
              id: 'antigravity-cli',
              binary: p.basename(binPath),
              path: binPath,
              label: 'Google Antigravity CLI',
              version: '1.2.0',
            ),
          );
          break;
        }
      }
    }

    // Nạp thêm hoặc override cấu hình agent từ file ~/.tadu_ai_agent/cli_agents.json nếu người dùng tùy biến
    try {
      final home = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '';
      if (home.isNotEmpty) {
        final customFile = File(p.join(home, '.tadu_ai_agent', 'cli_agents.json'));
        if (customFile.existsSync()) {
          final raw = customFile.readAsStringSync();
          final decoded = jsonDecode(raw);
          if (decoded is List) {
            for (final item in decoded) {
              if (item is Map<String, dynamic>) {
                final cId = item['id']?.toString() ?? '';
                final cPath = item['path']?.toString() ?? '';
                final cBinary = item['binary']?.toString() ?? p.basename(cPath);
                final cLabel = item['label']?.toString() ?? cId;
                final cVer = item['version']?.toString();
                if (cId.isNotEmpty && (cPath.isEmpty || File(cPath).existsSync())) {
                  final existingIdx = installed.indexWhere((a) => a.id == cId);
                  final newAgent = LocalCliAgent(
                    id: cId,
                    binary: cBinary,
                    path: cPath.isNotEmpty ? cPath : cBinary,
                    label: cLabel,
                    version: cVer,
                  );
                  if (existingIdx != -1) {
                    installed[existingIdx] = newAgent;
                  } else {
                    installed.add(newAgent);
                  }
                }
              }
            }
          }
        }
      }
    } catch (_) {}

    return installed;
  }

  /// Thực thi prompt thông qua Local CLI Agent (antigravity, claude, ollama...)
  Future<String> executeAgentPrompt(String agentId, String prompt) async {
    final agents = await scanInstalledAgents();
    LocalCliAgent? targetAgent;
    for (final a in agents) {
      if (a.id == agentId || a.binary == agentId) {
        targetAgent = a;
        break;
      }
    }
    targetAgent ??= agents.isNotEmpty ? agents.first : null;
    if (targetAgent == null) {
      throw Exception('Không tìm thấy Local CLI Agent "$agentId" được cài đặt trên máy tính.');
    }

    final executable = targetAgent.path;
    final binary = targetAgent.binary.toLowerCase();

    List<String> args = [];
    if (binary.contains('agy') || binary.contains('antigravity')) {
      args = ['--print', prompt];
    } else if (binary.contains('claude')) {
      args = ['-p', prompt];
    } else if (binary.contains('ollama')) {
      args = ['run', 'llama3', prompt];
    } else if (binary.contains('sgpt')) {
      args = ['--no-md', prompt];
    } else if (binary.contains('aichat')) {
      args = [prompt];
    } else {
      args = [prompt];
    }

    final result = await Process.run(
      executable,
      args,
      environment: Platform.environment,
      runInShell: true,
    ).timeout(const Duration(minutes: 3));

    if (result.exitCode != 0) {
      final err = result.stderr.toString().trim();
      throw Exception('Lỗi thực thi Local CLI Agent ($binary): ${err.isNotEmpty ? err : result.stdout}');
    }

    return result.stdout.toString().trim();
  }
}
