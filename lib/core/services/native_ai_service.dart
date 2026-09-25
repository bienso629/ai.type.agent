import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
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

  static final RegExp _systemMessageRegex = RegExp(
    r'(?:The following is a <SYSTEM_MESSAGE>[^\n]*\n+)?<SYSTEM_MESSAGE>[\s\S]*?<\/SYSTEM_MESSAGE>',
    caseSensitive: false,
    dotAll: true,
  );

  static String stripSystemMessages(String text) {
    if (!text.contains('<SYSTEM_MESSAGE>')) return text;
    return text.replaceAll(_systemMessageRegex, '').trim();
  }

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
   - Khi gặp câu hỏi quá khó, bất khả thi hoặc thiếu thông tin: Hãy giải thích rõ ràng tại sao không thể trả lời/thực hiện được, sau đó hướng dẫn người dùng cách cung cấp thêm ngữ cảnh hoặc tinh chỉnh prompt để Bot có thể xử lý chính xác.
   - Sử dụng định dạng Markdown chuẩn (tiêu đề, danh sách gạch đầu dòng, in đậm, bảng biểu, codeblock) thay cho biểu tượng.

5. BẢO MẬT & PHÂN LẬP TÀI KHOẢN TUYỆT ĐỐI (SECURITY & PRIVACY):
   - NGHIÊM CẤM truy cập, đọc nội dung, trích xuất, in ra màn hình hoặc giải mã bất kỳ file cấu hình tài khoản cá nhân nào (như config*.json, ~/.ai_type_agent/config*.json, ~/.tadu_ai_agent/config*.json, .env, chat_history*.db, file credential SSH/API key của hệ thống hoặc người dùng khác).
   - Nếu người dùng yêu cầu đọc hoặc xem thông tin nhạy cảm từ các file config tài khoản trên máy, BẮT BUỘC từ chối thực hiện vì vi phạm chính sách bảo mật và an toàn thông tin người dùng.
