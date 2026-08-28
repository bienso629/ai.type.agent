import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../../models/attachment_item.dart';
import '../../models/chat_message.dart';
import '../../models/server_model.dart';
import 'database_service.dart';
import 'local_config_service.dart';

import 'native_ssh_service.dart';

class NativeAiService {
  static final NativeAiService _instance = NativeAiService._internal();
  factory NativeAiService() => _instance;
  NativeAiService._internal();

  final LocalConfigService _configService = LocalConfigService();
  final DatabaseService _dbService = DatabaseService();
  final NativeSshService _sshService = NativeSshService();

  static const String systemPromptBase = '''Bạn là AI Type Agent - Trợ lý AI lập trình, quản trị máy chủ và tự động hoá (hỗ trợ cả Local Machine & Remote Server qua SSH).
Bạn có quyền thực thi lệnh bash/shell/terminal thực tế qua công cụ `execute_terminal_command`.

CÁC QUY TẮC BẮT BUỘC (VI PHẠM LÀ LỖI NGHIÊM TRỌNG):

1. THỰC THI TRIỆT ĐỂ ĐẾN CÙNG - KHÔNG DỪNG NỬA CHỪNG (END-TO-END EXECUTION):
   - Khi nhận yêu cầu (lập trình, quản trị website, cài đặt dịch vụ, tạo file, build dự án, cài đặt thư viện, debug, chạy lệnh, kiểm tra hệ thống...): Bạn PHẢI CHỦ ĐỘNG GỌI `execute_terminal_command` chạy liên tục toàn bộ các bước cho đến khi XONG HOÀN TOÀN và KIỂM CHỨNG THÀNH CÔNG.
   - TUYỆT ĐỐI CẤM dừng lại ở câu nói lấp lửng/dự định (như "Giờ copy...", "Tiếp theo sẽ build...", "Đang kiểm tra..."). Đã định làm gì là PHẢI GỌI TOOL CHẠY LỆNH ĐÓ NGAY LẬP TỨC.
   - Luôn kiểm tra kết quả bước trước. Nếu lệnh phát sinh lỗi, tự động chẩn đoán và chạy lệnh sửa lỗi ngay.

2. TẬP TRUNG ĐÚNG 100% TRỌNG TÂM YÊU CẦU (STRICT SCOPE):
   - CHỈ xử lý ĐÚNG DUY NHẤT mục tiêu mà người dùng đang yêu cầu trong tin nhắn mới nhất.

3. BÁO CÁO KẾT QUẢ RÕ RÀNG, CHÍNH XÁC (ZERO FLUFF):
   - Khi hoàn tất, báo cáo rõ kết quả thực thi và kết luận ngắn gọn.
   - Không chào hỏi dài dòng, không văn mẫu xã giao.

4. PHONG CÁCH TRÌNH BÀY & NGÔN NGỮ:
   - BẮT BUỘC viết TIẾNG VIỆT CÓ ĐẦY ĐỦ DẤU THANH, đúng chính tả và ngữ pháp chuẩn xác.
   - TUYỆT ĐỐI KHÔNG sử dụng bất kỳ icon, emoji hay biểu tượng hình ảnh nào (như ✅, ❌, 🚀, 💡, 📌, 🎯, ✨, ⚡, 🔍, 🛠️, v.v.) trong câu trả lời.
   - Trình bày câu trả lời bằng văn bản kỹ thuật chuyên nghiệp, trực diện, mạch lạc.
   - Sử dụng định dạng Markdown chuẩn (tiêu đề, danh sách gạch đầu dòng, in đậm, bảng biểu, codeblock) thay cho biểu tượng.
''';

  Future<String> _executeCommand(String command, {String? workingDir, int timeoutSeconds = 60, ServerModel? server}) async {
    try {
      if (server != null && server.serverIp != '127.0.0.1' && server.serverIp != 'localhost') {
        return await _sshService.executeCommand(command, workingDir: workingDir, timeoutSeconds: timeoutSeconds, server: server);
      }
      final cfg = await _configService.loadConfig();
      final serverIp = cfg['server_ip']?.toString() ?? '127.0.0.1';
      final isRemote = serverIp.isNotEmpty && serverIp != '127.0.0.1' && serverIp != 'localhost';

      if (isRemote) {
        return await _sshService.executeCommand(command, workingDir: workingDir, timeoutSeconds: timeoutSeconds);
      } else {
        return await _executeLocalCommand(command, workingDir: workingDir, timeoutSeconds: timeoutSeconds);
      }
    } catch (e) {
      return 'Lỗi thực thi lệnh: $e';
    }
  }

  Future<String> _executeLocalCommand(String command, {String? workingDir, int timeoutSeconds = 60}) async {
    try {
      ProcessResult result;
      if (Platform.isWindows) {
        result = await Process.run(
          'cmd.exe',
          ['/c', command],
          workingDirectory: workingDir,
        ).timeout(Duration(seconds: timeoutSeconds));
      } else {
        result = await Process.run(
          'bash',
          ['-c', command],
          workingDirectory: workingDir,
        ).timeout(Duration(seconds: timeoutSeconds));
      }
      final stdoutStr = result.stdout.toString().trim();
      final stderrStr = result.stderr.toString().trim();
      if (stdoutStr.isNotEmpty && stderrStr.isNotEmpty) {
        return '$stdoutStr\n[STDERR]: $stderrStr';
      } else if (stdoutStr.isNotEmpty) {
        return stdoutStr;
      } else if (stderrStr.isNotEmpty) {
        return '[STDERR]: $stderrStr';
      } else {
        return 'Lệnh chạy thành công (Mã thoát: ${result.exitCode})';
      }
    } catch (e) {
      return 'Lỗi thực thi lệnh cục bộ: $e';
    }
  }

