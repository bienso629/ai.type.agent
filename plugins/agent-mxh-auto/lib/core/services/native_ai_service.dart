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
        final defaultModel = cfg['ai_model']?.toString() ?? 'glm-5.3';
        final targetModel = (model != null && model.isNotEmpty) ? model : defaultModel;

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

        // If user selected a CLI agent (e.g. claude-cli, gemini-cli, ollama...)
        if (_isCliModel(targetModel)) {
          await _runCliAgent(
            sessionId: sessionId,
            cliName: targetModel,
            prompt: message,
            attachments: attachments,
            history: history,
            workingDir: workingDir,
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

        var baseUrl = cfg['proxy_base_url']?.toString() ?? 'https://api.mitom.ai/v1';
        if (!LocalConfigService.isValidMitomProxyUrl(baseUrl)) {
          onError('Cấu hình Proxy Base URL không hợp lệ. Chỉ chấp nhận domain thuộc *.mitom.ai');
          return;
        }
        final apiKey = cfg['proxy_api_key']?.toString() ?? '';

        if (baseUrl.endsWith('/')) {
          baseUrl = baseUrl.substring(0, baseUrl.length - 1);
        }

        // Build System Prompt
        String sysPrompt = systemPromptBase;
        if (workingDir != null && workingDir.isNotEmpty) {
          if (workingDir.startsWith('=== DANH SÁCH NHÂN VẬT ĐƯỢC CHỈ ĐỊNH') || workingDir.contains('👤 Nhân vật:')) {
            sysPrompt += '\n\n$workingDir\n\n🎯 QUY TẮC BẮT BUỘC VỀ ĐA NHÂN VẬT (MULTI-PERSONAS SCOPE):\n'
                '- Bạn CHỈ ĐƯỢC THAO TÁC / ĐÓNG VAI / ĐIỀU KHIỂN CÁC NHÂN VẬT TRÊN ĐÚNG VỚI IP TƯƠNG ỨNG ĐÃ ĐƯỢC CẤP.\n'
                '- KHI DANH SÁCH CÓ TỪ 2 NHÂN VẬT TRỞ LÊN: Nếu người dùng yêu cầu hành động chung (ví dụ: mở trình duyệt, truy cập trang web, mở thiết bị giả lập, nuôi nick, tương tác), bạn BẮT BUỘC PHẢI THỰC HIỆN CHO TOÀN BỘ TẤT CẢ CÁC NHÂN VẬT có trong danh sách trên bằng cách truyền toàn bộ danh sách IP vào tham số `ips` (hoặc gọi công cụ lần lượt cho từng IP). Tuyệt đối KHÔNG ĐƯỢC chỉ mở cho 1 nhân vật đầu tiên rồi dừng lại báo xong.';
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
              'description': 'Mở trình duyệt riêng biệt cho một hoặc nhiều nhân vật/hồ sơ theo IP để tự động hóa tương tác mạng xã hội trên web. Khi có nhiều nhân vật cần mở đồng thời, truyền danh sách vào tham số "ips".',
              'parameters': {
                'type': 'object',
                'properties': {
                  'ip': {
                    'type': 'string',
                    'description': 'Địa chỉ IP hoặc định danh của một nhân vật duy nhất.'
                  },
                  'ips': {
                    'type': 'array',
                    'items': {'type': 'string'},
                    'description': 'Danh sách các địa chỉ IP của toàn bộ nhân vật cần mở trình duyệt đồng loạt.'
                  },
                  'url': {
                    'type': 'string',
                    'description': 'Đường dẫn trang web mạng xã hội muốn mở (ví dụ: https://facebook.com, https://tiktok.com, https://youtube.com)'
                  }
                }
              }
            }
          },
          {
            'type': 'function',
            'function': {
              'name': 'close_profile_browser',
              'description': 'Đóng cửa sổ trình duyệt của một hoặc nhiều nhân vật theo IP.',
              'parameters': {
                'type': 'object',
                'properties': {
                  'ip': {
                    'type': 'string',
                    'description': 'Địa chỉ IP của nhân vật cần đóng trình duyệt'
                  },
                  'ips': {
                    'type': 'array',
                    'items': {'type': 'string'},
                    'description': 'Danh sách IP của các nhân vật cần đóng trình duyệt đồng loạt'
                  }
                }
              }
            }
          },
          {
            'type': 'function',
            'function': {
              'name': 'open_profile_device',
              'description': 'Khởi chạy hoặc kết nối thiết bị Android (máy ảo AVD local hoặc thiết bị ngoại vi qua WiFi/USB) cho một hoặc nhiều nhân vật theo IP.',
              'parameters': {
                'type': 'object',
                'properties': {
                  'ip': {
                    'type': 'string',
                    'description': 'Địa chỉ IP của nhân vật cần chạy thiết bị'
                  },
                  'ips': {
                    'type': 'array',
                    'items': {'type': 'string'},
                    'description': 'Danh sách IP của các nhân vật cần khởi chạy thiết bị Android đồng loạt'
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
                }
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
                    final List<String> targetIps = [];
                    if (parsedArgs['ips'] is List) {
                      for (final item in parsedArgs['ips']) {
                        final s = item?.toString().trim() ?? '';
                        if (s.isNotEmpty && !targetIps.contains(s)) targetIps.add(s);
                      }
                    }
                    final singleIp = parsedArgs['ip']?.toString().trim() ?? '';
                    if (singleIp.isNotEmpty && !targetIps.contains(singleIp)) {
                      targetIps.add(singleIp);
                    }
                    final url = parsedArgs['url']?.toString().trim();
                    if (targetIps.isEmpty) {
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

                    final List<String> successList = [];
                    final List<String> failList = [];
                    for (final tip in targetIps) {
                      onStatus('Đang mở trình duyệt cho IP: $tip...');
                      final success = await _socks5Service.launchBrowserWithSocks5(
                        server: activeServer,
                        ip: tip,
                        startUrl: url,
                      );
                      if (success) {
                        successList.add(tip);
                      } else {
                        failList.add(tip);
                      }
                    }
                    if (failList.isEmpty) {
                      toolOutput = 'Đã mở trình duyệt thành công cho toàn bộ ${successList.length} nhân vật (${successList.join(', ')})${url != null ? ' tại $url' : ''}.';
                    } else if (successList.isEmpty) {
                      toolOutput = 'Không thể khởi chạy trình duyệt cho các IP: ${failList.join(', ')}.';
                    } else {
                      toolOutput = 'Đã mở trình duyệt cho: ${successList.join(', ')}. Thất bại tại: ${failList.join(', ')}.';
                    }
                    break;

                  case 'close_profile_browser':
                    final List<String> closeIps = [];
                    if (parsedArgs['ips'] is List) {
                      for (final item in parsedArgs['ips']) {
                        final s = item?.toString().trim() ?? '';
                        if (s.isNotEmpty && !closeIps.contains(s)) closeIps.add(s);
                      }
                    }
                    final sCloseIp = parsedArgs['ip']?.toString().trim() ?? '';
                    if (sCloseIp.isNotEmpty && !closeIps.contains(sCloseIp)) {
                      closeIps.add(sCloseIp);
                    }
                    if (closeIps.isEmpty) {
                      toolOutput = 'Lỗi: Thiếu tham số IP nhân vật.';
                      break;
                    }
                    for (final tip in closeIps) {
                      await _socks5Service.closeBrowserForIp(tip);
                    }
                    toolOutput = 'Đã đóng trình duyệt cho các profile IP: ${closeIps.join(', ')}.';
                    break;

                  case 'open_profile_device':
                    final List<String> targetDevIps = [];
                    if (parsedArgs['ips'] is List) {
                      for (final item in parsedArgs['ips']) {
                        final s = item?.toString().trim() ?? '';
                        if (s.isNotEmpty && !targetDevIps.contains(s)) targetDevIps.add(s);
                      }
                    }
                    final singleDevIp = parsedArgs['ip']?.toString().trim() ?? '';
                    if (singleDevIp.isNotEmpty && !targetDevIps.contains(singleDevIp)) {
                      targetDevIps.add(singleDevIp);
                    }
                    final devType = parsedArgs['device_type']?.toString().trim() ?? 'mobile';
                    final avdName = parsedArgs['avd_name']?.toString().trim();
                    final remoteAddr = parsedArgs['remote_address']?.toString().trim();
                    if (targetDevIps.isEmpty) {
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

                    final List<String> devSuccessList = [];
                    final List<String> devFailList = [];
                    for (final tip in targetDevIps) {
                      onStatus('Đang khởi chạy thiết bị cho IP: $tip...');
                      final success = await _socks5Service.launchDeviceWithSocks5(
                        server: activeServerDev,
                        ip: tip,
                        deviceType: devType,
                        avdName: avdName,
                        remoteDeviceAddress: remoteAddr,
                      );
                      if (success) {
                        devSuccessList.add(tip);
                      } else {
                        devFailList.add(tip);
                      }
                    }
                    if (devFailList.isEmpty) {
                      toolOutput = 'Đã khởi chạy thiết bị Android thành công cho toàn bộ ${devSuccessList.length} nhân vật (${devSuccessList.join(', ')}, loại: $devType).';
                    } else if (devSuccessList.isEmpty) {
                      toolOutput = 'Không thể khởi chạy thiết bị Android cho các IP: ${devFailList.join(', ')}.';
                    } else {
                      toolOutput = 'Đã mở thiết bị cho: ${devSuccessList.join(', ')}. Thất bại tại: ${devFailList.join(', ')}.';
                    }
                    break;

                  case 'close_profile_device':
                    final List<String> closeDevIps = [];
                    if (parsedArgs['ips'] is List) {
                      for (final item in parsedArgs['ips']) {
                        final s = item?.toString().trim() ?? '';
                        if (s.isNotEmpty && !closeDevIps.contains(s)) closeDevIps.add(s);
                      }
                    }
                    final sCloseDevIp = parsedArgs['ip']?.toString().trim() ?? '';
                    if (sCloseDevIp.isNotEmpty && !closeDevIps.contains(sCloseDevIp)) {
                      closeDevIps.add(sCloseDevIp);
                    }
                    if (closeDevIps.isEmpty) {
                      toolOutput = 'Lỗi: Thiếu tham số IP nhân vật.';
                      break;
                    }
                    for (final tip in closeDevIps) {
                      await _socks5Service.closeDeviceForIp(tip);
                    }
                    toolOutput = 'Đã đóng thiết bị Android cho các profile IP: ${closeDevIps.join(', ')}.';
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

  Future<void> _runCliAgent({
    required String sessionId,
    required String cliName,
    required String prompt,
    List<AttachmentItem>? attachments,
    List<Map<String, dynamic>>? history,
    String? workingDir,
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

    // Check persistent conversation ID
    String? cliConvId = await _dbService.getCliConversationId(sessionId);

    try {
      final workDir = (workingDir != null && Directory(workingDir).existsSync())
          ? workingDir
          : Directory.current.path;

      // Xây dựng nội dung prompt đầy đủ bao gồm tệp/ảnh đính kèm nếu có
      String fullPromptWithAttachments = prompt;
      if (attachments != null && attachments.isNotEmpty) {
        final attBuf = StringBuffer();
        attBuf.writeln('\n\n=== TỆP & ẢNH ĐÍNH KÈM TỪ NGƯỜI DÙNG ===');
        for (final att in attachments) {
          final localInfo = (att.path != null && att.path!.isNotEmpty)
              ? ' (Đường dẫn local: ${att.path} - Dung lượng: ${att.formattedSize})'
              : ' (Dung lượng: ${att.formattedSize})';
          if (att.isImage) {
            attBuf.writeln('\n--- [Ảnh: ${att.name}$localInfo] ---');
            if (att.path != null && att.path!.isNotEmpty) {
              attBuf.writeln('Đường dẫn file ảnh trên hệ điều hành: ${att.path}');
            }
          } else {
            attBuf.writeln('\n--- [Tệp: ${att.name}$localInfo] ---');
            if (att.path != null && att.path!.isNotEmpty) {
              attBuf.writeln('Đường dẫn file trên hệ điều hành: ${att.path}');
            }
            if (att.content.isNotEmpty) {
              attBuf.writeln('Nội dung tệp:\n${att.content}');
            }
          }
        }
        attBuf.writeln('=== KẾT THÚC DANH SÁCH ĐÍNH KÈM ===');
        fullPromptWithAttachments += attBuf.toString();
      }

      final promptSuffix = (customPromptTemplate != null && customPromptTemplate.trim().isNotEmpty)
          ? customPromptTemplate.trim()
          : '(Yêu cầu: Viết tiếng Việt có đầy đủ dấu thanh chuẩn chính tả, tuyệt đối không dùng emoji hay icon trong câu trả lời, trình bày bằng định dạng markdown kỹ thuật chuẩn)';
      final cleanPrompt = '$fullPromptWithAttachments\n\n$promptSuffix';

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
          contextualPrompt = '${historyBuf.toString()}\n[Câu hỏi / Yêu cầu mới nhất của Người dùng]:\n$fullPromptWithAttachments\n\n$promptSuffix';
        }
      }

      // Augmented PATH environment so subprocesses are always found
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
      if (!env.containsKey('DISPLAY') || env['DISPLAY']!.isEmpty) {
        env['DISPLAY'] = Platform.environment['DISPLAY'] ?? ':0';
      }
      if (Platform.environment.containsKey('WAYLAND_DISPLAY')) {
        env['WAYLAND_DISPLAY'] = Platform.environment['WAYLAND_DISPLAY']!;
      }
      if (Platform.environment.containsKey('XDG_RUNTIME_DIR')) {
        env['XDG_RUNTIME_DIR'] = Platform.environment['XDG_RUNTIME_DIR']!;
      }
      if (Platform.environment.containsKey('XDG_CURRENT_DESKTOP')) {
        env['XDG_CURRENT_DESKTOP'] = Platform.environment['XDG_CURRENT_DESKTOP']!;
      }

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
          // Plain text fallback
        }

        fullOutput.writeln(line);
        onToken('$line\n');
      });

      process.stderr.transform(utf8.decoder).listen((data) {
        if (!isCancelled() && !hasFinished) {
          errOutput.write(data);
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