''';

  static bool _isCommandBlocked(String command) {
    final lower = command.toLowerCase();
    // Chặn các hành vi truy cập hoặc hiển thị file cấu hình người dùng nhạy cảm
    final patterns = [
      RegExp(r'(?:cat|more|less|head|tail|view|nano|vim|vi|sed|awk|grep|rg|python|python3|perl|ruby|cp|scp|rsync|base64|curl|wget)\b[^\n]*\bconfig[a-zA-Z0-9_\-\.]*\.json\b', caseSensitive: false),
      RegExp(r'\.ai_type_agent[/\\]config', caseSensitive: false),
      RegExp(r'\.tadu_ai_agent[/\\]config', caseSensitive: false),
      RegExp(r'config_[a-zA-Z0-9_\-]+\.json', caseSensitive: false),
      RegExp(r'(?:cat|less|more|head|tail|view|nano|vim|vi|grep|rg|sqlite3)\b[^\n]*\bchat_history[a-zA-Z0-9_\-\.]*\.db\b', caseSensitive: false),
      RegExp(r'tadu-cloud-ai-agent-control-center-secret-salt', caseSensitive: false),
    ];
    for (final p in patterns) {
      if (p.hasMatch(lower)) {
        return true;
      }
    }
    return false;
  }

  Future<String> _executeCommand(String command, {String? workingDir, int timeoutSeconds = 60, ServerModel? server}) async {
    try {
      if (_isCommandBlocked(command)) {
        return 'LỖI BẢO MẬT (SECURITY POLICY): Lệnh bị từ chối thực thi do vi phạm chính sách an toàn. Agent không được phép truy cập, đọc hoặc hiển thị file cấu hình tài khoản (config*.json, .env, credential DB).';
      }
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
    if (_isCommandBlocked(command)) {
      return 'LỖI BẢO MẬT (SECURITY POLICY): Lệnh bị từ chối thực thi do vi phạm chính sách an toàn. Agent không được phép truy cập, đọc hoặc hiển thị file cấu hình tài khoản (config*.json, .env, credential DB).';
    }
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
    List<String>? docFiles,
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
          targetServerModel = allServers.firstWhere(
            (s) => s.id == targetServer || s.name == targetServer || s.serverIp == targetServer,
            orElse: () => ServerModel(id: targetServer, name: targetServer, serverIp: targetServer),
          );
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
            history: history,
            workingDir: workingDir,
            docFiles: docFiles,
            targetServerModel: targetServerModel,
            onToken: onToken,
            onStatus: onStatus,
            onTool: onTool,
            onDone: (reply) async {
              final cleanReply = stripSystemMessages(reply);
              final assistantMsg = ChatMessageModel(
                sessionId: sessionId,
                role: 'assistant',
                content: cleanReply.isNotEmpty ? cleanReply : 'Đã hoàn tất tác vụ với $targetModel.',
                model: targetModel,
                createdAt: DateTime.now(),
              );
              await _dbService.insertMessage(assistantMsg);
              onDone(cleanReply.isNotEmpty ? cleanReply : 'Đã hoàn tất tác vụ với $targetModel.');
            },
            onError: onError,
            isCancelled: () => isCancelled,
          );
          return;
        }

        // Build System Prompt
        final customPrompt = cfg['custom_prompt']?.toString();
        String sysPrompt = (customPrompt != null && customPrompt.trim().isNotEmpty)
            ? customPrompt.trim()
            : systemPromptBase;

        if (targetServerModel != null) {
          sysPrompt += '\n\n🎯 MÔI TRƯỜNG THỰC THI: Máy chủ từ xa [${targetServerModel.name}] (${targetServerModel.serverIp}). Mọi lệnh terminal của bạn sẽ được gửi trực tiếp qua SSH tới máy chủ này.';
        } else {
          sysPrompt += '\n\n🎯 MÔI TRƯỜNG THỰC THI: Máy tính cục bộ (${Platform.operatingSystem}). Mọi lệnh terminal được chạy an toàn trên local shell.';
        }
        if (workingDir != null && workingDir.isNotEmpty) {
          sysPrompt += '\n🎯 THƯ MỤC LÀM VIỆC: `$workingDir`\nMọi lệnh terminal phải thực hiện bên trong thư mục này.';
          sysPrompt = sysPrompt.replaceAll('{workDir}', workingDir).replaceAll('\$workDir', workingDir);
        }
        if (docFiles != null && docFiles.isNotEmpty) {
          sysPrompt += '\n\n📚 TÀI LIỆU DỰ ÁN (SCOPE DOCUMENTATION):';
          sysPrompt += '\nĐây là danh sách các tệp tài liệu đặc tả, yêu cầu kỹ thuật thuộc phạm vi dự án này:';
          for (final doc in docFiles) {
            sysPrompt += '\n- `$doc`';
          }
          sysPrompt += '\nKHI THỰC HIỆN CÁC YÊU CẦU: Hãy chủ động đọc hoặc tham chiếu nội dung từ các file tài liệu trên khi cần thiết để hiểu đúng kiến trúc, nghiệp vụ và quy chuẩn dự án.';
        }

        final messages = <Map<String, dynamic>>[
          {'role': 'system', 'content': sysPrompt},
        ];

        // Append recent history (prior turns)
        if (history != null && history.isNotEmpty) {
          for (final h in history) {
            final role = h['role']?.toString() ?? 'user';
            final content = h['content']?.toString() ?? '';
            if (content.isNotEmpty) {
              messages.add({
                'role': role,
                'content': content,
              });
            }
          }
        } else {
          // Fetch last 15 messages from DB
          final dbHistory = await _dbService.getMessages(sessionId, limit: 15);
          for (final m in dbHistory.messages) {
            if (m.content != message && m.content.isNotEmpty) {
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

  /// Preloads Antigravity CLI in the background on app startup (noop stub)
  static Future<void> preloadAgyWorker({String? workingDir}) async {}

  /// Disposes all prewarmed/active CLI workers from RAM (noop stub)
  static void disposeAgyWorkers() {}

  Future<void> _runCliAgent({
    required String sessionId,
    required String cliName,
    required String prompt,
    List<Map<String, dynamic>>? history,
    String? workingDir,
    List<String>? docFiles,
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

    final cfg = await _configService.loadConfig();
    final customPromptTemplate = cfg['custom_prompt']?.toString();

    // Check if we have an existing persistent CLI conversation ID for this session
    String? cliConvId = await _dbService.getCliConversationId(sessionId);

    if (targetServerModel != null) {
      final configuredBinary = targetServerModel.cliBinary.isNotEmpty ? targetServerModel.cliBinary : 'agy';
      
      String remoteBinary = configuredBinary;
      final m = cliName.toLowerCase();
      if (m.contains('claude')) {
        remoteBinary = 'claude';
      } else if (m.contains('gemini')) {
        remoteBinary = 'gemini';
      } else if (m.contains('antigravity') || m == 'agy') {
        remoteBinary = 'agy';
      }

      onStatus('Đang gửi lệnh tới $remoteBinary CLI trên máy chủ ${targetServerModel.name} (${targetServerModel.serverIp})...');
      final promptSuffix = (customPromptTemplate != null && customPromptTemplate.trim().isNotEmpty)
          ? customPromptTemplate.trim()
          : '(Yêu cầu: Viết tiếng Việt có đầy đủ dấu thanh chuẩn chính tả, tuyệt đối không dùng emoji hay icon trong câu trả lời, trình bày bằng định dạng markdown kỹ thuật chuẩn. Tuyệt đối không đọc, truy cập hoặc làm lộ các file cấu hình config*.json, .env hay credential của hệ thống và người dùng)';
      final cleanPrompt = '$prompt\n\n$promptSuffix';
      final escapedPrompt = cleanPrompt.replaceAll("'", "'\\''");

      String remoteCliArgs = "-p '$escapedPrompt' --dangerously-skip-permissions";
      if (remoteBinary == 'agy' || remoteBinary.contains('antigravity')) {
        if (cliConvId != null && cliConvId.isNotEmpty) {
          remoteCliArgs = "--conversation '$cliConvId' -p '$escapedPrompt' --dangerously-skip-permissions";
        } else {
          remoteCliArgs = "-p '$escapedPrompt' --dangerously-skip-permissions";
        }
      } else if (remoteBinary == 'claude' || remoteBinary.contains('claude')) {
        if (cliConvId != null && cliConvId.isNotEmpty) {
          remoteCliArgs = "--session-id '$cliConvId' -p '$escapedPrompt' --dangerously-skip-permissions";
        } else {
          remoteCliArgs = "-p '$escapedPrompt' --dangerously-skip-permissions";
        }
      }

      final cmd = '''
