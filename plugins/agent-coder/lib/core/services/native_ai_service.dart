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

4. PHONG CÁCH TRÌNH BÀY (TUYỆT ĐỐI KHÔNG DÙNG ICON/EMOJI):
   - TUYỆT ĐỐI KHÔNG sử dụng bất kỳ icon, emoji hay biểu tượng hình ảnh nào (như ✅, ❌, 🚀, 💡, 📌, 🎯, ✨, ⚡, 🔍, 🛠️, v.v.) trong câu trả lời.
   - Trình bày câu trả lời bằng văn bản kỹ thuật thuần túy (clean text), chuyên nghiệp, trực diện, mạch lạc.
   - Sử dụng định dạng Markdown chuẩn (tiêu đề, danh sách gạch đầu dòng, in đậm, codeblock) thay cho biểu tượng.
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
            onError('AI API Error (${response.statusCode}): $errBody');
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
      return 'claude';
    }

    if (m.contains('gemini')) {
      final localBin = '$home/.local/bin/gemini';
      if (File(localBin).existsSync()) return localBin;
      return 'gemini';
    }

    return cliName;
  }

  Future<void> _runCliAgent({
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
      final escapedPrompt = prompt.replaceAll("'", "'\\''");
      final cmd = '$exe -p \'$escapedPrompt\'';
      final result = await _executeCommand(cmd, workingDir: workingDir, server: targetServerModel);
      onToken(result);
      onDone(result);
      return;
    }

    try {
      final workDir = (workingDir != null && Directory(workingDir).existsSync())
          ? workingDir
          : (Platform.environment['HOME'] ?? Directory.current.path);

      final cleanPrompt = '$prompt\n\n(Yêu cầu: Tuyệt đối không dùng emoji hay icon trong câu trả lời, trình bày bằng text thuần chuẩn kỹ thuật)';
      List<String> args;
      final m = cliName.toLowerCase();
      if (m.contains('claude')) {
        args = ['-p', cleanPrompt, '--output-format', 'stream-json', '--verbose', '--dangerously-skip-permissions'];
      } else if (m.contains('antigravity') || m == 'agy') {
        args = ['--print', cleanPrompt, '--output-format', 'stream-json', '--dangerously-skip-permissions'];
      } else if (m.contains('gemini')) {
        args = ['-p', cleanPrompt];
      } else {
        args = ['-p', cleanPrompt, '--dangerously-skip-permissions'];
      }

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

      onStatus('AI Agent $cliName đang phân tích và thực thi tác vụ...');
      final process = await Process.start(
        exe,
        args,
        workingDirectory: workDir,
        environment: env,
        runInShell: false,
      );

      // Close stdin immediately so the CLI tool doesn't wait for input
      try {
        await process.stdin.close();
      } catch (_) {}

      final fullOutput = StringBuffer();
      final errOutput = StringBuffer();

      process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
        if (isCancelled()) return;
        final trimmed = line.trim();
        if (trimmed.isEmpty) return;

        try {
          final json = jsonDecode(trimmed);
          if (json is Map<String, dynamic>) {
            // 1. Antigravity CLI (agy) streaming protocol
            if (json.containsKey('event')) {
              final event = json['event'];
              if (event == 'step_update') {
                final step = json['step_update'] as Map<String, dynamic>?;
                final stepType = step?['step_type']?.toString();
                final textDelta = step?['text_delta']?.toString();

                if (textDelta != null && textDelta.isNotEmpty) {
                  fullOutput.write(textDelta);
                  onToken(textDelta);
                } else if (stepType == 'tool_call') {
                  final toolName = step?['tool_name'] ?? 'công cụ';
                  onStatus('Antigravity CLI đang gọi: $toolName...');
                }
              } else if (event == 'result') {
                final res = json['result'] as Map<String, dynamic>?;
                final resp = res?['response']?.toString();
                if (resp != null && fullOutput.isEmpty) {
                  fullOutput.write(resp);
                  onToken(resp);
                }
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
        if (!isCancelled()) {
          errOutput.write(data);
          debugPrint('[$cliName stderr]: $data');
        }
      });

      final exitCode = await process.exitCode;
      if (exitCode == 0 || fullOutput.isNotEmpty) {
        final result = fullOutput.toString().trim();
        onDone(result.isNotEmpty ? result : 'Đã hoàn tất tác vụ với $cliName.');
      } else {
        final errStr = errOutput.toString().trim();
        onError('Agent $cliName báo lỗi (mã $exitCode): ${errStr.isNotEmpty ? errStr : "Không có phản hồi"}');
      }
    } catch (e) {
      onError('Không thể chạy CLI $cliName: $e. Hãy kiểm tra đường dẫn hoặc quyền thực thi.');
    }
  }
}