  StreamSubscription<String> streamChatMessage({
    required String sessionId,
    required String message,
    String? model,
    List<AttachmentItem>? attachments,
    List<Map<String, dynamic>>? history,
    String? workingDir,
    String? targetServer,
    required void Function(String token) onToken,
    required void Function(String status) onStatus,
    required void Function(ToolExecutionItem tool) onTool,
    required void Function(String fullReply) onDone,
    required void Function(dynamic error) onError,
  }) {
    final controller = StreamController<String>();
    bool isCancelled = false;

    () async {
      try {
        final cfg = await _configService.loadConfig();
        var baseUrl = cfg['proxy_base_url']?.toString() ?? 'https://openrouter.ai/api/v1';
        final apiKey = cfg['proxy_api_key']?.toString() ?? '';
        final defaultModel = cfg['ai_model']?.toString() ?? 'glm-5.3';
        final targetModel = (model != null && model.isNotEmpty) ? model : defaultModel;

        if (baseUrl.endsWith('/')) {
          baseUrl = baseUrl.substring(0, baseUrl.length - 1);
        }

        // Resolve Target Server for this specific session
        ServerModel? targetServerModel;
        final allServers = await _configService.getServers();
        if (targetServer != null && targetServer.isNotEmpty && targetServer != 'Local Machine' && targetServer != 'Local' && targetServer != '127.0.0.1') {
          final matches = allServers.where((s) => s.name == targetServer || s.id == targetServer || s.serverIp == targetServer);
          if (matches.isNotEmpty) {
            targetServerModel = matches.first;
          }
        }

        // Save user message to database
        final userMsg = ChatMessageModel(
          sessionId: sessionId,
          role: 'user',
          content: message,
          model: targetModel,
          attachments: attachments,
          createdAt: DateTime.now(),
        );
        await _dbService.insertMessage(userMsg);

        // If user selected a CLI agent (e.g. antigravity-cli, claude-cli, gemini-cli)
        if (_isCliModel(targetModel)) {
          await _runCliAgent(
            sessionId: sessionId,
            cliName: targetModel,
            prompt: message,
            workingDir: workingDir,
            targetServerModel: targetServerModel,
            onToken: onToken,
            onStatus: onStatus,
            onTool: onTool,
            onDone: (reply) async {
              final assistantMsg = ChatMessageModel(
                sessionId: sessionId,
                role: 'assistant',
                content: reply.isNotEmpty ? reply : 'Đã hoàn tất tác vụ với $targetModel.',
                model: targetModel,
                createdAt: DateTime.now(),
              );
              await _dbService.insertMessage(assistantMsg);
              onDone(reply.isNotEmpty ? reply : 'Đã hoàn tất tác vụ với $targetModel.');
            },
            onError: onError,
            isCancelled: () => isCancelled,
          );
          return;
        }

        // Build System Prompt
        String sysPrompt = systemPromptBase;
        if (targetServerModel != null) {
          sysPrompt += '\n\n🎯 MÔI TRƯỜNG THỰC THI: Máy chủ từ xa [${targetServerModel.name}] (${targetServerModel.serverIp}). Mọi lệnh terminal của bạn sẽ được gửi trực tiếp qua SSH tới máy chủ này.';
        } else {
          sysPrompt += '\n\n🎯 MÔI TRƯỜNG THỰC THI: Máy tính cục bộ (${Platform.operatingSystem}). Mọi lệnh terminal được chạy an toàn trên local shell.';
        }
        if (workingDir != null && workingDir.isNotEmpty) {
          sysPrompt += '\n🎯 THƯ MỤC LÀM VIỆC: `$workingDir`\nMọi lệnh terminal phải thực hiện bên trong thư mục này.';
        }

        final messages = <Map<String, dynamic>>[
          {'role': 'system', 'content': sysPrompt},
        ];

        // Append recent history
        if (history != null && history.isNotEmpty) {
          for (final h in history) {
            messages.add({
              'role': h['role'] ?? 'user',
              'content': h['content'] ?? '',
            });
          }
        } else {
          // Fetch last 10 messages from DB
          final dbHistory = await _dbService.getMessages(sessionId, limit: 10);
          for (final m in dbHistory.messages) {
            if (m.content != message) {
              messages.add({
                'role': m.role,
                'content': m.content,
              });
            }
          }
        }

        // Format user message with attachments
        String fullUserPrompt = message;
        if (attachments != null && attachments.isNotEmpty) {
          fullUserPrompt += '\n\n=== TỆP & ẢNH ĐÍNH KÈM TỪ NGƯỜI DÙNG ===';
          for (final att in attachments) {
            if (att.isImage) {
              fullUserPrompt += '\n\n--- [Ảnh: ${att.name}] --- (Người dùng đính kèm ảnh)';
            } else {
              fullUserPrompt += '\n\n--- [Tệp: ${att.name}] ---\n${att.content}';
            }
          }
        }

        // Add current user message
        messages.add({'role': 'user', 'content': fullUserPrompt});

        final tools = [
          {
            'type': 'function',
            'function': {
              'name': 'execute_terminal_command',
              'description': 'Thực thi lệnh terminal bash/shell trên máy tính cục bộ (Local OS).',
              'parameters': {
                'type': 'object',
                'properties': {
                  'command': {
                    'type': 'string',
                    'description': 'Lệnh shell/bash cần chạy trên máy tính cục bộ'
                  }
                },
                'required': ['command']
              }
            }
          }
        ];

        String finalReply = '';
        final allExecutedTools = <ToolExecutionItem>[];
        int turnCount = 0;
        const maxTurns = 20;

        while (turnCount < maxTurns && !isCancelled) {
          turnCount++;
          final client = http.Client();
          final request = http.Request('POST', Uri.parse('$baseUrl/chat/completions'));
          request.headers.addAll({
            'Content-Type': 'application/json',
            'Accept': 'application/json',
            if (apiKey.isNotEmpty) 'Authorization': 'Bearer $apiKey',
          });

          final requestBody = {
            'model': targetModel,
            'messages': messages,
            'tools': tools,
            'stream': true,
          };
          request.body = jsonEncode(requestBody);

          onStatus(turnCount == 1 ? 'Đang suy nghĩ...' : 'Đang xử lý bước tiếp theo...');
          final response = await client.send(request);

          if (response.statusCode != 200) {
            final errBody = await response.stream.bytesToString();
            String errorMsg = 'AI API Error (${response.statusCode}): $errBody';
            if (response.statusCode == 401) {
              errorMsg += '\n\n💡 Hướng dẫn khắc phục:\n'
                  '1. Vào mục "Cấu hình" (bên menu trái) -> Nhập "Proxy API Key" hợp lệ và lưu cấu hình.\n'
                  '2. Hoặc bấm vào góc trên bên trái (chỗ đang chọn $targetModel) và chọn "Google Antigravity CLI" để chạy trực tiếp trên máy không cần API Key.';
            }
            onError(errorMsg);
            client.close();
            return;
          }

          String stepContent = '';
          final toolCallsMap = <int, Map<String, dynamic>>{};

          final streamCompleter = Completer<void>();

          response.stream
              .transform(utf8.decoder)
              .transform(const LineSplitter())
              .listen(
            (line) {
              final trimmed = line.trim();
              if (trimmed.isEmpty) return;
              if (trimmed == 'data: [DONE]') {
                return;
              }
              if (trimmed.startsWith('data:')) {
                final jsonStr = trimmed.substring(5).trim();
                try {
                  final data = jsonDecode(jsonStr);
                  final choices = data['choices'] as List<dynamic>?;
                  if (choices != null && choices.isNotEmpty) {
                    final delta = choices[0]['delta'] as Map<String, dynamic>?;
                    if (delta != null) {
                      // Text content delta
                      if (delta['content'] != null) {
                        final token = delta['content'].toString();
                        stepContent += token;
                        onToken(token);
                      }

                      // Tool calls delta
                      if (delta['tool_calls'] != null) {
                        final tcs = delta['tool_calls'] as List<dynamic>;
                        for (final tc in tcs) {
                          final idx = tc['index'] as int? ?? 0;
                          toolCallsMap.putIfAbsent(idx, () => {
                            'id': tc['id'] ?? '',
                            'name': tc['function']?['name'] ?? '',
                            'arguments': '',
                          });
                          if (tc['id'] != null && tc['id'].toString().isNotEmpty) {
                            toolCallsMap[idx]!['id'] = tc['id'];
                          }
                          if (tc['function']?['name'] != null) {
                            toolCallsMap[idx]!['name'] = tc['function']['name'];
                          }
                          if (tc['function']?['arguments'] != null) {
                            toolCallsMap[idx]!['arguments'] =
                                (toolCallsMap[idx]!['arguments'] as String) + tc['function']['arguments'].toString();
                          }
                        }
                      }
                    }
                  }
                } catch (_) {}
              }
            },
            onError: (err) {
              if (!streamCompleter.isCompleted) streamCompleter.completeError(err);
            },
            onDone: () {
              if (!streamCompleter.isCompleted) streamCompleter.complete();
              client.close();
            },
            cancelOnError: true,
          );

          await streamCompleter.future;

          // Check if tools were called
          if (toolCallsMap.isNotEmpty) {
            final formattedToolCalls = <Map<String, dynamic>>[];
            final executedToolResults = <Map<String, dynamic>>[];

            for (final entry in toolCallsMap.entries) {
              final tc = entry.value;
              final toolCallId = tc['id']?.toString() ?? 'call_${entry.key}';
              final funcName = tc['name']?.toString() ?? 'execute_terminal_command';
              final rawArgs = tc['arguments']?.toString() ?? '{}';

              formattedToolCalls.add({
                'id': toolCallId,
                'type': 'function',
                'function': {
                  'name': funcName,
                  'arguments': rawArgs,
                }
              });

              // Execute tool
              String cmd = '';
              try {
                final parsedArgs = jsonDecode(rawArgs);
                cmd = parsedArgs['command']?.toString() ?? '';
              } catch (_) {
                cmd = rawArgs;
              }

              onStatus('Đang chạy lệnh: $cmd');

              final toolItem = ToolExecutionItem(
                tool: funcName,
                command: cmd,
                output: 'Đang thực thi...',
              );
              onTool(toolItem);

              final cmdOutput = await _executeCommand(cmd, workingDir: workingDir, server: targetServerModel);

              final finishedTool = ToolExecutionItem(
                tool: funcName,
                command: cmd,
                output: cmdOutput,
              );
              allExecutedTools.add(finishedTool);
              onTool(finishedTool);

              executedToolResults.add({
                'tool_call_id': toolCallId,
                'content': cmdOutput,
              });
            }

            // Properly append single assistant message containing all tool_calls for this turn
            messages.add({
              'role': 'assistant',
              'content': stepContent.isNotEmpty ? stepContent : null,
              'tool_calls': formattedToolCalls,
            });

            // Append each tool response
            for (final res in executedToolResults) {
              messages.add({
                'role': 'tool',
                'tool_call_id': res['tool_call_id'],
                'content': res['content'],
              });
            }

            // Add spacing token if there was narration
            if (stepContent.isNotEmpty) {
              onToken('\n\n');
            }
          } else {
            // Finished generation without more tools
            finalReply = stepContent;
            break;
          }
        }

        // Final reply fallback if not captured
        if (finalReply.isEmpty && messages.isNotEmpty && messages.last['role'] == 'assistant') {
          finalReply = messages.last['content']?.toString() ?? '';
        }

        // Save assistant message to Database
        final assistantMsg = ChatMessageModel(
          sessionId: sessionId,
          role: 'assistant',
          content: finalReply.isNotEmpty ? finalReply : 'Đã hoàn tất thao tác.',
          model: targetModel,
          toolExecutions: allExecutedTools,
          createdAt: DateTime.now(),
        );
        await _dbService.insertMessage(assistantMsg);

        onDone(finalReply.isNotEmpty ? finalReply : 'Đã hoàn tất thao tác.');
      } catch (e) {
        onError('Lỗi xử lý AI: $e');
      }
    }();

    return controller.stream.listen((_) {}, onDone: () {
      isCancelled = true;
    });
  }