export PATH="\$HOME/.local/bin:\$HOME/bin:\$HOME/.nvm/versions/node/\$(ls \$HOME/.nvm/versions/node 2>/dev/null | tail -n 1)/bin:/usr/local/bin:/usr/bin:/bin:\$PATH"
if command -v $remoteBinary >/dev/null 2>&1; then
  $remoteBinary $remoteCliArgs 2>&1
elif [ -f "\$HOME/.local/bin/$remoteBinary" ]; then
  "\$HOME/.local/bin/$remoteBinary" $remoteCliArgs 2>&1
elif [ -f "/usr/local/bin/$remoteBinary" ]; then
  "/usr/local/bin/$remoteBinary" $remoteCliArgs 2>&1
else
  echo "LỖI: Máy chủ ${targetServerModel.name} (${targetServerModel.serverIp}) chưa được cài đặt '$remoteBinary'."
  echo ""
  echo "Thông tin chế độ server:"
  echo "- Chế độ đã chọn: Chế độ 2 (CLI Agent: $remoteBinary)"
  echo "- Hướng dẫn cài đặt $remoteBinary trên máy chủ VPS: ssh vào VPS và cài đặt $remoteBinary vào ~/.local/bin hoặc /usr/local/bin."
  echo "- Hoặc nếu máy chủ chạy dịch vụ systemd (ai-agent.service), hãy chuyển cấu hình máy chủ sang 'Chế độ 1: Dịch vụ AI Agent (Systemd)'."
fi
''';
      final result = await _executeCommand(cmd, workingDir: workingDir, server: targetServerModel);
      final convMatch = RegExp(r'"conversation_id":\s*"([^"]+)"').firstMatch(result);
      if (convMatch != null) {
        final foundConv = convMatch.group(1);
        if (foundConv != null && foundConv.isNotEmpty) {
          await _dbService.setCliConversationId(sessionId, foundConv);
        }
      }
      final cleanRes = stripSystemMessages(result);
      onToken(cleanRes);
      onDone(cleanRes);
      return;
    }

    try {
      final workDir = (workingDir != null && Directory(workingDir).existsSync())
          ? workingDir
          : (Platform.environment['HOME'] ?? Directory.current.path);

      String promptSuffix;
      if (customPromptTemplate != null && customPromptTemplate.trim().isNotEmpty) {
        promptSuffix = customPromptTemplate
            .replaceAll('{workDir}', workDir)
            .replaceAll('\$workDir', workDir)
            .trim();
      } else {
        promptSuffix = '''(Yêu cầu thực thi bắt buộc dành cho Agent CLI):
