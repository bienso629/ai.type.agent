import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../../models/attachment_item.dart';
import '../../models/chat_message.dart';
import '../../models/server_model.dart';
import 'adb_manager_service.dart';
import 'database_service.dart';
import 'local_config_service.dart';
import 'persona_service.dart';
import 'socks5_proxy_service.dart';

class NativeAiService {
  static final NativeAiService _instance = NativeAiService._internal();
  factory NativeAiService() => _instance;
  NativeAiService._internal();

  final LocalConfigService _configService = LocalConfigService();
  final DatabaseService _dbService = DatabaseService();
  final PersonaService _personaService = PersonaService();
  final Socks5ProxyService _socks5Service = Socks5ProxyService();
  final AdbManagerService _adbManagerService = AdbManagerService();

  static const String systemPromptBase = '''Bạn là AI Agent MXH Tự Động - Chuyên gia lên kế hoạch và tự động hóa quy trình nuôi nick, tương tác mạng xã hội trên máy local.
Bạn có quyền hạn điều khiển trực tiếp các hồ sơ nhân vật (profiles), khởi chạy/đóng trình duyệt độc lập theo từng IP/nhân vật, kết nối và điều khiển thiết bị di động (Android AVD / thiết bị ngoại vi qua ADB) để thực thi các kịch bản tự động hóa mà không phụ thuộc vào SSH hay máy chủ từ xa.

CÁC NGUYÊN TẮC HOẠT ĐỘNG:
1. LẬP KẾ HOẠCH & ĐIỀU PHỐI LOCAL PROFILE:
   - Quản lý và tra cứu danh sách nhân vật/profile với IP và cấu hình riêng biệt.
   - Điều khiển mở trình duyệt với profile riêng hoặc khởi động thiết bị máy ảo/ngoại vi để thực hiện các tác vụ tự động hóa như lướt bài, like, tương tác, xem video.

2. TẬP TRUNG TÁC VỤ TỰ ĐỘNG HÓA MXH:
   - Sử dụng các công cụ nội bộ để tương tác trực tiếp với trình duyệt và thiết bị Android cục bộ.
   - BẮT BUỘC: Sau khi gọi hoặc thực thi bất kỳ công cụ (tool/function) nào, bạn PHẢI luôn luôn có câu trả lời bằng văn bản gửi cho người dùng để trình bày chi tiết kết quả, giải thích các bước đã thực hiện hoặc đưa ra phân tích tiếp theo. Tuyệt đối KHÔNG được kết thúc cuộc hội thoại trong im lặng hoặc trả về nội dung rỗng.''';

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
            final localInfo = (att.path != null && att.path!.isNotEmpty)
                ? ' (Đường dẫn local: ${att.path} - Dung lượng: ${att.formattedSize})'
                : ' (Dung lượng: ${att.formattedSize})';
            if (att.isImage) {
              fullUserPrompt += '\n\n--- [Ảnh: ${att.name}$localInfo] --- (Người dùng đính kèm ảnh local)';
            } else {
              fullUserPrompt += '\n\n--- [Tệp: ${att.name}$localInfo] ---\n${att.content}';
            }
          }
        }

        // Add current user message
        messages.add({'role': 'user', 'content': fullUserPrompt});

        final tools = [
          {
            'type': 'function',
            'function': {
              'name': 'list_profiles',
              'description': 'Lấy danh sách các nhân vật/hồ sơ (profiles) nuôi nick hiện có cùng IP, thông tin avatar, thiết bị cấu hình.',
              'parameters': {
                'type': 'object',
                'properties': {},
              }
            }
          },
          {
            'type': 'function',
            'function': {
              'name': 'open_profile_browser',
              'description': 'Mở trình duyệt riêng biệt cho một nhân vật/hồ sơ theo IP để tự động hóa tương tác mạng xã hội trên web.',
              'parameters': {
                'type': 'object',
                'properties': {
                  'ip': {
                    'type': 'string',
                    'description': 'Địa chỉ IP hoặc định danh của nhân vật'
                  },
                  'url': {
                    'type': 'string',
                    'description': 'Đường dẫn trang web mạng xã hội muốn mở (ví dụ: https://facebook.com, https://tiktok.com, https://youtube.com)'
                  }
                },
                'required': ['ip']
              }
            }
          },
          {
            'type': 'function',
            'function': {
              'name': 'close_profile_browser',
              'description': 'Đóng cửa sổ trình duyệt của nhân vật theo IP.',
              'parameters': {
                'type': 'object',
                'properties': {
                  'ip': {
                    'type': 'string',
                    'description': 'Địa chỉ IP của nhân vật cần đóng trình duyệt'
                  }
                },
                'required': ['ip']
              }
            }
          },
          {
            'type': 'function',
            'function': {
              'name': 'open_profile_device',
              'description': 'Khởi chạy hoặc kết nối thiết bị Android (máy ảo AVD local hoặc thiết bị ngoại vi qua WiFi/USB) cho nhân vật theo IP.',
              'parameters': {
                'type': 'object',
                'properties': {
                  'ip': {
                    'type': 'string',
                    'description': 'Địa chỉ IP của nhân vật cần chạy thiết bị'
                  },
                  'device_type': {
                    'type': 'string',
                    'description': 'Loại thiết bị: "mobile" hoặc "tablet"',
                    'default': 'mobile'
                  },
                  'avd_name': {
                    'type': 'string',
                    'description': 'Tên máy ảo AVD nếu muốn chỉ định cụ thể'
                  },
                  'remote_address': {
                    'type': 'string',
                    'description': 'Địa chỉ IP:port của điện thoại thật nếu kết nối ngoại vi qua WiFi (ví dụ: 192.168.1.50:5555)'
                  }
                },
                'required': ['ip']
              }
            }
          },
          {
            'type': 'function',
            'function': {
              'name': 'close_profile_device',
              'description': 'Đóng máy ảo hoặc ngắt kết nối thiết bị Android của nhân vật theo IP.',
              'parameters': {
                'type': 'object',
                'properties': {
                  'ip': {
                    'type': 'string',
                    'description': 'Địa chỉ IP của nhân vật cần đóng thiết bị'
                  }
                },
                'required': ['ip']
              }
            }
          },
          {
            'type': 'function',
            'function': {
              'name': 'get_connected_devices',
              'description': 'Lấy danh sách các thiết bị Android (máy ảo AVD, USB hoặc WiFi) đang kết nối nội bộ.',
              'parameters': {
                'type': 'object',
                'properties': {},
              }
            }
          },
          {
            'type': 'function',
            'function': {
              'name': 'execute_adb_command',
              'description': 'Thực thi lệnh ADB trực tiếp trên máy local để điều khiển thiết bị Android (ví dụ tap, swipe, input text, mở app).',
              'parameters': {
                'type': 'object',
                'properties': {
                  'serial': {
                    'type': 'string',
                    'description': 'Số serial hoặc địa chỉ thiết bị (ví dụ emulator-5554 hoặc 192.168.1.50:5555). Để trống nếu chỉ có 1 thiết bị.'
                  },
                  'command': {
                    'type': 'string',
                    'description': 'Lệnh adb cần thực thi (ví dụ: "shell input tap 500 1000", "shell input text hello", "shell am start ...")'
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

              // Parse tool arguments
              Map<String, dynamic> parsedArgs = {};
              try {
                final decoded = jsonDecode(rawArgs);
                if (decoded is Map<String, dynamic>) {
                  parsedArgs = decoded;
                }
              } catch (_) {}

              String cmdLabel = funcName;
              if (parsedArgs.containsKey('ip')) {
                cmdLabel += ' [IP: ${parsedArgs['ip']}]';
              }
              if (parsedArgs.containsKey('url')) {
                cmdLabel += ' -> ${parsedArgs['url']}';
              }
              if (parsedArgs.containsKey('command')) {
                cmdLabel += ': ${parsedArgs['command']}';
              }

              onStatus('Đang thực thi: $cmdLabel');

              final toolItem = ToolExecutionItem(
                tool: funcName,
                command: cmdLabel,
                output: 'Đang thực thi...',
              );
              onTool(toolItem);

              String toolOutput = '';
              try {
                switch (funcName) {
                  case 'list_profiles':
                    final profiles = await _personaService.loadSavedPersonas();
                    if (profiles.isEmpty) {
                      toolOutput = 'Chưa có hồ sơ nhân vật nào được tạo.';
                    } else {
                      final list = profiles.values.map((p) => {
                        'ip': p.ip,
                        'name': p.name,
                        'age': p.age,
                        'gender': p.gender,
                        'bio': p.bio,
                        'device_type': p.deviceType,
                        'avd_name': p.avdName,
                        'use_external_device': p.useExternalDevice,
                        'external_device_address': p.externalDeviceAddress,
                      }).toList();
                      toolOutput = jsonEncode(list);
                    }
                    break;

                  case 'open_profile_browser':
                    final ip = parsedArgs['ip']?.toString().trim() ?? '';
                    final url = parsedArgs['url']?.toString().trim();
                    if (ip.isEmpty) {
                      toolOutput = 'Lỗi: Thiếu tham số IP nhân vật.';
                      break;
                    }
                    final servers = await _configService.getServers();
                    final activeServer = servers.firstWhere(
                      (s) => s.isSelected,
                      orElse: () => servers.isNotEmpty
                          ? servers.first
                          : ServerModel.fromJson(cfg),
                    );
                    final success = await _socks5Service.launchBrowserWithSocks5(
                      server: activeServer,
                      ip: ip,
                      startUrl: url,
                    );
                    toolOutput = success
                        ? 'Đã mở trình duyệt thành công cho profile IP: $ip${url != null ? ' tại $url' : ''}.'
                        : 'Không thể khởi chạy trình duyệt cho IP: $ip.';
                    break;

                  case 'close_profile_browser':
                    final ip = parsedArgs['ip']?.toString().trim() ?? '';
                    if (ip.isEmpty) {
                      toolOutput = 'Lỗi: Thiếu tham số IP nhân vật.';
                      break;
                    }
                    await _socks5Service.closeBrowserForIp(ip);
                    toolOutput = 'Đã đóng trình duyệt cho profile IP: $ip.';
                    break;

                  case 'open_profile_device':
                    final ip = parsedArgs['ip']?.toString().trim() ?? '';
                    final devType = parsedArgs['device_type']?.toString().trim() ?? 'mobile';
                    final avdName = parsedArgs['avd_name']?.toString().trim();
                    final remoteAddr = parsedArgs['remote_address']?.toString().trim();
                    if (ip.isEmpty) {
                      toolOutput = 'Lỗi: Thiếu tham số IP nhân vật.';
                      break;
                    }
                    final serversDev = await _configService.getServers();
                    final activeServerDev = serversDev.firstWhere(
                      (s) => s.isSelected,
                      orElse: () => serversDev.isNotEmpty
                          ? serversDev.first
                          : ServerModel.fromJson(cfg),
                    );
                    final success = await _socks5Service.launchDeviceWithSocks5(
                      server: activeServerDev,
                      ip: ip,
                      deviceType: devType,
                      avdName: avdName,
                      remoteDeviceAddress: remoteAddr,
                    );
                    toolOutput = success
                        ? 'Đã khởi chạy thiết bị Android thành công cho IP: $ip (loại: $devType).'
                        : 'Không thể khởi chạy thiết bị Android cho IP: $ip.';
                    break;

                  case 'close_profile_device':
                    final ip = parsedArgs['ip']?.toString().trim() ?? '';
                    if (ip.isEmpty) {
                      toolOutput = 'Lỗi: Thiếu tham số IP nhân vật.';
                      break;
                    }
                    await _socks5Service.closeDeviceForIp(ip);
                    toolOutput = 'Đã đóng thiết bị Android cho profile IP: $ip.';
                    break;

                  case 'get_connected_devices':
                    final devs = await _socks5Service.getConnectedAdbDevices();
                    toolOutput = devs.isEmpty ? 'Không có thiết bị Android nào đang kết nối.' : jsonEncode(devs);
                    break;

                  case 'execute_adb_command':
                    final adbCmd = parsedArgs['command']?.toString().trim() ?? '';
                    final serial = parsedArgs['serial']?.toString().trim();
                    if (adbCmd.isEmpty) {
                      toolOutput = 'Lỗi: Lệnh ADB rỗng.';
                      break;
                    }
                    final adbBin = await _adbManagerService.resolveAdbPath();
                    final List<String> args = [];
                    if (serial != null && serial.isNotEmpty) {
                      args.addAll(['-s', serial]);
                    }
                    final parts = adbCmd.split(RegExp(r'\s+'));
                    if (parts.isNotEmpty && parts.first.toLowerCase() == 'adb') {
                      parts.removeAt(0);
                    }
                    args.addAll(parts);
                    final procRes = await Process.run(adbBin, args);
                    final stdoutStr = procRes.stdout.toString().trim();
                    final stderrStr = procRes.stderr.toString().trim();
                    toolOutput = stdoutStr.isNotEmpty ? stdoutStr : (stderrStr.isNotEmpty ? stderrStr : 'Lệnh thực thi thành công (Exit code: ${procRes.exitCode}).');
                    break;

                  default:
                    toolOutput = 'Công cụ $funcName không được hỗ trợ.';
                    break;
                }
              } catch (e) {
                toolOutput = 'Lỗi thực thi công cụ $funcName: $e';
              }

              final finishedTool = ToolExecutionItem(
                tool: funcName,
                command: cmdLabel,
                output: toolOutput,
              );
              allExecutedTools.add(finishedTool);
              onTool(finishedTool);

              executedToolResults.add({
                'tool_call_id': toolCallId,
                'content': toolOutput,
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

        // If tools were executed but AI didn't emit text narrative, synthesize clear report
        if (finalReply.isEmpty && allExecutedTools.isNotEmpty) {
          final buffer = StringBuffer();
          buffer.writeln('Đã thực hiện xong các tác vụ:');
          for (final t in allExecutedTools) {
            buffer.writeln('- **${t.command}**');
            if (t.output.isNotEmpty) {
              final cleanOut = t.output.length > 200 ? '${t.output.substring(0, 200)}...' : t.output;
              buffer.writeln('  > $cleanOut');
            }
          }
          finalReply = buffer.toString().trim();
          onToken(finalReply);
        } else if (finalReply.isEmpty) {
          finalReply = 'Đã hoàn tất thao tác.';
          onToken(finalReply);
        }

        // Save assistant message to Database
        final assistantMsg = ChatMessageModel(
          sessionId: sessionId,
          role: 'assistant',
          content: finalReply,
          model: targetModel,
          toolExecutions: allExecutedTools,
          createdAt: DateTime.now(),
        );
        await _dbService.insertMessage(assistantMsg);
        onDone(finalReply);
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