  bool _isCliModel(String model) {
    final m = model.toLowerCase();
    return m.contains('cli') || m == 'agy' || m == 'claude' || m == 'gemini';
  }

  String _findCliExecutable(String cliName) {
    final home = Platform.environment['HOME'] ?? '';
    final m = cliName.toLowerCase();

    if (m.contains('antigravity') || m == 'agy') {
      final userBin = '$home/.local/bin/agy';
      if (File(userBin).existsSync()) return userBin;
      final binDir = '$home/bin/agy';
      if (File(binDir).existsSync()) return binDir;
      final usrLocal = '/usr/local/bin/agy';
      if (File(usrLocal).existsSync()) return usrLocal;
      final snapBin = '/snap/bin/antigravity-cli';
      if (File(snapBin).existsSync()) return snapBin;
      return 'agy';
    }

    if (m.contains('claude')) {
      final nvmDir = '$home/.nvm/versions/node';
      if (Directory(nvmDir).existsSync()) {
        try {
          final entries = Directory(nvmDir).listSync();
          for (final e in entries) {
            final claudePath = '${e.path}/bin/claude';
            if (File(claudePath).existsSync()) return claudePath;
          }
        } catch (_) {}
      }
      final localBin = '$home/.local/bin/claude';
      if (File(localBin).existsSync()) return localBin;
      final usrLocal = '/usr/local/bin/claude';
      if (File(usrLocal).existsSync()) return usrLocal;
      return 'claude';
    }

    if (m.contains('gemini')) {
      final localBin = '$home/.local/bin/gemini';
      if (File(localBin).existsSync()) return localBin;
      final usrLocal = '/usr/local/bin/gemini';
      if (File(usrLocal).existsSync()) return usrLocal;
      return 'gemini';
    }

    return cliName;
  }

