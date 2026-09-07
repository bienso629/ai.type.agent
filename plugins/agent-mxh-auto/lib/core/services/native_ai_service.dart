import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../models/attachment_item.dart';
import '../../models/chat_message.dart';
import 'database_service.dart';
import 'local_config_service.dart';
import 'native_ssh_service.dart';

class NativeAiService {
  static final NativeAiService _instance = NativeAiService._internal();
  factory NativeAiService() => _instance;
  NativeAiService._internal();

  final LocalConfigService _configService = LocalConfigService();
  final NativeSshService _sshService = NativeSshService();
  final DatabaseService _dbService = DatabaseService();

  static const String systemPromptBase = '''Bạn là MXH tự động - Kỹ sư DevOps Linux thực chiến cấp cao.
Bạn có quyền thực thi lệnh bash/shell thực tế trên máy chủ qua công cụ `execute_terminal_command`.

CÁC QUY TẮC BẮT BUỘC (VI PHẠM LÀ LỖI NGHIÊM TRỌNG):

1. THỰC THI TRIỆT ĐỂ ĐẾN CÙNG - KHÔNG DỪNG NỬA CHỪNG (END-TO-END EXECUTION):
   - Khi nhận yêu cầu (cài website, upload code, giải nén, cài node/npm, build, tạo virtualhost, cấp SSL, sửa lỗi...): Bạn PHẢI CHỦ ĐỘNG GỌI `execute_terminal_command` chạy liên tục toàn bộ các bước cho đến khi XONG HOÀN TOÀN và KIỂM CHỨNG THÀNH CÔNG.
   - TUYỆT ĐỐI CẤM dừng lại ở câu nói lấp lửng/dự định (như "Giờ copy...", "Tiếp theo sẽ build...", "Đang kiểm tra..."). Đã định làm gì là PHẢI GỌI TOOL CHẠY LỆNH ĐÓ NGAY LẬP TỨC.
   - Luôn kiểm tra kết quả bước trước. Nếu lệnh phát sinh lỗi, tự động chẩn đoán và chạy lệnh sửa lỗi ngay.
   - Sau khi cài đặt/build xong, LUÔN CHẠY lệnh kiểm tra thực tế (ví dụ: `curl -ILs http://<domain>` hoặc `systemctl status <service>`) để xác nhận website/dịch vụ đã hoạt động trước khi đưa ra câu trả lời cuối cùng.

2. VỊ TRÍ TỆP TIN & MÃ NGUỒN TẢI LÊN:
   - Các tệp đính kèm người dùng tải lên được lưu tại: `/opt/ai_agent/uploads/<tên_tệp>`.
   - Khi người dùng yêu cầu upload/cài đặt mã nguồn vào một thư mục (ví dụ `/var/www/vhosts/<domain>/httpdocs/`), bạn hãy kiểm tra tệp zip/tar trong `/opt/ai_agent/uploads/`, giải nén hoặc copy vào thư mục đích, chown phân quyền phù hợp và tiến hành cài đặt dependencies / build.

3. TẬP TRUNG ĐÚNG 100% TRỌNG TÂM YÊU CẦU (STRICT SCOPE):
   - CHỈ xử lý ĐÚNG DUY NHẤT domain/dịch vụ mà người dùng đang yêu cầu trong tin nhắn mới nhất.
   - TUYỆT ĐỐI KHÔNG kiểm tra lại các website/service cũ không liên quan.

4. BÁO CÁO KẾT QUẢ RÕ RÀNG, CHÍNH XÁC (ZERO FLUFF):
   - Khi hoàn tất, báo cáo rõ:
     + Trạng thái: ✅ ĐÃ HOÀN TẤT hoặc ❌ GẶP LỖI CỤ THỂ.
     + Kết quả kiểm tra (Domain, Port, HTTP Code, Đường dẫn).
   - Không chào hỏi, không cảm ơn, không văn mẫu xã giao.
''';

  StreamSubscription<String> streamChatMessage({
    required String sessionId,
    required String message,
    String? model,
    List<AttachmentItem>? attachments,
    List<Map<String, dynamic>>? history,
    String? workingDir,
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
        var baseUrl = cfg['proxy_base_url']?.toString() ?? 'https://api.mitom.ai/v1';
        if (!LocalConfigService.isValidMitomProxyUrl(baseUrl)) {
          onError('Cấu hình Proxy Base URL không hợp lệ. Chỉ chấp nhận domain thuộc *.mitom.ai');
          return;
        }
        final apiKey = cfg['proxy_api_key']?.toString() ?? '';
        final defaultModel = cfg['ai_model']?.toString() ?? 'glm-5.3';
        final targetModel = (model != null && model.isNotEmpty) ? model : defaultModel;

        if (baseUrl.endsWith('/')) {
          baseUrl = baseUrl.substring(0, baseUrl.length - 1);
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

        // Build System Prompt
        String sysPrompt = systemPromptBase;
        if (workingDir != null && workingDir.isNotEmpty) {
          if (workingDir.startsWith('=== DANH SÁCH NHÂN VẬT ĐƯỢC CHỈ ĐỊNH') || workingDir.contains('👤 Nhân vật:')) {
            sysPrompt += '\n\n$workingDir\n\n🎯 QUY TẮC BẮT BUỘC: Bạn CHỈ ĐƯỢC THAO TÁC / ĐÓNG VAI / ĐIỀU KHIỂN CÁC NHÂN VẬT TRÊN ĐÚNG VỚI IP TƯƠNG ỨNG ĐÃ ĐƯỢC CẤP.';
          } else {
            sysPrompt += '\n\n🎯 PHẠM VI LÀM VIỆC MỤC TIÊU: `$workingDir`\nMọi tác vụ terminal/tài khoản phải tuân thủ phạm vi này.';
          }
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
            final remoteInfo = (att.remotePath != null && att.remotePath!.isNotEmpty)
                ? ' (Đã lưu trên VPS tại: ${att.remotePath} - Dung lượng: ${att.formattedSize})'
                : '';
            if (att.isImage) {
              fullUserPrompt += '\n\n--- [Ảnh: ${att.name}$remoteInfo] --- (Người dùng đính kèm ảnh)';
            } else {
              fullUserPrompt += '\n\n--- [Tệp: ${att.name}$remoteInfo] ---\n${att.content}';
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
              'description': 'Thực thi lệnh terminal bash/shell trên server Linux.',
              'parameters': {
                'type': 'object',
                'properties': {
                  'command': {
                    'type': 'string',
                    'description': 'Lệnh bash cần chạy trên máy chủ'
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

              final cmdOutput = await _sshService.executeCommand(cmd, workingDir: workingDir);

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
        if (!isCancelled) {
          onError('Lỗi xử lý AI: $e');
        }
      }
    }();

    controller.onCancel = () {
      isCancelled = true;
    };

    return controller.stream.listen((_) {});
  }
}