- THƯ MỤC LÀM VIỆC MỤC TIÊU (SCOPE BẮT BUỘC): `$workDir`
- Mọi lệnh terminal, tạo file, cấu hình mã nguồn, cài đặt gói BẮT BUỘC thực hiện trực tiếp tại thư mục `$workDir` (hoặc tạo thư mục con ngay trong `$workDir`). Tuyệt đối KHÔNG tạo ở scratch/ hay bất kỳ thư mục nào khác ngoài `$workDir`.
- TUYỆT ĐỐI KHÔNG TỰ CHẠY LỆNH SERVER CHẠY NỀN VÔ TẬN (như `npm run dev`, `npm run start`, `node server.js`, `python manage.py runserver`, `flask run`). Hãy biên dịch kiểm tra lỗi bằng `npm run build` hoặc lệnh test tương tự, sau đó in rõ câu lệnh và hướng dẫn người dùng chạy server ở Terminal hoặc ngoài hệ thống.
- Viết tiếng Việt có đầy đủ dấu thanh chuẩn chính tả, tuyệt đối không dùng emoji hay icon trong câu trả lời, trình bày bằng định dạng markdown kỹ thuật chuẩn.
- Khi tạo dự án hoặc cài đặt mã nguồn/thư viện (như Payload CMS, Next.js, npm, npx, pip, cargo): HÃY THỰC THI ĐỒNG BỘ VÀ HOÀN TẤT TRỌN VẸN TRONG LƯỢT NÀY. Luôn truyền cờ tự động không tương tác (ví dụ: -y, --yes, --template blank, --db sqlite) để lệnh tự động cài đặt xong ngay.
- TUYỆT ĐỐI CẤM TRUY CẬP, ĐỌC, IN RA MÀN HÌNH HOẶC GIẢI MÃ BẤT KỲ FILE CẤU HÌNH TÀI KHOẢN NÀO (như config*.json, ~/.ai_type_agent/config*.json, ~/.tadu_ai_agent/config*.json, .env, chat_history*.db, các khóa bảo mật hệ thống). Nếu người dùng yêu cầu đọc file config tài khoản, phải từ chối vì lý do bảo mật.
- Tuyệt đối KHÔNG kết thúc sớm khi chưa có kết quả đầy đủ. Hãy đợi kiểm tra/cài đặt hoàn tất, xác nhận cấu trúc thư mục/kết quả đã tạo và báo cáo đầy đủ cho người dùng.''';
      }

      // Đọc và đính kèm nội dung các file tài liệu / rules được chọn vào prompt
      if (docFiles != null && docFiles.isNotEmpty) {
        final docsBuffer = StringBuffer();
        docsBuffer.writeln('\n\n=== TÀI LIỆU DỰ ÁN & RULES BẮT BUỘC THAM CHIẾU (SCOPE DOCS) ===');
        docsBuffer.writeln('Người dùng đã chỉ định các tệp tài liệu và rules dưới đây để Agent tuân thủ và hiểu rõ yêu cầu dự án:\n');

        for (final docPath in docFiles) {
          final file = File(docPath);
          final docName = p.basename(docPath);
          if (file.existsSync()) {
            try {
              final len = file.lengthSync();
              // Nếu file < 150KB, đọc trực tiếp nội dung nạp vào prompt để Agent hiểu ngay tức khắc
              if (len <= 150 * 1024) {
                final content = file.readAsStringSync();
                docsBuffer.writeln('--- TẬP TIN: $docName ($docPath) ---');
                docsBuffer.writeln(content);
                docsBuffer.writeln('--- HẾT TẬP TIN: $docName ---\n');
              } else {
                docsBuffer.writeln('- Đường dẫn file tài liệu: `$docPath` (Kích thước lớn: ${(len / 1024).round()} KB, Agent hãy chủ động đọc khi cần)');
              }
            } catch (_) {
              docsBuffer.writeln('- Đường dẫn file tài liệu: `$docPath`');
            }
          } else {
            docsBuffer.writeln('- File tài liệu: `$docPath`');
          }
        }
        docsBuffer.writeln('=== KẾT THÚC TÀI LIỆU SCOPE ===');
        promptSuffix = '$promptSuffix\n\n${docsBuffer.toString()}';
      }

      final cleanPrompt = '$prompt\n\n$promptSuffix';

      final m = cliName.toLowerCase();

      // Build contextual prompt for CLI models that do not support multi-turn session IDs
      String contextualPrompt = cleanPrompt;
      if (m.contains('gemini') || (!m.contains('agy') && !m.contains('antigravity') && !m.contains('claude'))) {
        final recentHistory = (history != null && history.isNotEmpty)
            ? history
            : (await _dbService.getMessages(sessionId, limit: 10)).messages.map((e) => {'role': e.role, 'content': e.content}).toList();
        final pastMessages = recentHistory.where((h) => (h['content']?.toString().trim().isNotEmpty ?? false) && h['content'] != prompt).toList();
        if (pastMessages.isNotEmpty) {
          final historyBuf = StringBuffer();
          historyBuf.writeln('=== LỊCH SỬ HỘI THOẠI TRƯỚC ĐÓ ===');
          for (final h in pastMessages) {
            final roleName = (h['role'] == 'user') ? 'Người dùng' : 'Trợ lý AI';
            historyBuf.writeln('[$roleName]: ${h['content']}');
          }
          historyBuf.writeln('=== KẾT THÚC LỊCH SỬ HỘI THOẠI ===\n');
          contextualPrompt = '${historyBuf.toString()}\n[Câu hỏi / Yêu cầu mới nhất của Người dùng]:\n$prompt\n\n$promptSuffix';
        }
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
      if (home.isNotEmpty) env['HOME'] = home;

      List<String> args;
      if (m.contains('claude')) {
        if (cliConvId != null && cliConvId.isNotEmpty) {
          args = ['--session-id', cliConvId, '-p', cleanPrompt, '--output-format', 'stream-json', '--verbose', '--dangerously-skip-permissions'];
        } else {
          args = ['-p', cleanPrompt, '--output-format', 'stream-json', '--verbose', '--dangerously-skip-permissions'];
        }
      } else if (m.contains('antigravity') || m == 'agy') {
        if (cliConvId != null && cliConvId.isNotEmpty) {
          args = ['--conversation', cliConvId, '--print', cleanPrompt, '--input-format', 'text', '--output-format', 'stream-json', '--dangerously-skip-permissions', '--effort', 'low', '--print-timeout', '15m0s'];
        } else {
          args = ['--print', cleanPrompt, '--input-format', 'text', '--output-format', 'stream-json', '--dangerously-skip-permissions', '--effort', 'low', '--print-timeout', '15m0s'];
        }
      } else if (m.contains('gemini')) {
        args = ['-p', contextualPrompt];
      } else {
        args = ['-p', contextualPrompt, '--dangerously-skip-permissions'];
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
        final rawResult = fullOutput.toString().trim();
        final result = stripSystemMessages(rawResult);
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
            // Track and store persistent conversation_id for subsequent turns
            final emittedConvId = json['conversation_id']?.toString() ??
                (json['result'] as Map<String, dynamic>?)?['conversation_id']?.toString() ??
                (json['step_update'] as Map<String, dynamic>?)?['conversation_id']?.toString() ??
                json['session_id']?.toString();
            if (emittedConvId != null && emittedConvId.isNotEmpty && emittedConvId != cliConvId) {
              cliConvId = emittedConvId;
              _dbService.setCliConversationId(sessionId, emittedConvId);
            }

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
                } else if (status == 'ERROR' && errorMsg != null && errorMsg.isNotEmpty && fullOutput.isEmpty) {
                  fullOutput.write('\n[Lỗi Antigravity]: $errorMsg\n');
                  onToken('\n[Lỗi Antigravity]: $errorMsg\n');
                }
                // Do not finishSession() here - wait for full process exitCode!
              } else if (event == 'error') {
                final err = json['error']?.toString() ?? json['message']?.toString() ?? '';
                if (err.isNotEmpty && fullOutput.isEmpty) {
                  fullOutput.write('\n[Lỗi Antigravity]: $err\n');
                  onToken('\n[Lỗi Antigravity]: $err\n');
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
              } else if (type == 'error') {
                final err = json['error']?.toString() ?? json['message']?.toString() ?? '';
                if (err.isNotEmpty) {
                  fullOutput.write('\n[Lỗi Claude]: $err\n');
                  onToken('\n[Lỗi Claude]: $err\n');
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