  static final Map<String, _AgyWorker> _activeAgyWorkers = {};

  /// Preloads Antigravity CLI in the background on app startup
  static Future<void> preloadAgyWorker({String? workingDir}) async {
    try {
      final exe = NativeAiService()._findCliExecutable('antigravity');
      final workDir = (workingDir != null && Directory(workingDir).existsSync())
          ? workingDir
          : (Platform.environment['HOME'] ?? Directory.current.path);

      final env = Map<String, String>.from(Platform.environment);
      final home = Platform.environment['HOME'] ?? '';
      final currentPath = env['PATH'] ?? '';
      final extraPaths = <String>[
        '$home/.local/bin',
        '$home/bin',
        '/usr/local/bin',
        '/snap/bin',
      ];
      final nvmDir = Directory('$home/.nvm/versions/node');
      if (nvmDir.existsSync()) {
        try {
          for (final dir in nvmDir.listSync()) {
            final binPath = '${dir.path}/bin';
            if (Directory(binPath).existsSync()) {
              extraPaths.add(binPath);
            }
          }
        } catch (_) {}
      }
      env['PATH'] = '${extraPaths.join(':')}:$currentPath';
      if (home.isNotEmpty) env['HOME'] = home;

      if (!_activeAgyWorkers.containsKey('prewarm')) {
        final proc = await Process.start(
          exe,
          [
            '--input-format',
            'stream-json',
            '--output-format',
            'stream-json',
            '--dangerously-skip-permissions',
            '--effort',
            'low',
          ],
          workingDirectory: workDir,
          environment: env,
          runInShell: false,
        );
        final worker = _AgyWorker(process: proc, workingDir: workDir);
        _activeAgyWorkers['prewarm'] = worker;
      }
    } catch (_) {}
  }

  /// Disposes all prewarmed/active CLI workers from RAM.
  static void disposeAgyWorkers() {
    for (final w in _activeAgyWorkers.values) {
      w.dispose();
    }
    _activeAgyWorkers.clear();
  }

  Future<void> _runCliAgent({
    required String sessionId,
    required String cliName,
    required String prompt,
    String? workingDir,
    ServerModel? targetServerModel,
    required void Function(String token) onToken,
    required void Function(String status) onStatus,
    required void Function(ToolExecutionItem tool) onTool,
    required void Function(String fullReply) onDone,
    required void Function(dynamic error) onError,
    required bool Function() isCancelled,
  }) async {
    final exe = _findCliExecutable(cliName);
    onStatus('Đang khởi chạy $cliName agent...');

    if (targetServerModel != null) {
      onStatus('Đang gửi lệnh tới $cliName trên máy chủ ${targetServerModel.name}...');
      final cleanPrompt = '$prompt\n\n(Yêu cầu: Viết tiếng Việt có đầy đủ dấu thanh chuẩn chính tả, tuyệt đối không dùng emoji hay icon trong câu trả lời, trình bày bằng định dạng markdown kỹ thuật chuẩn)';
      final escapedPrompt = cleanPrompt.replaceAll("'", "'\\''");

      String remoteBinary = 'agy';
      final m = cliName.toLowerCase();
      if (m.contains('claude')) {
        remoteBinary = 'claude';
      } else if (m.contains('gemini')) {
        remoteBinary = 'gemini';
      }

      final cmd = '''
export PATH="\$HOME/.local/bin:\$HOME/bin:\$HOME/.nvm/versions/node/\$(ls \$HOME/.nvm/versions/node 2>/dev/null | tail -n 1)/bin:/usr/local/bin:/usr/bin:/bin:\$PATH"
if command -v $remoteBinary >/dev/null 2>&1; then
  $remoteBinary -p '$escapedPrompt' --dangerously-skip-permissions
elif [ -f "\$HOME/.local/bin/$remoteBinary" ]; then
  "\$HOME/.local/bin/$remoteBinary" -p '$escapedPrompt' --dangerously-skip-permissions
elif [ -f "/usr/local/bin/$remoteBinary" ]; then
  "/usr/local/bin/$remoteBinary" -p '$escapedPrompt' --dangerously-skip-permissions
else
  echo "LỖI: Máy chủ ${targetServerModel.name} (${targetServerModel.serverIp}) chưa được cài đặt '$remoteBinary'."
  echo ""
  echo "Hướng dẫn:"
  echo "1. Cài đặt $remoteBinary trên máy chủ VPS: ssh vào VPS và cài đặt $remoteBinary vào ~/.local/bin hoặc /usr/local/bin."
  echo "2. Hoặc chọn 'Local Machine' ở danh sách máy chủ bên trái để chạy $remoteBinary trực tiếp từ máy tính của bạn."
fi
''';
      final result = await _executeCommand(cmd, workingDir: workingDir, server: targetServerModel);
      onToken(result);
      onDone(result);
      return;
    }

    try {
      final workDir = (workingDir != null && Directory(workingDir).existsSync())
          ? workingDir
          : (Platform.environment['HOME'] ?? Directory.current.path);

      final cleanPrompt = '''$prompt

(Yêu cầu thực thi bắt buộc dành cho Agent CLI):
- THƯ MỤC LÀM VIỆC MỤC TIÊU (SCOPE BẮT BUỘC): `$workDir`
- Mọi lệnh terminal, tạo file, cấu hình mã nguồn, cài đặt gói BẮT BUỘC thực hiện trực tiếp tại thư mục `$workDir` (hoặc tạo thư mục con ngay trong `$workDir`). Tuyệt đối KHÔNG tạo ở scratch/ hay bất kỳ thư mục nào khác ngoài `$workDir`.
- TUYỆT ĐỐI KHÔNG TỰ CHẠY LỆNH SERVER CHẠY NỀN VÔ TẬN (như `npm run dev`, `npm run start`, `node server.js`, `python manage.py runserver`, `flask run`). Hãy biên dịch kiểm tra lỗi bằng `npm run build` hoặc lệnh test tương tự, sau đó in rõ câu lệnh và hướng dẫn người dùng chạy server ở Terminal hoặc ngoài hệ thống.
- Viết tiếng Việt có đầy đủ dấu thanh chuẩn chính tả, tuyệt đối không dùng emoji hay icon trong câu trả lời, trình bày bằng định dạng markdown kỹ thuật chuẩn.
- Khi tạo dự án hoặc cài đặt mã nguồn/thư viện (như Payload CMS, Next.js, npm, npx, pip, cargo): HÃY THỰC THI ĐỒNG BỘ VÀ HOÀN TẤT TRỌN VẸN TRONG LƯỢT NÀY. Luôn truyền cờ tự động không tương tác (ví dụ: -y, --yes, --template blank, --db sqlite) để lệnh tự động cài đặt xong ngay.
- Tuyệt đối KHÔNG đẩy tác vụ cài đặt ra chạy nền rồi kết thúc sớm khi chưa có kết quả. Hãy đợi cài đặt hoàn tất, xác nhận cấu trúc thư mục đã tạo và báo cáo đầy đủ cho người dùng kèm hướng dẫn lệnh chạy server.''';

      final m = cliName.toLowerCase();

      // Augmented PATH environment so subprocesses (node, git, etc.) are always found
      final env = Map<String, String>.from(Platform.environment);
      final home = Platform.environment['HOME'] ?? '';
      final currentPath = env['PATH'] ?? '';
      final extraPaths = <String>[
        '$home/.local/bin',
        '$home/bin',
        '/usr/local/bin',
        '/snap/bin',
      ];
      final nvmDir = Directory('$home/.nvm/versions/node');
      if (nvmDir.existsSync()) {
        try {
          for (final dir in nvmDir.listSync()) {
            final binPath = '${dir.path}/bin';
            if (Directory(binPath).existsSync()) {
              extraPaths.add(binPath);
            }
          }
        } catch (_) {}
      }
      env['PATH'] = '${extraPaths.join(':')}:$currentPath';
      if (home.isNotEmpty) env['HOME'] = home;

      // 1. Persistent Warm Interactive Worker for Antigravity CLI
      if ((m.contains('antigravity') || m == 'agy')) {
        try {
          _AgyWorker? worker = _activeAgyWorkers[sessionId];
          // Check if there is a prewarmed worker available
          if (worker == null && _activeAgyWorkers.containsKey('prewarm') && _activeAgyWorkers['prewarm']!.workingDir == workDir) {
            worker = _activeAgyWorkers.remove('prewarm');
            if (worker != null) {
              _activeAgyWorkers[sessionId] = worker;
            }
          }

          if (worker == null || worker.workingDir != workDir) {
            worker?.dispose();
            onStatus('Đang nạp sẵn môi trường Antigravity CLI...');
            final proc = await Process.start(
              exe,
              [
                '--input-format',
                'stream-json',
                '--output-format',
                'stream-json',
                '--dangerously-skip-permissions',
                '--effort',
                'low',
              ],
              workingDirectory: workDir,
              environment: env,
              runInShell: false,
            );
            worker = _AgyWorker(process: proc, workingDir: workDir);
            _activeAgyWorkers[sessionId] = worker;
          }

          onStatus('AI Agent $cliName đang phản hồi...');
          final fullOutput = StringBuffer();
          final completer = Completer<void>();
          Timer? idleTimer;

          void resetIdleTimer() {
            idleTimer?.cancel();
            if (fullOutput.isNotEmpty) {
              idleTimer = Timer(const Duration(milliseconds: 3000), () {
                if (!completer.isCompleted) completer.complete();
              });
            }
          }

          late StreamSubscription sub;
          sub = worker.stream.listen((json) {
            if (isCancelled()) {
              idleTimer?.cancel();
              sub.cancel();
              if (!completer.isCompleted) completer.complete();
              return;
            }

            final event = json['event'];
            if (event == 'step_update') {
              final step = json['step_update'] as Map<String, dynamic>?;
              final stepType = step?['step_type']?.toString();
              final textDelta = step?['text_delta']?.toString() ?? step?['content']?.toString() ?? step?['text']?.toString();
              final errorMsg = step?['error']?.toString();

              if (textDelta != null && textDelta.isNotEmpty) {
                fullOutput.write(textDelta);
                onToken(textDelta);
                resetIdleTimer();
              } else if (errorMsg != null && errorMsg.isNotEmpty) {
                fullOutput.write('\n[Lỗi]: $errorMsg\n');
                onToken('\n[Lỗi]: $errorMsg\n');
                resetIdleTimer();
              } else if (stepType == 'tool' || stepType == 'tool_call') {
                idleTimer?.cancel();
                final state = step?['state']?.toString();
                final toolInfo = step?['tool_info'] as Map<String, dynamic>?;
                final toolParams = toolInfo?['parameters'] as Map<String, dynamic>? ??
                    step?['tool_args'] as Map<String, dynamic>? ??
                    step?['parameters'] as Map<String, dynamic>? ??
                    step?['args'] as Map<String, dynamic>?;
                final toolName = step?['tool_name']?.toString() ?? toolInfo?['name']?.toString() ?? 'công cụ';

                String cmdDesc = '';
                if (toolParams != null) {
                  if (toolParams['CommandLine'] != null) {
                    cmdDesc = toolParams['CommandLine'].toString();
                  } else if (toolParams['TargetFile'] != null) {
                    cmdDesc = '${toolParams['Instruction'] ?? 'Sửa file'}: ${toolParams['TargetFile']}';
                  } else if (toolParams['AbsolutePath'] != null) {
                    cmdDesc = 'Đọc file: ${toolParams['AbsolutePath']}';
                  } else if (toolParams['Query'] != null) {
                    cmdDesc = 'Tìm "${toolParams['Query']}" trong ${toolParams['SearchPath'] ?? ''}';
                  } else if (toolParams['DirectoryPath'] != null) {
                    cmdDesc = 'Xem thư mục: ${toolParams['DirectoryPath']}';
                  } else if (toolParams['toolAction'] != null) {
                    cmdDesc = toolParams['toolAction'].toString();
                  } else if (toolParams['command'] != null) {
                    cmdDesc = toolParams['command'].toString();
                  }
                }
                if (cmdDesc.isEmpty) {
                  cmdDesc = toolName;
                }

                // If state is ACTIVE, only update status; when DONE, emit the full tool card with output
                if (state == 'ACTIVE') {
                  onStatus('Đang thực thi $toolName: $cmdDesc...');
                } else {
                  final output = toolInfo?['output']?.toString() ?? step?['output']?.toString() ?? step?['tool_result']?.toString() ?? '';
                  onTool(ToolExecutionItem(
                    tool: toolName,
                    command: cmdDesc,
                    output: output,
                  ));
                }
              } else if (stepType == 'thought' || stepType == 'thinking') {
                onStatus('AI đang suy nghĩ và lập kế hoạch...');
              }
            } else if (event == 'result') {
              idleTimer?.cancel();
              final res = json['result'] as Map<String, dynamic>?;
              final resp = res?['response']?.toString();
              final status = res?['status']?.toString();
              final errorMsg = res?['error']?.toString();
              if (resp != null && resp.isNotEmpty && fullOutput.isEmpty) {
                fullOutput.write(resp);
                onToken(resp);
              } else if (status == 'ERROR' && errorMsg != null && errorMsg.isNotEmpty) {
                fullOutput.write('\n[Lỗi Antigravity]: $errorMsg\n');
                onToken('\n[Lỗi Antigravity]: $errorMsg\n');
                _activeAgyWorkers.remove(sessionId)?.dispose();
              }
              sub.cancel();
              if (!completer.isCompleted) completer.complete();
            } else if (event == 'error') {
              idleTimer?.cancel();
              final err = json['error']?.toString() ?? json['message']?.toString() ?? '';
              if (err.isNotEmpty) {
                fullOutput.write('\n[Lỗi Antigravity]: $err\n');
                onToken('\n[Lỗi Antigravity]: $err\n');
              }
              _activeAgyWorkers.remove(sessionId)?.dispose();
              sub.cancel();
              if (!completer.isCompleted) completer.complete();
            }
          });

          await worker.sendPrompt(cleanPrompt);
          await completer.future.timeout(const Duration(minutes: 3), onTimeout: () {
            _activeAgyWorkers.remove(sessionId)?.dispose();
            if (!completer.isCompleted) completer.complete();
          });

          idleTimer?.cancel();
          sub.cancel();

          final resStr = fullOutput.toString().trim();
          onDone(resStr.isNotEmpty ? resStr : 'Đã hoàn tất tác vụ với $cliName.');
          return;
        } catch (e) {
          _activeAgyWorkers.remove(sessionId)?.dispose();
          // Fallback to one-shot CLI execution below
        }
      }

      List<String> args;
      if (m.contains('claude')) {
        args = ['-p', cleanPrompt, '--output-format', 'stream-json', '--verbose', '--dangerously-skip-permissions'];
      } else if (m.contains('antigravity') || m == 'agy') {
        args = ['--print', cleanPrompt, '--input-format', 'text', '--output-format', 'stream-json', '--dangerously-skip-permissions', '--effort', 'low', '--print-timeout', '15m0s'];
      } else if (m.contains('gemini')) {
        args = ['-p', cleanPrompt];
      } else {
        args = ['-p', cleanPrompt, '--dangerously-skip-permissions'];
      }

      onStatus('AI Agent $cliName đang phân tích và thực thi tác vụ...');
      final process = await Process.start(
        exe,
        args,
        workingDirectory: workDir,
        environment: env,
        runInShell: false,
      );

      final fullOutput = StringBuffer();
      final rawStdout = StringBuffer();
      final errOutput = StringBuffer();
      bool hasFinished = false;

      void finishSession([String? fallbackReply]) {
        if (hasFinished) return;
        hasFinished = true;
        final result = fullOutput.toString().trim();
        onDone(result.isNotEmpty ? result : (fallbackReply ?? 'Đã hoàn tất tác vụ với $cliName.'));
        try {
          process.kill();
        } catch (_) {}
      }

      // Close stdin asynchronously
      process.stdin.close().catchError((_) {});

      process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
        if (isCancelled() || hasFinished) return;
        final trimmed = line.trim();
        if (trimmed.isEmpty) return;
        rawStdout.writeln(line);

        try {
          final json = jsonDecode(trimmed);
          if (json is Map<String, dynamic>) {
            // 1. Antigravity CLI (agy) streaming protocol
            if (json.containsKey('event')) {
              final event = json['event'];
              if (event == 'step_update') {
                final step = json['step_update'] as Map<String, dynamic>?;
                final stepType = step?['step_type']?.toString();
                final textDelta = step?['text_delta']?.toString() ?? step?['content']?.toString() ?? step?['text']?.toString();
                final errorMsg = step?['error']?.toString();

                if (textDelta != null && textDelta.isNotEmpty) {
                  fullOutput.write(textDelta);
                  onToken(textDelta);
                } else if (errorMsg != null && errorMsg.isNotEmpty) {
                  fullOutput.write('\n[Lỗi]: $errorMsg\n');
                  onToken('\n[Lỗi]: $errorMsg\n');
                } else if (stepType == 'tool' || stepType == 'tool_call') {
                  final state = step?['state']?.toString();
                  final toolInfo = step?['tool_info'] as Map<String, dynamic>?;
                  final toolParams = toolInfo?['parameters'] as Map<String, dynamic>? ??
                      step?['tool_args'] as Map<String, dynamic>? ??
                      step?['parameters'] as Map<String, dynamic>? ??
                      step?['args'] as Map<String, dynamic>?;
                  final toolName = step?['tool_name']?.toString() ?? toolInfo?['name']?.toString() ?? 'công cụ';

                  String cmdDesc = '';
                  if (toolParams != null) {
                    if (toolParams['CommandLine'] != null) {
                      cmdDesc = toolParams['CommandLine'].toString();
                    } else if (toolParams['TargetFile'] != null) {
                      cmdDesc = '${toolParams['Instruction'] ?? 'Sửa file'}: ${toolParams['TargetFile']}';
                    } else if (toolParams['AbsolutePath'] != null) {
                      cmdDesc = 'Đọc file: ${toolParams['AbsolutePath']}';
                    } else if (toolParams['Query'] != null) {
                      cmdDesc = 'Tìm "${toolParams['Query']}" trong ${toolParams['SearchPath'] ?? ''}';
                    } else if (toolParams['DirectoryPath'] != null) {
                      cmdDesc = 'Xem thư mục: ${toolParams['DirectoryPath']}';
                    } else if (toolParams['toolAction'] != null) {
                      cmdDesc = toolParams['toolAction'].toString();
                    } else if (toolParams['command'] != null) {
                      cmdDesc = toolParams['command'].toString();
                    }
                  }
                  if (cmdDesc.isEmpty) {
                    cmdDesc = toolName;
                  }

                  if (state == 'ACTIVE') {
                    onStatus('Đang thực thi $toolName: $cmdDesc...');
                  } else {
                    final output = toolInfo?['output']?.toString() ?? step?['output']?.toString() ?? step?['tool_result']?.toString() ?? '';
                    onTool(ToolExecutionItem(
                      tool: toolName,
                      command: cmdDesc,
                      output: output,
                    ));
                  }
                } else if (stepType == 'thought' || stepType == 'thinking') {
                  onStatus('AI đang suy nghĩ và lập kế hoạch...');
                }
              } else if (event == 'result') {
                final res = json['result'] as Map<String, dynamic>?;
                final resp = res?['response']?.toString();
                final status = res?['status']?.toString();
                final errorMsg = res?['error']?.toString();
                if (resp != null && resp.isNotEmpty && fullOutput.isEmpty) {
                  fullOutput.write(resp);
                  onToken(resp);
                } else if (status == 'ERROR' && errorMsg != null && errorMsg.isNotEmpty) {
                  fullOutput.write('\n[Lỗi Antigravity]: $errorMsg\n');
                  onToken('\n[Lỗi Antigravity]: $errorMsg\n');
                }
                finishSession();
                return;
              } else if (event == 'error') {
                final err = json['error']?.toString() ?? json['message']?.toString() ?? '';
                if (err.isNotEmpty) {
                  fullOutput.write('\n[Lỗi Antigravity]: $err\n');
                  onToken('\n[Lỗi Antigravity]: $err\n');
                }
                finishSession();
                return;
              }
              return;
            }

            // 2. Claude Code CLI streaming protocol
            if (json.containsKey('type')) {
              final type = json['type'];
              if (type == 'content_block_delta') {
                final delta = json['delta'] as Map<String, dynamic>?;
                final text = delta?['text']?.toString();
                if (text != null && text.isNotEmpty) {
                  fullOutput.write(text);
                  onToken(text);
                }
              } else if (type == 'result') {
                final result = json['result']?.toString();
                if (result != null && fullOutput.isEmpty) {
                  fullOutput.write(result);
                  onToken(result);
                }
                finishSession();
                return;
              } else if (type == 'error') {
                final err = json['error']?.toString() ?? json['message']?.toString() ?? '';
                if (err.isNotEmpty) {
                  fullOutput.write('\n[Lỗi Claude]: $err\n');
                  onToken('\n[Lỗi Claude]: $err\n');
                }
                finishSession();
                return;
              } else if (type == 'assistant') {
                final msg = json['message'] as Map<String, dynamic>?;
                final contents = msg?['content'] as List<dynamic>?;
                if (contents != null) {
                  for (final c in contents) {
                    if (c is Map && c['type'] == 'text') {
                      final t = c['text']?.toString();
                      if (t != null && fullOutput.isEmpty) {
                        fullOutput.write(t);
                        onToken(t);
                      }
                    }
                  }
                }
              }
              return;
            }
          }
        } catch (_) {
          // Not JSON -> handle as plain text stream
        }

        // Plain text fallback line
        fullOutput.writeln(line);
        onToken('$line\n');
      });

      process.stderr.transform(utf8.decoder).listen((data) {
        if (!isCancelled() && !hasFinished) {
          errOutput.write(data);
          debugPrint('[$cliName stderr]: $data');
        }
      });

      final exitCode = await process.exitCode;
      if (!hasFinished) {
        if (exitCode == 0 || fullOutput.isNotEmpty) {
          finishSession();
        } else {
          final errStr = errOutput.toString().trim();
          final rawStr = rawStdout.toString().trim();
          final displayErr = errStr.isNotEmpty
              ? errStr
              : (rawStr.isNotEmpty ? rawStr : 'Không có phản hồi từ tiến trình (Mã thoát: $exitCode)');
          onError('Agent $cliName báo lỗi (mã $exitCode): $displayErr');
        }
      }
    } catch (e) {
      onError('Không thể chạy CLI $cliName: $e. Hãy kiểm tra đường dẫn hoặc quyền thực thi.');
    }
  }
}

class _AgyWorker {
  final Process process;
  final String workingDir;
  final StreamController<Map<String, dynamic>> _controller = StreamController<Map<String, dynamic>>.broadcast();
  final Completer<void> _initCompleter = Completer<void>();
  bool _isDisposed = false;
  DateTime lastActive = DateTime.now();

  Stream<Map<String, dynamic>> get stream => _controller.stream;
  Future<void> get onInit => _initCompleter.future;

  _AgyWorker({required this.process, required this.workingDir}) {
    process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
      if (_isDisposed) return;
      final trimmed = line.trim();
      if (trimmed.isEmpty) return;
      try {
        final json = jsonDecode(trimmed);
        if (json is Map<String, dynamic>) {
          if (json['event'] == 'init' && !_initCompleter.isCompleted) {
            _initCompleter.complete();
          }
          _controller.add(json);
        }
      } catch (_) {}
    }, onDone: () {
      if (!_initCompleter.isCompleted) _initCompleter.complete();
      _controller.close();
    });

    process.stderr.transform(utf8.decoder).listen((_) {});
  }

  Future<void> sendPrompt(String prompt) async {
    try {
      await onInit.timeout(const Duration(seconds: 10));
    } catch (_) {}
    lastActive = DateTime.now();
    final turnMsg = jsonEncode({
      'event': 'user',
      'message': {'content': prompt}
    });
    process.stdin.writeln(turnMsg);
    await process.stdin.flush();
  }

  void dispose() {
    _isDisposed = true;
    try {
      process.kill();
    } catch (_) {}
    _controller.close();
  }
}
