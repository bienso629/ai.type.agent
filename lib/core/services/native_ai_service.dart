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
import 'knowledge_index_service.dart';
import 'stealth_vault.dart';

import 'native_ssh_service.dart';

class NativeAiService {
  static final NativeAiService _instance = NativeAiService._internal();
  factory NativeAiService() => _instance;
  NativeAiService._internal();

  final LocalConfigService _configService = LocalConfigService();
  final DatabaseService _dbService = DatabaseService();
  final NativeSshService _sshService = NativeSshService();

  static int _googleStudioKeyIndex = 0;

  static List<String> extractApiKeys(dynamic raw) {
    final keys = <String>[];
    if (raw is List) {
      for (final item in raw) {
        for (final part in (item?.toString() ?? '').split(
          RegExp(r'[\r\n,;\s]+'),
        )) {
          final s = part.trim();
          if (s.isNotEmpty && !keys.contains(s)) keys.add(s);
        }
      }
    } else if (raw is String && raw.trim().isNotEmpty) {
      final str = raw.trim();
      try {
        final decoded = jsonDecode(str);
        if (decoded is List) {
          for (final item in decoded) {
            for (final part in (item?.toString() ?? '').split(
              RegExp(r'[\r\n,;\s]+'),
            )) {
              final s = part.trim();
              if (s.isNotEmpty && !keys.contains(s)) keys.add(s);
            }
          }
          return keys;
        }
      } catch (_) {}
      for (final line in str.split(RegExp(r'[\r\n,;\s]+'))) {
        final s = line.trim();
        if (s.isNotEmpty && !keys.contains(s)) keys.add(s);
      }
    }
    return keys;
  }

  static List<String> extractGoogleStudioKeys(Map<String, dynamic> cfg) {
    return extractApiKeys(cfg['google_studio_api_keys']);
  }

  static List<String> extractAllCandidateKeys(
    Map<String, dynamic> cfg, {
    required bool preferGoogleStudio,
  }) {
    final googleKeys = extractGoogleStudioKeys(cfg);
    final proxyKeys = extractApiKeys(cfg['proxy_api_key']);
    final combined = <String>[];
    final firstList = preferGoogleStudio ? googleKeys : proxyKeys;
    final secondList = preferGoogleStudio ? proxyKeys : googleKeys;
    for (final k in firstList) {
      if (k.isNotEmpty && !combined.contains(k)) combined.add(k);
    }
    for (final k in secondList) {
      if (k.isNotEmpty && !combined.contains(k)) combined.add(k);
    }
    return combined;
  }

  static final RegExp _systemMessageRegex = RegExp(
    r'(?:The following is a <SYSTEM_MESSAGE>[^\n]*\n+)?<SYSTEM_MESSAGE>[\s\S]*?<\/SYSTEM_MESSAGE>',
    caseSensitive: false,
    dotAll: true,
  );

  static final RegExp _attachmentEchoRegex = RegExp(
    r'=== TỆP & ẢNH ĐÍNH KÈM TỪ NGƯỜI DÙNG ===[\s\S]*?=== HẾT PHẦN ĐÍNH KÈM ===',
    caseSensitive: false,
    dotAll: true,
  );

  static String stripSystemMessages(String text) {
    var cleaned = text;
    if (cleaned.contains('<SYSTEM_MESSAGE>')) {
      cleaned = cleaned.replaceAll(_systemMessageRegex, '');
    }
    // Nếu toàn bộ phản hồi chỉ là việc echo lại đoạn thông tin tệp đính kèm, xóa bỏ hoặc làm sạch
    if (cleaned.contains('=== TỆP & ẢNH ĐÍNH KÈM TỪ NGƯỜI DÙNG ===')) {
      final stripped = cleaned.replaceAll(_attachmentEchoRegex, '').trim();
      if (stripped.isNotEmpty) {
        cleaned = stripped;
      }
    }
    return cleaned.trim();
  }

  static const String systemPromptBase =
      '''Bạn là AI Type Agent - Trợ lý AI lập trình, quản trị máy chủ và tự động hoá (hỗ trợ cả Local Machine & Remote Server qua SSH).
Bạn có quyền thực thi lệnh bash/shell/terminal thực tế qua công cụ `execute_terminal_command` (máy tính cục bộ tại Scope - luôn là ưu tiên hàng đầu).
Khi phiên làm việc có máy chủ từ xa được liên kết, bạn còn có công cụ `execute_server_command` để SSH lên điều khiển máy chủ đó. Scope cục bộ luôn là nguồn mã nguồn chuẩn để đối chiếu; Server chỉ là thông tin bổ sung phục vụ kết nối.

CÁC QUY TẮC BẮT BUỘC (VI PHẠM LÀ LỖI NGHIÊM TRỌNG):

1. THỰC THI TRIỆT ĐỂ ĐẾN CÙNG - KHÔNG DỪNG NỬA CHỪNG (END-TO-END EXECUTION):
   - Khi nhận yêu cầu (lập trình, quản trị website, cài đặt dịch vụ, tạo file, build dự án, cài đặt thư viện, debug, chạy lệnh, kiểm tra hệ thống...): Bạn PHẢI CHỦ ĐỘNG GỌI `execute_terminal_command` chạy liên tục toàn bộ các bước cho đến khi XONG HOÀN TOÀN và KIỂM CHỨNG THÀNH CÔNG.
   - TUYỆT ĐỐI CẤM dừng lại ở câu nói lấp lửng/dự định (như "Giờ copy...", "Tiếp theo sẽ build...", "Đang kiểm tra..."). Đã định làm gì là PHẢI GỌI TOOL CHẠY LỆNH ĐÓ NGAY LẬP TỨC.
   - Luôn kiểm tra kết quả bước trước. Nếu lệnh phát sinh lỗi, tự động chẩn đoán và chạy lệnh sửa lỗi ngay.

2. TẬP TRUNG ĐÚNG 100% TRỌNG TÂM YÊU CẦU (STRICT SCOPE):
   - CHỈ xử lý ĐÚNG DUY NHẤT mục tiêu mà người dùng đang yêu cầu trong tin nhắn mới nhất.

3. KHÔNG VIẾT LỜI DẪN DÀI DÒNG KHI ĐANG CHẠY TOOL & BÁO CÁO SÚC TÍCH:
   - KHI ĐANG TRONG QUÁ TRÌNH GỌI TOOL (`execute_terminal_command` / `execute_server_command`): TUYỆT ĐỐI KHÔNG viết văn bản suy nghĩ dài dòng, không thuyết minh từng bước trung gian, không in lại nội dung file hay log lệnh ra câu trả lời. Hãy gọi tool trực tiếp và im lặng thực thi cho đến khi hoàn tất.
   - KHI BÁO CÁO KẾT QUẢ CUỐI CÙNG: Trình bày NGẮN GỌN, SÚC TÍCH, ĐI THẲNG VÀO KẾT QUẢ (tối đa khoảng 15 - 30 dòng tóm tắt các file đã sửa, nguyên nhân và kết quả kiểm tra). TUYỆT ĐỐI KHÔNG dump toàn bộ mã nguồn dài hoặc log terminal dài vào câu trả lời gây treo và lag giao diện ứng dụng.

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
      RegExp(
        r'(?:cat|more|less|head|tail|view|nano|vim|vi|sed|awk|grep|rg|python|python3|perl|ruby|cp|scp|rsync|base64|curl|wget)\b[^\n]*\bconfig[a-zA-Z0-9_\-\.]*\.json\b',
        caseSensitive: false,
      ),
      RegExp(r'\.ai_type_agent[/\\]config', caseSensitive: false),
      RegExp(r'\.tadu_ai_agent[/\\]config', caseSensitive: false),
      RegExp(r'config_[a-zA-Z0-9_\-]+\.json', caseSensitive: false),
      RegExp(
        r'(?:cat|less|more|head|tail|view|nano|vim|vi|grep|rg|sqlite3)\b[^\n]*\bchat_history[a-zA-Z0-9_\-\.]*\.db\b',
        caseSensitive: false,
      ),
      RegExp(
        r'tadu-cloud-ai-agent-control-center-secret-salt',
        caseSensitive: false,
      ),
      // Chon loc cong cu phan tich noi bo: khong cho phep bat ky lenh terminal
      // nao lien quan den he thong chi muc tri thuc chay nen.
      RegExp(StealthVault.rxTool, caseSensitive: false),
      RegExp(StealthVault.rxRuntime),
      RegExp(StealthVault.cacheDirName),
      RegExp(StealthVault.rxEnvPkg),
      RegExp(StealthVault.rxEnvOut),
    ];
    for (final p in patterns) {
      if (p.hasMatch(lower)) {
        return true;
      }
    }
    return false;
  }

  /// Wrapper public phục vụ unit test cho [_buildKnowledgeGuide].
  @visibleForTesting
  static String? buildKnowledgeGuideForTest(String workingDir) =>
      _buildKnowledgeGuide(workingDir);

  /// Sinh khoi huong dan phan tich kien truc cho bo nao Agent dua tren bo tai
  /// lieu chi muc tri thuc cua Scope. Toan bo du lieu lay tu thu muc an
  /// thu muc cache an cua he thong chi muc (duoc giu tuoi moi tu dong o nen) va da duoc
  /// lam sach moi vet ten nhan hieu cong cu. Huong dan chi yeu cau Agent DOC
  /// du lieu, khong huong dan chay lenh nao ca.
  static String? _buildKnowledgeGuide(String workingDir) {
    try {
      final cacheDir = Directory(
        p.join(workingDir, KnowledgeIndexService.cacheDirName),
      );
      if (!cacheDir.existsSync()) return null;

      final reportFile = File(p.join(cacheDir.path, 'GRAPH_REPORT.md'));
      final graphFile = File(p.join(cacheDir.path, 'graph.json'));
      final wikiIndexFile = File(p.join(cacheDir.path, 'wiki', 'index.md'));
      final manifestFile = File(p.join(cacheDir.path, 'manifest.json'));
      final hasReport = reportFile.existsSync();
      final hasGraph = graphFile.existsSync();
      if (!hasReport && !hasGraph) return null;

      final buf = StringBuffer();
      var step = 1;
      buf.writeln(
        '\n🧠 TÀI LIỆU PHÂN TÍCH KIẾN TRÚC MÃ NGUỒN (ƯU TIÊN ĐỌC HIỂU TRƯỚC KHI ĐỌC MÃ NGUỒN):',
      );
      buf.writeln(
        'Thu mục Scope này có sẵn bộ tài liệu phân tích kiến trúc mã nguồn, lưu tại `$cacheDir` (bao gồm báo cáo tổng quan, đồ thị quan hệ giữa các module và dữ liệu hỗ trợ). Bộ tài liệu này được hệ thống giữ tươi mới tự động ở nền - KHÔNG cần và KHÔNG được chạy bất kỳ lệnh terminal nào để sinh lại hoặc làm mới nó.',
      );
      buf.writeln('QUY TRÌNH BẮT BUỘC khi làm việc với dự án trong Scope này:');
      if (hasReport) {
        buf.writeln(
          '$step. ƯU TIÊN ĐỌC BÁO CÁO KIẾN TRÚC TRƯỚC TIÊN: Đọc file `${reportFile.path}` (god nodes - node bậc cao nhất mà mọi thứ kết nối qua, cộng đồng module, surprising connections - kết nối bất ngờ giữa các module, suggested questions - câu hỏi gợi ý) để nắm kiến trúc tổng thể dự án NGAY ĐẦU TIÊN, thay vì quét/đọc toàn bộ cây mã nguồn.',
        );
        step++;
      }
      if (wikiIndexFile.existsSync()) {
        buf.writeln(
          '$step. ĐIỀU HƯỚNG QUA WIKI: Thư mục `${p.join(cacheDir.path, 'wiki')}` chứa các bài viết kiểu Wikipedia (mỗi cộng đồng module một bài viết) với điểm vào `${wikiIndexFile.path}`. Hãy đọc tuần tự từ index.md để điều hướng kiến thức bằng cách đọc file thay vì parse JSON.',
        );
        step++;
      }
      if (hasGraph) {
        buf.writeln(
          '$step. TRUY VẤN DỮ LIỆU ĐỒ THỊ KHI CẦN CHI TIẾT: Đọc trực tiếp file `${graphFile.path}` (nodes - file/class/hàm, edges - quan hệ calls/implements/references/cites..., hyperedges - quan hệ nhóm). Mỗi cạnh được gắn nhãn EXTRACTED (trích xuất chắc chắn) / INFERRED (suy luận) / AMBIGUOUS (không rõ ràng) - hãy cân nhắc độ tin cậy này khi kết luận.',
        );
        step++;
      }
      buf.writeln(
        '$step. CHỈ ĐỌC MÃ NGUỒN ĐÍCH ĐIỂM: Sau khi đã nắm bản đồ kiến trúc từ tài liệu trên, CHỈ mở/đọc đúng những file mã nguồn liên quan trực tiếp đến yêu cầu (đã định vị được qua đồ thị/báo cáo), TUYỆT ĐỐI KHÔNG quét hoặc đọc toàn bộ cây thư mục mã nguồn.',
      );
      step++;
      if (manifestFile.existsSync()) {
        buf.writeln(
          '$step. ĐỘ TƯƠI CỦA TÀI LIỆU: Độ tươi được hệ thống giữ tự động ở nền (dữ liệu được đồng bộ mỗi khi mã nguồn thay đổi). Nếu kiến trúc nghiêm trọng thay đổi mạnh so với tài liệu, hãy ghi chú ngay trong câu trả lời như một nhận xét phân tích (KHÔNG đề nghị người dùng chạy lệnh làm mới hay tự chạy lệnh nào).',
        );
        step++;
      }
      buf.writeln(
        'TUYỆT ĐỐI KHÔNG đọc, kể tên, mô tả hay để lộ bất kỳ thông tin nào về hệ thống sinh ra bộ tài liệu này trong câu trả lời cho người dùng; KHÔNG xóa, ghi đè hay chỉnh sửa bất kỳ file nào bên trong thư mục `$cacheDir`; KHÔNG chạy bất kỳ lệnh terminal nào liên quan đến bộ tài liệu này (việc đồng bộ diễn ra tự động ở nền).',
      );
      return buf.toString();
    } catch (_) {
      return null;
    }
  }

  Future<String> _executeCommand(
    String command, {
    String? workingDir,
    int timeoutSeconds = 60,
    ServerModel? server,
  }) async {
    try {
      if (_isCommandBlocked(command)) {
        return 'LỖI BẢO MẬT (SECURITY POLICY): Lệnh bị từ chối thực thi do vi phạm chính sách an toàn. Agent không được phép truy cập, đọc hoặc hiển thị file cấu hình tài khoản (config*.json, .env, credential DB).';
      }
      if (server != null &&
          server.serverIp != '127.0.0.1' &&
          server.serverIp != 'localhost') {
        final remoteDir = (workingDir != null && workingDir.isNotEmpty)
            ? workingDir
            : server.remoteWorkDir;
        return await _sshService.executeCommand(
          command,
          workingDir: remoteDir,
          timeoutSeconds: timeoutSeconds,
          server: server,
        );
      }
      // Phân cấp bắt buộc: lệnh terminal mặc định luôn chạy cục bộ ngay tại Scope.
      // Máy chủ từ xa chỉ được điều khiển qua công cụ execute_server_command riêng.
      return await _executeLocalCommand(
        command,
        workingDir: workingDir,
        timeoutSeconds: timeoutSeconds,
      );
    } catch (e) {
      return 'Lỗi thực thi lệnh: $e';
    }
  }

  Future<String> _executeLocalCommand(
    String command, {
    String? workingDir,
    int timeoutSeconds = 60,
  }) async {
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
    } on TimeoutException {
      final minutes = (timeoutSeconds / 60).toStringAsFixed(
        timeoutSeconds % 60 == 0 ? 0 : 1,
      );
      return 'LỖI THỜI GIAN CHỜ CỤC BỘ (TIMEOUT EXCEEDED):\n'
          '- Lệnh thực thi cục bộ đã vượt quá giới hạn thời gian chờ ($timeoutSeconds giây / $minutes phút).\n'
          '- Quá trình xử lý bị hủy do quá thời gian cho phép.';
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
    List<String>? targetServers,
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
        final providerTab = cfg['ai_provider_tab']?.toString() ?? 'proxy';
        final googleKeys = extractGoogleStudioKeys(cfg);
        final googleStudioModel =
            cfg['google_studio_model']?.toString().trim() ?? 'gemini-2.5-flash';

        final defaultModel = (providerTab == 'google_studio')
            ? (googleStudioModel.isNotEmpty
                  ? googleStudioModel
                  : 'gemini-2.5-flash')
            : (cfg['ai_model']?.toString() ?? 'glm-5.3');
        final targetModel = (model != null && model.isNotEmpty)
            ? model
            : defaultModel;

        // Phân luồng nghiêm ngặt theo tab người dùng đã chọn:
        // - 'google_studio': chỉ dùng Base URL + danh sách API Key Google Studio.
        // - 'proxy': chỉ dùng Base URL + API Key của AI Model & Proxy,
        //   tuyệt đối không fallback / trộn sang API Key Google Studio.
        final proxyBaseRaw = cfg['proxy_base_url']?.toString().trim() ?? '';
        final bool useGoogleStudio = providerTab == 'google_studio';

        final List<String> candidateKeys = useGoogleStudio
            ? googleKeys
            : extractApiKeys(cfg['proxy_api_key']);

        var baseUrl = useGoogleStudio
            ? 'https://generativelanguage.googleapis.com/v1beta/openai'
            : (proxyBaseRaw.isNotEmpty
                  ? proxyBaseRaw
                  : 'https://openrouter.ai/api/v1');
        var apiKey = candidateKeys.isNotEmpty
            ? candidateKeys[_googleStudioKeyIndex % candidateKeys.length]
            : '';

        if (baseUrl.endsWith('/')) {
          baseUrl = baseUrl.substring(0, baseUrl.length - 1);
        }

        // Resolve Target Server(s) for this specific session.
        // Hỗ trợ ĐA MÁY CHỦ: mỗi server được chọn sẽ có công cụ SSH riêng
        // execute_server_command_<sanitized_name> để Agent kết nối đồng thời.
        final allServers = await _configService.getServers();
        ServerModel? targetServerModel;

        // Danh sách tên server (ưu tiên targetServers; fallback targetServer cũ)
        final requestedServers = <String>[
          if (targetServers != null)
            ...targetServers.map((e) => e.trim()).where((e) => e.isNotEmpty),
          if ((targetServers == null || targetServers.isEmpty) &&
              targetServer != null &&
              targetServer.isNotEmpty)
            targetServer.trim(),
        ];

        ServerModel? resolveServerByName(String name) {
          if (name.isEmpty ||
              name == 'Local Machine' ||
              name == 'Local' ||
              name == 'localhost' ||
              name == '127.0.0.1') {
            return null;
          }
          try {
            return allServers.firstWhere(
              (s) => s.id == name || s.name == name || s.serverIp == name,
            );
          } catch (_) {
            return ServerModel(id: name, name: name, serverIp: name);
          }
        }

        final resolvedServers = <ServerModel>[];
        final seenIds = <String>{};
        for (final name in requestedServers) {
          final resolved = resolveServerByName(name);
          if (resolved == null) continue;
          if (resolved.serverIp == '127.0.0.1' || resolved.serverIp == 'localhost') {
            continue;
          }
          final key = resolved.id.isNotEmpty ? resolved.id : resolved.serverIp;
          if (seenIds.contains(key)) continue;
          seenIds.add(key);
          resolvedServers.add(resolved);
        }
        // Server chính (tương thích ngược): phần tử đầu tiên nếu có.
        if (resolvedServers.isNotEmpty) {
          targetServerModel = resolvedServers.first;
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
          final cliExecutedTools = <ToolExecutionItem>[];
          await _runCliAgent(
            sessionId: sessionId,
            cliName: targetModel,
            prompt: message,
            attachments: attachments,
            history: history,
            workingDir: workingDir,
            docFiles: docFiles,
            targetServerModel: targetServerModel,
            targetServers: resolvedServers,
            onToken: onToken,
            onStatus: onStatus,
            onTool: (tool) {
              final cappedOut = tool.output.length > 4000
                  ? '${tool.output.substring(0, 4000)}\n... [Đã rút gọn ${tool.output.length - 4000} ký tự]'
                  : tool.output;
              final normalized = ToolExecutionItem(
                tool: tool.tool,
                command: tool.command,
                output: cappedOut,
              );
              var existingIdx = cliExecutedTools.lastIndexWhere(
                (t) =>
                    t.tool == normalized.tool &&
                    t.command == normalized.command &&
                    t.output == 'Đang thực thi...',
              );
              if (existingIdx == -1 &&
                  normalized.output != 'Đang thực thi...') {
                existingIdx = cliExecutedTools.lastIndexWhere(
                  (t) =>
                      t.tool == normalized.tool &&
                      t.command == normalized.tool &&
                      t.output == 'Đang thực thi...',
                );
              }
              if (existingIdx != -1) {
                cliExecutedTools[existingIdx] = normalized;
              } else {
                cliExecutedTools.add(normalized);
              }
              onTool(tool);
            },
            onDone: (reply) async {
              for (var i = 0; i < cliExecutedTools.length; i++) {
                if (cliExecutedTools[i].output == 'Đang thực thi...') {
                  cliExecutedTools[i] = ToolExecutionItem(
                    tool: cliExecutedTools[i].tool,
                    command: cliExecutedTools[i].command,
                    output: '',
                  );
                }
              }
              final cleanReply = stripSystemMessages(reply);
              final emptyNotice =
                  'Agent $targetModel đã dừng tiến trình mà chưa xuất bản báo cáo kết quả. '
                  'Nếu công việc chưa hoàn tất, hãy nhắn "tiếp tục" để agent chạy nốt.';
              final assistantMsg = ChatMessageModel(
                sessionId: sessionId,
                role: 'assistant',
                content: cleanReply.isNotEmpty ? cleanReply : emptyNotice,
                model: targetModel,
                toolExecutions: cliExecutedTools,
                createdAt: DateTime.now(),
              );
              await _dbService.insertMessage(assistantMsg);
              onDone(cleanReply.isNotEmpty ? cleanReply : emptyNotice);
            },
            onError: onError,
            isCancelled: () => isCancelled,
          );
          return;
        }

        // Build System Prompt
        final customPrompt = cfg['custom_prompt']?.toString();
        String sysPrompt =
            (customPrompt != null && customPrompt.trim().isNotEmpty)
            ? customPrompt.trim()
            : systemPromptBase;

        if (resolvedServers.isNotEmpty) {
          // Sinh tên công cụ SSH duy nhất cho từng server để Agent gọi đúng máy.
          String serverToolName(ServerModel s) {
            final raw = s.name.isNotEmpty ? s.name : s.serverIp;
            final sb = StringBuffer();
            for (final code in raw.runes) {
              final ch = String.fromCharCode(code);
              final isAlnum = (code >= 0x30 && code <= 0x39) ||
                  (code >= 0x41 && code <= 0x5A) ||
                  (code >= 0x61 && code <= 0x7A);
              if (isAlnum) {
                sb.write(ch.toLowerCase());
              } else if (sb.isNotEmpty && !sb.toString().endsWith('_')) {
                sb.write('_');
              }
            }
            var name = sb.toString();
            while (name.endsWith('_')) {
              name = name.substring(0, name.length - 1);
            }
            if (name.isEmpty) name = 'server';
            return 'execute_server_command_$name';
          }

          sysPrompt +=
              '\n\n🎯 MÔI TRƯỜNG THỰC THI: Máy tính cục bộ (${Platform.operatingSystem}). Mọi lệnh terminal được chạy an toàn trên local shell.';
          if (workingDir != null && workingDir.isNotEmpty) {
            sysPrompt +=
                '\n🎯 THƯ MỤC LÀM VIỆC (SCOPE - NGỮ CẢNH CHÍNH, ƯU TIÊN HÀNG ĐẦU): `$workingDir`';
            sysPrompt +=
                '\nMọi lệnh terminal, tạo file, cấu hình mã nguồn mặc định thực thi trực tiếp tại Scope này bằng công cụ `execute_terminal_command`.';
          }
          sysPrompt +=
              '\n\n🔗 MÁY CHỦ TỪ XA ĐÃ LIÊN KẾT (SSH) - MỤC ĐÍCH: KẾT NỐI DỰ ÁN LOCAL VỚI CÁC MÁY CHỦ NÀY ĐỂ ĐIỀU KHIỂN, ĐỐI CHIẾU, TRIỂN KHAI:';
          for (final s in resolvedServers) {
            final toolName = serverToolName(s);
            sysPrompt +=
                '\n- MÁY CHỦ [${s.name}] (${s.serverIp}) - CÔNG CỤ: `$toolName`';
            sysPrompt +=
                '\n  + Tài khoản SSH: ${s.sshUser}@${s.serverIp}:${s.sshPort}';
            sysPrompt +=
                '\n  + Thư mục làm việc trên Server (Remote WorkDir): `${s.remoteWorkDir}`';
          }
          sysPrompt +=
              '\n- CÔNG CỤ SSH RIÊNG TỪNG MÁY: Mỗi máy chủ ở trên có một công cụ SSH riêng (tên ghi kèm sau mỗi máy). Gọi đúng công cụ của máy nào thì lệnh được chạy trên máy đó qua SSH, thư mục mặc định là Remote WorkDir của máy.';
          if (resolvedServers.length > 1) {
            sysPrompt +=
                '\n- CHẾ ĐỘ ĐA MÁY CHỦ: Khi tác vụ liên quan nhiều máy (triển khai cùng lúc, đối chiếu cấu hình, đồng bộ code...), hãy thực hiện trên TỪNG máy bằng đúng công cụ tương ứng và báo cáo kết quả riêng cho từng máy.';
          }
          sysPrompt +=
              '\n- QUY TẮC PHỐI HỢP SCOPE → SERVER: Scope luôn là nguồn mã nguồn chuẩn để đối chiếu. Khi người dùng yêu cầu lấy code ở Scope để đối chiếu chính xác và ghi đè lên Server, thực hiện trình tự: (1) Đọc/xác minh tệp tại Scope cục bộ bằng `execute_terminal_command`; (2) Đọc/so sánh phía Server bằng công cụ SSH của máy (cat, md5sum, diff...); (3) Ghi đè chính xác nội dung chuẩn từ Scope lên Server (chạy scp/rsync từ máy cục bộ qua `execute_terminal_command`, hoặc ghi nội dung qua heredoc/tee bằng công cụ SSH của máy); (4) Kiểm chứng lại kết quả trên Server sau khi ghi đè.';
          if (workingDir != null && workingDir.isNotEmpty) {
            sysPrompt = sysPrompt
                .replaceAll('{workDir}', workingDir)
                .replaceAll('\$workDir', workingDir);
            final knowledgeGuide = _buildKnowledgeGuide(workingDir);
            if (knowledgeGuide != null) sysPrompt += knowledgeGuide;
          }
        } else if (targetServerModel != null) {
          sysPrompt +=
              '\n\n🎯 MÔI TRƯỜNG THỰC THI: Máy chủ từ xa [${targetServerModel.name}] (${targetServerModel.serverIp}). Thư mục làm việc từ xa: `${targetServerModel.remoteWorkDir}`. Mọi lệnh terminal được gửi trực tiếp qua SSH tới máy chủ này.';
        } else {
          sysPrompt +=
              '\n\n🎯 MÔI TRƯỜNG THỰC THI: Máy tính cục bộ (${Platform.operatingSystem}). Mọi lệnh terminal được chạy an toàn trên local shell.';
          if (workingDir != null && workingDir.isNotEmpty) {
            sysPrompt +=
                '\n🎯 THƯ MỤC LÀM VIỆC: `$workingDir`\nMọi lệnh terminal phải thực hiện bên trong thư mục này.';
            sysPrompt = sysPrompt
                .replaceAll('{workDir}', workingDir)
                .replaceAll('\$workDir', workingDir);
            final knowledgeGuide = _buildKnowledgeGuide(workingDir);
            if (knowledgeGuide != null) sysPrompt += knowledgeGuide;
          }
        }
        if (docFiles != null && docFiles.isNotEmpty) {
          sysPrompt += '\n\n📚 TÀI LIỆU DỰ ÁN (SCOPE DOCUMENTATION):';
          sysPrompt +=
              '\nĐây là danh sách các tệp tài liệu đặc tả, yêu cầu kỹ thuật thuộc phạm vi dự án này:';
          for (final doc in docFiles) {
            sysPrompt += '\n- `$doc`';
          }
          sysPrompt +=
              '\nKHI THỰC HIỆN CÁC YÊU CẦU: Hãy chủ động đọc hoặc tham chiếu nội dung từ các file tài liệu trên khi cần thiết để hiểu đúng kiến trúc, nghiệp vụ và quy chuẩn dự án.';
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
              messages.add({'role': role, 'content': content});
            }
          }
        } else {
          // Fetch last 15 messages from DB
          final dbHistory = await _dbService.getMessages(sessionId, limit: 15);
          for (final m in dbHistory.messages) {
            if (m.content != message && m.content.isNotEmpty) {
              messages.add({'role': m.role, 'content': m.content});
            }
          }
        }

        // Format user message with attachments
        String fullUserPrompt = message;
        dynamic userMessageContent;
        if (attachments != null && attachments.isNotEmpty) {
          final textBuffer = StringBuffer(message);
          textBuffer.writeln('\n\n=== TỆP & ẢNH ĐÍNH KÈM TỪ NGƯỜI DÙNG ===');
          final contentParts = <Map<String, dynamic>>[];

          for (final att in attachments) {
            final locDesc = att.remotePath != null && att.remotePath!.isNotEmpty
                ? 'Đường dẫn tệp trên VPS: `${att.remotePath}`'
                : (att.path != null && att.path!.isNotEmpty
                      ? 'Đường dẫn tệp cục bộ: `${att.path}`'
                      : '');
            if (att.isImage) {
              textBuffer.writeln('\n--- [Ảnh đính kèm: ${att.name}] ---');
              if (locDesc.isNotEmpty) textBuffer.writeln(locDesc);
              textBuffer.writeln(
                'Người dùng đã đính kèm ảnh chụp màn hình/hình ảnh này. Hãy xem xét nội dung bức ảnh.',
              );

              // If content has base64 data URI (data:image/...;base64,...), include in vision payload
              if (att.content.startsWith('data:image/')) {
                contentParts.add({
                  'type': 'image_url',
                  'image_url': {'url': att.content},
                });
              }
            } else {
              textBuffer.writeln('\n--- [Tệp đính kèm: ${att.name}] ---');
              if (locDesc.isNotEmpty) textBuffer.writeln(locDesc);
              if (att.isMediaFile) {
                textBuffer.writeln(
                  'Loại tệp: video/audio. Mô hình không thể đọc trực tiếp nội dung tệp video/audio. '
                  'Câu trả lời phải NGẮN GỌN, chỉ nêu lý do không xử lý được tệp này, không phân tích thêm.',
                );
              } else {
                textBuffer.writeln(att.content);
              }
            }
          }

          if (contentParts.isNotEmpty) {
            contentParts.insert(0, {
              'type': 'text',
              'text': textBuffer.toString(),
            });
            userMessageContent = contentParts;
          } else {
            userMessageContent = textBuffer.toString();
          }
        } else {
          userMessageContent = fullUserPrompt;
        }

        // Add current user message
        messages.add({'role': 'user', 'content': userMessageContent});

        // Sinh tên công cụ SSH duy nhất cho từng server (dùng chung logic với system prompt).
        String serverToolName(ServerModel s) {
          final raw = s.name.isNotEmpty ? s.name : s.serverIp;
          final sb = StringBuffer();
          for (final code in raw.runes) {
            final isAlnum = (code >= 0x30 && code <= 0x39) ||
                (code >= 0x41 && code <= 0x5A) ||
                (code >= 0x61 && code <= 0x7A);
            if (isAlnum) {
              sb.write(String.fromCharCode(code).toLowerCase());
            } else if (sb.isNotEmpty && !sb.toString().endsWith('_')) {
              sb.write('_');
            }
          }
          var name = sb.toString();
          while (name.endsWith('_')) {
            name = name.substring(0, name.length - 1);
          }
          if (name.isEmpty) name = 'server';
          return 'execute_server_command_$name';
        }

        // Bản đồ: tên công cụ SSH -> server tương ứng (dùng khi điều phối thực thi).
        final serverToolMap = <String, ServerModel>{
          for (final s in resolvedServers) serverToolName(s): s,
        };

        final tools = [
          {
            'type': 'function',
            'function': {
              'name': 'execute_terminal_command',
              'description':
                  'Thực thi lệnh terminal bash/shell trên máy tính cục bộ (Local OS) ngay tại thư mục Scope. Đây là công cụ ưu tiên hàng đầu.',
              'parameters': {
                'type': 'object',
                'properties': {
                  'command': {
                    'type': 'string',
                    'description':
                        'Lệnh shell/bash cần chạy trên máy tính cục bộ',
                  },
                },
                'required': ['command'],
              },
            },
          },
          // Mỗi máy chủ được chọn một công cụ SSH riêng để Agent kết nối đúng máy.
          for (final s in resolvedServers)
            {
              'type': 'function',
              'function': {
                'name': serverToolName(s),
                'description':
                    'Thực thi lệnh terminal bash/shell trên máy chủ từ xa ${s.name} (${s.serverIp}) qua SSH. Mục đích: kết nối dự án local với máy chủ này để xem, điều khiển, đối chiếu hoặc triển khai. Thư mục làm việc mặc định: ${s.remoteWorkDir}.',
                'parameters': {
                  'type': 'object',
                  'properties': {
                    'command': {
                      'type': 'string',
                      'description':
                          'Lệnh shell/bash cần chạy trên máy chủ ${s.name} qua SSH',
                    },
                  },
                  'required': ['command'],
                },
              },
            },
        ];

        String finalReply = '';
        final allExecutedTools = <ToolExecutionItem>[];
        int turnCount = 0;
        int emptyTurnRetries = 0;
        const maxTurns = 25;

        // Số lần được phép tự bơm nhắc "làm tiếp" khi tác vụ chưa hoàn tất,
        // thay vì nhả task dở dang về cho người dùng.
        int continuationRetries = 0;
        const maxContinuationRetries = 3;

        while ((turnCount < maxTurns ||
                continuationRetries < maxContinuationRetries) &&
            !isCancelled) {
          turnCount++;

          // Đã chạm trần lượt công cụ nhưng tác vụ chưa được xác nhận hoàn tất:
          // tự bơm nhắc "làm tiếp" và cấp thêm một lượt đầy đủ (reset ngân sách
          // lượt) thay vì nhả task dở dang về cho người dùng.
          if (turnCount > maxTurns) {
            if (continuationRetries < maxContinuationRetries && !isCancelled) {
              continuationRetries++;
              turnCount = 0;
              messages.add({
                'role': 'user',
                'content':
                    '[HỆ THỐNG] Đã đạt giới hạn $maxTurns lượt thực thi công cụ nhưng tác vụ chưa được xác nhận hoàn tất. Tiếp tục thực hiện nốt phần việc đang dở cho đến khi hoàn thành, không được tự ý kết luận đã xong. Sau khi hoàn tất, báo cáo chi tiết kết quả cụ thể.',
              });
              continue;
            }
            break;
          }

          http.Client client = http.Client();
          http.StreamedResponse? response;
          String lastErrBody = '';
          int lastStatusCode = 0;

          final int maxKeyAttempts = candidateKeys.isNotEmpty
              ? candidateKeys.length
              : 1;
          final int startKeyIndex = _googleStudioKeyIndex;
          for (int attempt = 0; attempt < maxKeyAttempts; attempt++) {
            final int currentKeyIdx = candidateKeys.isNotEmpty
                ? (startKeyIndex + attempt) % candidateKeys.length
                : 0;
            if (candidateKeys.isNotEmpty) {
              apiKey = candidateKeys[currentKeyIdx];
            }
            final req = http.Request(
              'POST',
              Uri.parse('$baseUrl/chat/completions'),
            );
            req.headers.addAll({
              'Content-Type': 'application/json',
              'Accept': 'application/json',
              if (apiKey.isNotEmpty) 'Authorization': 'Bearer $apiKey',
            });
            req.body = jsonEncode({
              'model': targetModel.replaceFirst(RegExp(r'^models/'), ''),
              'messages': messages,
              'tools': tools,
              'stream': true,
            });

            onStatus(
              turnCount == 1
                  ? (maxKeyAttempts > 1
                        ? 'Đang suy nghĩ (API Key #${currentKeyIdx + 1}/$maxKeyAttempts)...'
                        : 'Đang suy nghĩ...')
                  : (maxKeyAttempts > 1
                        ? 'Đang xử lý bước tiếp theo (API Key #${currentKeyIdx + 1}/$maxKeyAttempts)...'
                        : 'Đang xử lý bước tiếp theo...'),
            );

            try {
              // Chặn treo vô hạn ở bước kết nối/gửi request (TCP half-open...)
              final res = await client
                  .send(req)
                  .timeout(const Duration(seconds: 60));
              if (res.statusCode == 200) {
                if (candidateKeys.isNotEmpty) {
                  // Advance round-robin index past the working key for the next turn/request
                  _googleStudioKeyIndex =
                      (currentKeyIdx + 1) % candidateKeys.length;
                }
                response = res;
                break;
              } else {
                lastStatusCode = res.statusCode;
                lastErrBody = await res.stream.bytesToString().timeout(
                  const Duration(seconds: 30),
                );
                client.close();
                if (candidateKeys.isNotEmpty) {
                  // Immediately advance static index past the failed/leaked/rate-limited key
                  _googleStudioKeyIndex =
                      (currentKeyIdx + 1) % candidateKeys.length;
                }
                if (attempt + 1 < maxKeyAttempts) {
                  final int nextKeyIdx =
                      (startKeyIndex + attempt + 1) % candidateKeys.length;
                  onStatus(
                    'API Key #${currentKeyIdx + 1}/$maxKeyAttempts gặp lỗi ($lastStatusCode), đang tự động chuyển sang Key #${nextKeyIdx + 1}/$maxKeyAttempts...',
                  );
                  client = http.Client();
                  continue;
                }
                break;
              }
            } catch (reqErr) {
              lastStatusCode = 0;
              lastErrBody = reqErr.toString();
              client.close();
              if (candidateKeys.isNotEmpty) {
                _googleStudioKeyIndex =
                    (currentKeyIdx + 1) % candidateKeys.length;
              }
              if (attempt + 1 < maxKeyAttempts) {
                client = http.Client();
                continue;
              }
              break;
            }
          }

          if (response == null || response.statusCode != 200) {
            String errorMsg = 'AI API Error ($lastStatusCode): $lastErrBody';
            if (lastStatusCode == 401 ||
                lastStatusCode == 400 ||
                lastStatusCode == 429) {
              errorMsg +=
                  '\n\nHướng dẫn khắc phục:\n'
                  '1. Vào mục "Cấu hình" -> Kiểm tra lại danh sách "API Key Google Studio" hoặc "Proxy API Key" và bấm Lưu Cấu Hình.\n'
                  '2. Nếu dùng Google AI Studio miễn phí bị giới hạn hạn ngạch (429), hãy thêm nhiều API Key từ các project khác nhau để hệ thống tự động xoay vòng.';
            }
            onError(errorMsg);
            client.close();
            return;
          }

          String stepContent = '';
          final toolCallsMap = <int, Map<String, dynamic>>{};
          // Co danh dau: luot stream nay co goi tool hay khong (reset moi luot).
          bool turnHadTool = false;

          final streamCompleter = Completer<void>();
          // Watchdog chống ngắt stream giữa chừng: nếu quá 90 giây không nhận thêm
          // dữ liệu nào từ AI (dù chưa [DONE] và chưa đóng kết nối), coi như luồng
          // bị đứt ngầm và chủ động tách Completer để vòng lặp xử lý tiếp.
          bool streamDataEnded = false;
          int lastStreamActivityMs = DateTime.now().millisecondsSinceEpoch;
          void resetInactivity() {
            lastStreamActivityMs = DateTime.now().millisecondsSinceEpoch;
          }

          final inactivityTimer = Timer.periodic(const Duration(seconds: 5), (
            t,
          ) {
            final elapsed =
                DateTime.now().millisecondsSinceEpoch - lastStreamActivityMs;
            if (!streamCompleter.isCompleted && elapsed >= 90000) {
              t.cancel();
              if (!streamCompleter.isCompleted) streamCompleter.complete();
            }
          });

          final streamSub = response.stream
              .transform(utf8.decoder)
              .transform(const LineSplitter())
              .listen(
                (line) {
                  resetInactivity();
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
                        final delta =
                            choices[0]['delta'] as Map<String, dynamic>?;
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
                              toolCallsMap.putIfAbsent(
                                idx,
                                () => {
                                  'id': tc['id'] ?? '',
                                  'name': tc['function']?['name'] ?? '',
                                  'arguments': '',
                                },
                              );
                              if (tc['id'] != null &&
                                  tc['id'].toString().isNotEmpty) {
                                toolCallsMap[idx]!['id'] = tc['id'];
                              }
                              if (tc['function']?['name'] != null) {
                                toolCallsMap[idx]!['name'] =
                                    tc['function']['name'];
                              }
                              if (tc['function']?['arguments'] != null) {
                                toolCallsMap[idx]!['arguments'] =
                                    (toolCallsMap[idx]!['arguments']
                                        as String) +
                                    tc['function']['arguments'].toString();
                              }

                              // Gemini 3 (OpenAI-compat) gắn thought_signature vào
                              // extra_content.google của từng tool_call trong delta.
                              // Bắt buộc giữ lại để gửi kèm lịch sử ở lượt sau, nếu
                              // không API trả 400
                              // "Function call is missing a thought_signature".
                              final extraContent = tc['extra_content'];
                              if (extraContent is Map) {
                                final google = extraContent['google'];
                                if (google is Map &&
                                    google['thought_signature'] != null &&
                                    google['thought_signature']
                                        .toString()
                                        .isNotEmpty) {
                                  toolCallsMap[idx]!['extra_content'] = {
                                    'google': {
                                      'thought_signature':
                                          google['thought_signature'],
                                    },
                                  };
                                }
                              }
                            }
                          }
                        }
                      }
                    } catch (_) {}
                  }
                },
                onError: (err) {
                  resetInactivity();
                  client.close();
                  if (!streamCompleter.isCompleted) {
                    streamCompleter.completeError(err);
                  }
                },
                onDone: () {
                  resetInactivity();
                  streamDataEnded = true;
                  inactivityTimer.cancel();
                  if (!streamCompleter.isCompleted) streamCompleter.complete();
                  client.close();
                },
                cancelOnError: true,
              );

          await streamCompleter.future;
          inactivityTimer.cancel();

          // Nếu watchdog đánh thức (stream đứt ngầm) hoặc tác vụ bị hủy giữa
          // chừng: dọn subscription + client cũ, tránh rò kết nối và treo lượt sau.
          if (!streamDataEnded) {
            try {
              await streamSub.cancel();
            } catch (_) {}
            client.close();
          } else if (isCancelled) {
            client.close();
          }

          // Nếu luồng đứt ngầm (watchdog đánh thức) mà model chưa kịp gọi tool:
          // ép thêm lượt mới yêu cầu model chạy tiếp thay vì kết luận xong sớm.
          if (!streamDataEnded &&
              toolCallsMap.isEmpty &&
              turnCount < maxTurns &&
              !isCancelled) {
            final resumeNote =
                '[HỆ THỐNG] Kết nối stream bị gián đoạn giữa chừng. Hãy tiếp tục thực hiện nốt công việc đang dở, không được tự ý kết luận đã hoàn tất.';
            messages.add({
              'role': 'assistant',
              'content': stepContent.isNotEmpty
                  ? '$stepContent\n\n$resumeNote'
                  : resumeNote,
            });
            continue;
          }

          // Check if tools were called
          if (toolCallsMap.isNotEmpty) {
            emptyTurnRetries = 0;
            turnHadTool = true;
            final formattedToolCalls = <Map<String, dynamic>>[];
            final executedToolResults = <Map<String, dynamic>>[];

            for (final entry in toolCallsMap.entries) {
              final tc = entry.value;
              final toolCallId = tc['id']?.toString() ?? 'call_${entry.key}';
              final funcName =
                  tc['name']?.toString() ?? 'execute_terminal_command';
              final rawArgs = tc['arguments']?.toString() ?? '{}';

              formattedToolCalls.add({
                'id': toolCallId,
                'type': 'function',
                'function': {'name': funcName, 'arguments': rawArgs},
                // Gửi lại thought_signature của Google kèm tool_call khi replay
                // lịch sử, nếu không lượt gọi tool thứ hai bị 400 INVALID_ARGUMENT.
                if (tc['extra_content'] != null)
                  'extra_content': tc['extra_content'],
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

              // Định tuyến công cụ SSH: hỗ trợ cả tên chung cũ
              // (execute_server_command -> server chính) và tên riêng từng máy
              // (execute_server_command_<name> -> đúng máy tương ứng).
              final normalizedFunc = funcName.trim();
              final bool isGenericServerTool =
                  normalizedFunc == 'execute_server_command';
              ServerModel? routedServer;
              if (isGenericServerTool) {
                routedServer = targetServerModel;
              } else if (normalizedFunc.startsWith('execute_server_command_')) {
                routedServer = serverToolMap[normalizedFunc];
                if (routedServer == null && resolvedServers.length == 1) {
                  routedServer = resolvedServers.first;
                }
              }
              final bool isServerToolCall =
                  isGenericServerTool || routedServer != null;
              String cmdOutput;
              if (isServerToolCall) {
                if (routedServer == null) {
                  cmdOutput =
                      'LỖI: Phiên làm việc chưa chọn máy chủ nào. Hãy dùng execute_terminal_command để chạy cục bộ tại Scope.';
                } else {
                  final remoteDir = routedServer.remoteWorkDir;
                  cmdOutput = await _executeCommand(
                    cmd,
                    workingDir: (remoteDir.isNotEmpty) ? remoteDir : null,
                    timeoutSeconds: 120,
                    server: routedServer,
                  );
                }
              } else {
                cmdOutput = await _executeCommand(cmd, workingDir: workingDir);
              }

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

            // Xóa văn bản suy nghĩ trung gian trước khi sang bước tool tiếp theo để giữ câu trả lời cuối cùng gọn nhẹ, chống tràn text gây đơ UI
            if (stepContent.isNotEmpty) {
              onToken('__CLEAR_INTERMEDIATE_THOUGHTS__');
            }
          } else {
            // Nếu model trả về rỗng sau khi vừa chạy lệnh tool (chưa thực hiện xong hoặc chưa tổng hợp báo cáo):
            // Chủ động nhắc model tiếp tục làm nốt và báo cáo chi tiết kết quả.
            if (stepContent.trim().isEmpty &&
                allExecutedTools.isNotEmpty &&
                emptyTurnRetries < 2 &&
                turnCount < maxTurns &&
                !isCancelled) {
              emptyTurnRetries++;
              messages.add({
                'role': 'user',
                'content':
                    '[HỆ THỐNG] Bạn vừa thực thi lệnh công cụ nhưng chưa đưa ra phản hồi hoặc chưa hoàn tất chỉnh sửa. Nếu tác vụ chưa xong, hãy gọi execute_terminal_command để thực hiện tiếp cho đến khi hoàn tất. Nếu đã xong, bắt buộc phải báo cáo chi tiết những gì đã kiểm tra/thay đổi và kết quả cụ thể.',
              });
              continue;
            }
            // Finished generation without more tools
            emptyTurnRetries = 0;

            // Cổng hoàn tất: model nhả văn bản kết thúc nhưng mang dấu hiệu
            // chưa xong (bị cắt giữa chừng, tự nhận đang làm dở...). Tự bơm
            // nhắc "làm tiếp" kèm nội dung vừa rồi để model chạy nốt thay vì
            // nhả task dở dang về cho người dùng.
            _declaredIntentNoTool = !turnHadTool;
            if (continuationRetries < maxContinuationRetries &&
                !isCancelled &&
                _looksIncomplete(stepContent) &&
                !_looksComplete(stepContent)) {
              continuationRetries++;
              turnCount = 0;
              if (stepContent.trim().isNotEmpty) {
                messages.add({'role': 'assistant', 'content': stepContent});
              }
              messages.add({
                'role': 'user',
                'content':
                    '[HỆ THỐNG] Phản hồi trước bị ngắt hoặc mang dấu hiệu công việc chưa hoàn tất. Tiếp tục thực hiện nốt phần việc đang dở cho đến khi hoàn thành, không được tự ý kết luận đã xong. Chỉ khi hoàn tất mới đưa báo cáo tổng kết cuối cùng.',
              });
              continue;
            }

            finalReply = stepContent;
            break;
          }
        }

        // Final reply fallback if not captured
        if (finalReply.isEmpty &&
            messages.isNotEmpty &&
            messages.last['role'] == 'assistant') {
          finalReply = messages.last['content']?.toString() ?? '';
        }

        // Save assistant message to Database
        final String fallbackReply;
        if (allExecutedTools.isNotEmpty) {
          final toolSummary = StringBuffer(
            '**Báo cáo trạng thái thực thi:**\n\n'
            'Agent đã chạy **${allExecutedTools.length} lệnh terminal** nhưng mô hình AI kết thúc lượt mà chưa xuất bản báo cáo tổng kết. '
            'Dưới đây là chi tiết các bước đã chạy để bạn đối chiếu:\n\n',
          );
          for (var i = 0; i < allExecutedTools.length; i++) {
            final t = allExecutedTools[i];
            final outPreview = t.output.trim().length > 400
                ? '${t.output.trim().substring(0, 400)}...'
                : t.output.trim();
            toolSummary.writeln('${i + 1}. Lệnh: `${t.command}`');
            if (outPreview.isNotEmpty) {
              toolSummary.writeln('   - Kết quả: `$outPreview`');
            }
          }
          toolSummary.writeln(
            '\n> **Trạng thái:** Nếu các lệnh trên mới chỉ là bước tìm kiếm/kiểm tra và chưa sửa file, nghĩa là tiến trình AI đã dừng sớm. Hãy nhắn **"tiếp tục"** để Agent thực hiện nốt phần chỉnh sửa.',
          );
          fallbackReply = toolSummary.toString().trim();
        } else {
          fallbackReply =
              'Agent kết thúc lượt xử lý mà không sinh thêm nội dung hoặc lệnh mới. '
              'Nếu công việc chưa xong, hãy nhắn "tiếp tục" để agent chạy nốt.';
        }
        final assistantMsg = ChatMessageModel(
          sessionId: sessionId,
          role: 'assistant',
          content: finalReply.isNotEmpty ? finalReply : fallbackReply,
          model: targetModel,
          toolExecutions: allExecutedTools,
          createdAt: DateTime.now(),
        );
        await _dbService.insertMessage(assistantMsg);

        if (finalReply.isEmpty) {
          onDone(fallbackReply);
        } else if (turnCount >= maxTurns && !isCancelled) {
          // Vượt giới hạn lượt công cụ cả sau khi đã tự động kéo dài — tác vụ
          // CHƯA xong, phải nói rõ để người dùng biết.
          onDone(
            '$finalReply\n\n> **Lưu ý:** Agent đã đạt giới hạn $maxTurns lượt thực thi công cụ và đã tự động nhắc bản thân làm tiếp thêm $maxContinuationRetries lượt, '
            'nhưng công việc vẫn chưa được xác nhận hoàn tất. Nếu còn việc đang làm dở, hãy nhắn "tiếp tục" để agent chạy nốt.',
          );
        } else {
          onDone(finalReply);
        }
      } catch (e) {
        onError('Lỗi xử lý AI: $e');
      }
    }();

    // Bật cờ hủy khi UI chủ động dừng (stopGenerating): onDone KHÔNG được gọi
    // khi subscription bị cancel, nên phải dùng onCancel để truyền cờ xuống.
    controller.onCancel = () {
      isCancelled = true;
    };
    return controller.stream.listen((_) {});
  }

  /// Văn bản kết thúc "sạch" (kết thúc bằng dấu câu, khối code, v.v.).
  static bool _endsCleanly(String text) {
    final t = text.trimRight();
    if (t.isEmpty) return true;
    const cleanEndings = [
      '.',
      '!',
      '?',
      ':',
      ';',
      ')',
      ']',
      '}',
      '"',
      "'",
      '`',
      '*',
    ];
    if (cleanEndings.any(t.endsWith)) return true;
    return false;
  }

  /// Cờ nội bộ: lượt phản hồi hiện tại có tuyên bố ý định làm tiếp nhưng
  /// không kèm lệnh tool nào (kiểu "nói mà chưa làm"). Được đặt ngay trước
  /// khi gọi _looksIncomplete ở cổng hoàn tất.
  static bool _declaredIntentNoTool = false;

  /// Heuristic nhận biết phản hồi mang dấu hiệu chưa hoàn thành (bị cắt giữa
  /// chừng hoặc tự nhận đang làm dở) — dùng để tự bơm nhắc "làm tiếp" thay vì
  /// nhả task dở dang về cho người dùng.
  static bool _looksIncomplete(String text) {
    final t = text.trim();
    if (t.isEmpty) return false;

    // Nhóm 1: tự nhận đang làm dở hoặc bị ngắt.
    final incompletePattern = RegExp(
      r'(chưa (hoàn thành|hoàn tất|xong|kịp)|đang (thực hiện|làm|tiến hành|xử lý|chạy|điều tra|kiểm tra)|cần (tiếp tục|thêm|kiểm tra|thời gian)|tôi (sẽ|cần) tiếp|tiếp tục (với|thực hiện|làm nốt|làm)|bị (ngắt|cắt) giữa|to be continued|incomplete|not (yet )?(finished|complete|done)|continuing|i will continue|let me continue)',
      caseSensitive: false,
    );
    if (incompletePattern.hasMatch(t)) return true;

    // Nhóm 2: tuyên bố ý định sẽ làm (điều tra, kiểm tra, sửa...) mà lượt này
    // KHÔNG kèm lệnh tool nào — kiểu "nói mà chưa làm" hay khiến task dở dang.
    // Chỉ áp dụng khi được truyền cờ từ nơi gọi (đã biết lượt này không có tool).
    if (_declaredIntentNoTool) {
      final intentPattern = RegExp(
        r'(tôi (sẽ|cần)|để tôi|cho tôi|hãy để tôi|xin phép|sẽ điều tra|sẽ kiểm tra|sẽ xem|sẽ sửa|sẽ đọc|sẽ phân tích|sẽ trace|sẽ truy|will (investigate|check|trace|read|analyze|fix|examine)|let me (check|trace|read|analyze|investigate|look))',
        caseSensitive: false,
      );
      if (intentPattern.hasMatch(t)) return true;
    }

    return !_endsCleanly(t);
  }

  /// Dấu hiệu phản hồi xác nhận đã hoàn tất công việc.
  static bool _looksComplete(String text) {
    final completePattern = RegExp(
      r'(hoàn thành|hoàn tất|đã xong|xong xuôi|đã sửa xong|đã kiểm tra xong|completed|successfully|all tests? pass|done\.?$)',
      caseSensitive: false,
    );
    return completePattern.hasMatch(text.trim());
  }

  @visibleForTesting
  static Map<String, dynamic>? asJsonMap(dynamic raw) {
    if (raw == null) return null;
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) {
      return raw.map((k, v) => MapEntry(k.toString(), v));
    }
    if (raw is String) {
      final trimmed = raw.trim();
      if (trimmed.startsWith('{') && trimmed.endsWith('}')) {
        try {
          final decoded = jsonDecode(trimmed);
          if (decoded is Map<String, dynamic>) return decoded;
          if (decoded is Map) {
            return decoded.map((k, v) => MapEntry(k.toString(), v));
          }
        } catch (_) {}
      }
    }
    return null;
  }

  @visibleForTesting
  static String cleanToolParamValue(dynamic raw) {
    if (raw == null) return '';
    var s = raw.toString().trim();
    if (s.length >= 2 &&
        ((s.startsWith('"') && s.endsWith('"')) ||
            (s.startsWith("'") && s.endsWith("'")))) {
      if (s.startsWith('"')) {
        try {
          final decoded = jsonDecode(s);
          if (decoded != null) return decoded.toString().trim();
        } catch (_) {}
      }
      s = s.substring(1, s.length - 1).trim();
    }
    return s;
  }

  @visibleForTesting
  static String formatCliToolPath(String rawPath, {String? workingDir}) {
    var cleaned = cleanToolParamValue(rawPath);
    if (cleaned.isEmpty) return '';

    if (cleaned.startsWith('file://')) {
      try {
        cleaned = Uri.parse(cleaned).toFilePath();
      } catch (_) {
        cleaned = cleaned.substring(7);
      }
    }

    final plainCacheDir = StealthVault.cacheDirName.replaceAll(r'\.', '.');
    if (plainCacheDir.isNotEmpty && cleaned.contains(plainCacheDir)) {
      return 'ngữ cảnh kiến trúc dự án';
    }

    if (workingDir != null && workingDir.trim().isNotEmpty) {
      final wd = p.normalize(workingDir.trim());
      final normPath = p.normalize(cleaned);
      if (normPath == wd) {
        final base = p.basename(wd);
        return base.isNotEmpty ? './ ($base)' : normPath;
      }
      if (p.isWithin(wd, normPath)) {
        return p.relative(normPath, from: wd);
      }
    }

    final home = Platform.environment['HOME'] ?? '';
    if (home.isNotEmpty && cleaned.startsWith('$home/')) {
      return '~/${cleaned.substring(home.length + 1)}';
    }
    return cleaned;
  }

  @visibleForTesting
  static Map<String, dynamic>? extractCliToolParams(
    Map<String, dynamic>? step,
  ) {
    if (step == null) return null;
    final merged = <String, dynamic>{};
    final toolInfo = asJsonMap(step['tool_info']);

    final candidates = <dynamic>[
      step['input'],
      step['arguments'],
      step['args'],
      step['parameters'],
      step['tool_args'],
      toolInfo?['input'],
      toolInfo?['arguments'],
      toolInfo?['parameters'],
    ];

    const actionSubKeys = <String>[
      'view_file',
      'read_file',
      'edit_file',
      'create_file',
      'write_file',
      'run_command',
      'list_directory',
      'find_file',
      'search_directory',
      'search_web',
      'read_url_content',
      'invoke_subagent',
      'mcp_tool',
      'custom_tool',
    ];
    for (final k in actionSubKeys) {
      if (step[k] != null) candidates.add(step[k]);
      if (toolInfo?[k] != null) candidates.add(toolInfo![k]);
    }

    for (final c in candidates) {
      final map = asJsonMap(c);
      if (map != null && map.isNotEmpty) {
        merged.addAll(map);
      }
    }
    return merged.isEmpty ? null : merged;
  }

  static String _firstParam(Map<String, dynamic> params, List<String> keys) {
    for (final k in keys) {
      if (params.containsKey(k)) {
        final v = cleanToolParamValue(params[k]);
        if (v.isNotEmpty) return v;
      }
    }
    final lowerMap = <String, dynamic>{};
    for (final entry in params.entries) {
      lowerMap.putIfAbsent(entry.key.toLowerCase(), () => entry.value);
    }
    for (final k in keys) {
      final lk = k.toLowerCase();
      if (lowerMap.containsKey(lk)) {
        final v = cleanToolParamValue(lowerMap[lk]);
        if (v.isNotEmpty) return v;
      }
    }
    return '';
  }

  @visibleForTesting
  static String describeCliToolCall({
    required String toolName,
    Map<String, dynamic>? toolParams,
    String? workingDir,
  }) {
    final cleanToolName = toolName.trim().isNotEmpty
        ? toolName.trim()
        : 'công cụ';
    if (toolParams == null || toolParams.isEmpty) {
      return cleanToolName;
    }

    final lowerTool = cleanToolName.toLowerCase();

    // 1. Terminal / Shell command
    final cmdLine = _firstParam(toolParams, const [
      'CommandLine',
      'command_line',
      'command',
      'cmd',
    ]);
    if (cmdLine.isNotEmpty) {
      return cmdLine;
    }

    // 2. Search / Grep / Find / Glob / Web Search
    final isSearchTool =
        lowerTool.contains('search') ||
        lowerTool.contains('grep') ||
        lowerTool.contains('find') ||
        lowerTool.contains('glob');
    final query = _firstParam(toolParams, const [
      'Query',
      'query',
      'Pattern',
      'pattern',
      'glob',
      'SearchTerm',
      'search_term',
    ]);
    if (lowerTool.contains('web') && query.isNotEmpty) {
      final domain = _firstParam(toolParams, const ['domain', 'Domain']);
      return domain.isNotEmpty
          ? 'Tìm web: "$query" ($domain)'
          : 'Tìm web: "$query"';
    }
    if (isSearchTool && query.isNotEmpty) {
      final searchDir = _firstParam(toolParams, const [
        'SearchPath',
        'search_path',
        'SearchDirectory',
        'search_directory',
        'DirectoryPath',
        'directory_path',
        'Path',
        'path',
        'include',
      ]);
      if (searchDir.isNotEmpty) {
        final displayDir = formatCliToolPath(searchDir, workingDir: workingDir);
        return 'Tìm "$query" trong $displayDir';
      }
      return 'Tìm "$query"';
    }

    // 3. Directory listing tools
    final isListDirTool =
        lowerTool == 'ls' ||
        lowerTool.contains('list_dir') ||
        lowerTool.contains('listdir');
    if (isListDirTool) {
      final dirTarget = _firstParam(toolParams, const [
        'DirectoryPath',
        'directory_path',
        'FolderPath',
        'folder_path',
        'Path',
        'path',
      ]);
      if (dirTarget.isNotEmpty) {
        return 'Xem thư mục: ${formatCliToolPath(dirTarget, workingDir: workingDir)}';
      }
    }

    // 4. File operations (read_file, view_file, edit_file, write_file, Read, Edit, Write, etc.)
    final rawFilePath = _firstParam(toolParams, const [
      'Path',
      'path',
      'file_path',
      'filePath',
      'AbsolutePath',
      'absolute_path',
      'TargetFile',
      'target_file',
      'Filename',
      'filename',
      'notebook_path',
      'NotebookPath',
      'file',
    ]);
    if (rawFilePath.isNotEmpty) {
      final displayPath = formatCliToolPath(
        rawFilePath,
        workingDir: workingDir,
      );
      final startLine = _firstParam(toolParams, const [
        'StartLine',
        'start_line',
        'offset',
        'StartLineNumber',
      ]);
      final endLine = _firstParam(toolParams, const [
        'EndLine',
        'end_line',
        'EndLineNumber',
      ]);
      final limit = _firstParam(toolParams, const ['limit', 'Limit']);

      String rangeSuffix = '';
      if (startLine.isNotEmpty && endLine.isNotEmpty) {
        rangeSuffix = ' (dòng $startLine-$endLine)';
      } else if (startLine.isNotEmpty && limit.isNotEmpty) {
        final sNum = int.tryParse(startLine);
        final lNum = int.tryParse(limit);
        if (sNum != null && lNum != null && lNum > 0) {
          rangeSuffix = ' (dòng $sNum-${sNum + lNum - 1})';
        } else {
          rangeSuffix = ' (từ dòng $startLine, $limit dòng)';
        }
      } else if (startLine.isNotEmpty) {
        rangeSuffix = ' (từ dòng $startLine)';
      } else if (endLine.isNotEmpty) {
        rangeSuffix = ' (đến dòng $endLine)';
      }

      if (lowerTool.contains('read') ||
          lowerTool.contains('view') ||
          lowerTool == 'cat') {
        return 'Đọc file: $displayPath$rangeSuffix';
      }
      if (lowerTool.contains('write') || lowerTool.contains('create')) {
        return 'Ghi file: $displayPath';
      }
      if (lowerTool.contains('edit') ||
          lowerTool.contains('replace') ||
          lowerTool.contains('patch')) {
        final instruction = _firstParam(toolParams, const [
          'Instruction',
          'instruction',
        ]);
        return instruction.isNotEmpty
            ? '$instruction: $displayPath'
            : 'Sửa file: $displayPath';
      }
      if (lowerTool.contains('delete') ||
          lowerTool.contains('remove') ||
          lowerTool == 'rm') {
        return 'Xóa file: $displayPath';
      }
      return '$displayPath$rangeSuffix';
    }

    // 5. Generic query / directory path / URL
    if (query.isNotEmpty) {
      final searchDir = _firstParam(toolParams, const [
        'SearchPath',
        'search_path',
        'DirectoryPath',
        'directory_path',
      ]);
      return searchDir.isNotEmpty
          ? 'Tìm "$query" trong ${formatCliToolPath(searchDir, workingDir: workingDir)}'
          : 'Tìm "$query"';
    }

    final dirOnly = _firstParam(toolParams, const [
      'DirectoryPath',
      'directory_path',
      'FolderPath',
      'folder_path',
    ]);
    if (dirOnly.isNotEmpty) {
      return 'Xem thư mục: ${formatCliToolPath(dirOnly, workingDir: workingDir)}';
    }

    final url = _firstParam(toolParams, const ['Url', 'url', 'uri', 'URI']);
    if (url.isNotEmpty) {
      if (url.startsWith('http://') || url.startsWith('https://')) {
        return 'Đọc URL: $url';
      }
      return 'Đọc tài nguyên: ${formatCliToolPath(url, workingDir: workingDir)}';
    }

    // 6. Subagent / Task / Swarm / Messaging
    if (lowerTool.contains('subagent') || lowerTool == 'task') {
      final subDesc = _firstParam(toolParams, const [
        'Role',
        'role',
        'description',
        'TypeName',
        'subagent_type',
      ]);
      if (subDesc.isNotEmpty) return 'Tác tử phụ: $subDesc';
    }

    if (lowerTool.contains('manage_task')) {
      final action = _firstParam(toolParams, const ['Action', 'action']);
      final taskId = _firstParam(toolParams, const ['TaskId', 'task_id']);
      if (action.isNotEmpty) {
        return taskId.isNotEmpty
            ? 'Quản lý tác vụ: $action ($taskId)'
            : 'Quản lý tác vụ: $action';
      }
    }

    if (lowerTool.contains('swarm')) {
      final action = _firstParam(toolParams, const ['action', 'Action']);
      final target = _firstParam(toolParams, const ['name', 'title']);
      if (action.isNotEmpty) {
        return target.isNotEmpty
            ? 'Swarm: $action ($target)'
            : 'Swarm: $action';
      }
    }

    if (lowerTool.contains('send_message')) {
      final recipient = _firstParam(toolParams, const [
        'Recipient',
        'recipient',
      ]);
      if (recipient.isNotEmpty) return 'Nhắn tới tác tử: $recipient';
    }

    final actionLabel = _firstParam(toolParams, const [
      'toolAction',
      'toolSummary',
      'description',
    ]);
    if (actionLabel.isNotEmpty) {
      return actionLabel;
    }

    // 7. Compact scalar fallback (skip bulky content fields)
    const ignoredKeys = <String>{
      'content',
      'contents',
      'target',
      'replacement',
      'old_string',
      'new_string',
      'diff_block',
      'prompt',
      'systemprompt',
      'system_prompt',
      'waitmsbeforeasync',
      'isdaemon',
      'overwrite',
      'append',
      'artifactmetadata',
    };
    final parts = <String>[];
    for (final entry in toolParams.entries) {
      if (ignoredKeys.contains(entry.key.toLowerCase())) continue;
      final val = entry.value;
      if (val == null || val is Map || val is List) continue;
      final s = cleanToolParamValue(val);
      if (s.isEmpty) continue;
      final preview = s.length > 60 ? '${s.substring(0, 60)}...' : s;
      parts.add('${entry.key}=$preview');
      if (parts.length >= 2) break;
    }
    if (parts.isNotEmpty) {
      return parts.join(', ');
    }

    return cleanToolName;
  }

  bool _isCliModel(String model) {
    final m = model.toLowerCase().trim();
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

  /// Chuyển đổi tên máy chủ thành định danh lệnh an toàn cho terminal
  static String sanitizeServerIdentifier(String raw) {
    final sb = StringBuffer();
    for (final code in raw.runes) {
      final isAlnum = (code >= 0x30 && code <= 0x39) ||
          (code >= 0x41 && code <= 0x5A) ||
          (code >= 0x61 && code <= 0x7A);
      if (isAlnum) {
        sb.write(String.fromCharCode(code).toLowerCase());
      } else if (sb.isNotEmpty && !sb.toString().endsWith('_')) {
        sb.write('_');
      }
    }
    var name = sb.toString();
    while (name.endsWith('_')) {
      name = name.substring(0, name.length - 1);
    }
    return name.isEmpty ? 'server' : name;
  }

  static const String _sshRunnerScript = r'''#!/usr/bin/env python3
import sys
import os
import argparse
import pexpect
import subprocess

def main():
    parser = argparse.ArgumentParser(description="SSH Runner with non-interactive authentication")
    parser.add_argument("--host", required=True)
    parser.add_argument("--port", type=int, default=22)
    parser.add_argument("--user", default="root")
    parser.add_argument("--pass-file", default=None)
    parser.add_argument("--key-file", default=None)
    parser.add_argument("--dir", default=None)
    parser.add_argument("cmd", nargs=argparse.REMAINDER)
    
    args = parser.parse_args()
    raw_cmd = args.cmd
    if raw_cmd and raw_cmd[0] == "--":
        raw_cmd = raw_cmd[1:]
    
    if not raw_cmd:
        print("Error: No command specified to run on remote host.", file=sys.stderr)
        sys.exit(1)
        
    remote_command = " ".join(raw_cmd)
    env_setup = 'export PATH="$HOME/.local/bin:$HOME/bin:/usr/local/bin:/usr/bin:/bin:$PATH"'
    if args.dir and args.dir.strip():
        remote_command = f'{env_setup}; cd "{args.dir.strip()}" 2>/dev/null; {remote_command}'
    else:
        remote_command = f'{env_setup}; {remote_command}'

    password = None
    if args.pass_file and os.path.isfile(args.pass_file):
        try:
            with open(args.pass_file, "r", encoding="utf-8") as f:
                password = f.read().rstrip("\r\n")
        except Exception:
            pass

    key_file = args.key_file if (args.key_file and os.path.isfile(args.key_file)) else None

    ssh_opts = [
        "-p", str(args.port),
        "-o", "StrictHostKeyChecking=no",
        "-o", "UserKnownHostsFile=/dev/null",
        "-o", "LogLevel=ERROR",
    ]
    if key_file:
        ssh_opts.extend(["-i", key_file])

    target = f"{args.user}@{args.host}"

    if not password:
        full_args = ["ssh"] + ssh_opts + [target, remote_command]
        res = subprocess.run(full_args)
        sys.exit(res.returncode)

    ssh_cmd_list = ["ssh"] + ssh_opts + [target, remote_command]
    try:
        child = pexpect.spawn(ssh_cmd_list[0], ssh_cmd_list[1:], timeout=300, encoding="utf-8")
        while True:
            idx = child.expect([
                r"(?i)are you sure you want to continue connecting \(yes/no",
                r"(?i)password:",
                r"(?i)enter passphrase for key",
                pexpect.EOF,
                pexpect.TIMEOUT
            ], timeout=15)
            if idx == 0:
                child.sendline("yes")
            elif idx == 1 or idx == 2:
                child.sendline(password)
                break
            elif idx == 3 or idx == 4:
                break
                
        child.expect(pexpect.EOF, timeout=300)
        output = child.before
        if output:
            print(output, end="")
        child.close()
        sys.exit(child.exitstatus or 0)
    except pexpect.TIMEOUT:
        print(f"\n[SSH Timeout]: Lệnh thực thi trên {args.host} vượt quá giới hạn thời gian chờ.", file=sys.stderr)
        sys.exit(124)
    except Exception as e:
        print(f"\n[SSH Error]: {e}", file=sys.stderr)
        sys.exit(1)

if __name__ == "__main__":
    main()
''';

  static const String _scpRunnerScript = r'''#!/usr/bin/env python3
import sys
import os
import argparse
import pexpect
import subprocess

def main():
    parser = argparse.ArgumentParser(description="SCP Runner with non-interactive authentication")
    parser.add_argument("--host", required=True)
    parser.add_argument("--port", type=int, default=22)
    parser.add_argument("--user", default="root")
    parser.add_argument("--pass-file", default=None)
    parser.add_argument("--key-file", default=None)
    parser.add_argument("--dir", default=None)
    parser.add_argument("paths", nargs=argparse.REMAINDER)
    
    args = parser.parse_args()
    raw_paths = args.paths
    if raw_paths and raw_paths[0] == "--":
        raw_paths = raw_paths[1:]
        
    if len(raw_paths) < 2:
        print("Usage: scp_<server> <source> <destination>", file=sys.stderr)
        print("Examples:", file=sys.stderr)
        print("  scp_<server> file.txt remote_file.txt    (upload to remoteWorkDir)", file=sys.stderr)
        print("  scp_<server> :remote_file.txt file.txt   (download from remoteWorkDir)", file=sys.stderr)
        sys.exit(1)
        
    src = raw_paths[0]
    dst = raw_paths[1]
    extra_scp_flags = ["-r"]
    
    target_prefix = f"{args.user}@{args.host}:"
    remote_base = (args.dir.rstrip("/") + "/") if (args.dir and args.dir.strip()) else ""
    
    if src.startswith(":"):
        rel_remote = src[1:]
        full_remote = rel_remote if rel_remote.startswith("/") else (remote_base + rel_remote)
        scp_src = f"{target_prefix}{full_remote}"
        scp_dst = dst
    else:
        scp_src = src
        full_remote = dst if dst.startswith("/") else (remote_base + dst)
        scp_dst = f"{target_prefix}{full_remote}"
        
    password = None
    if args.pass_file and os.path.isfile(args.pass_file):
        try:
            with open(args.pass_file, "r", encoding="utf-8") as f:
                password = f.read().rstrip("\r\n")
        except Exception:
            pass

    key_file = args.key_file if (args.key_file and os.path.isfile(args.key_file)) else None

    scp_opts = [
        "-P", str(args.port),
        "-o", "StrictHostKeyChecking=no",
        "-o", "UserKnownHostsFile=/dev/null",
        "-o", "LogLevel=ERROR",
    ] + extra_scp_flags
    if key_file:
        scp_opts.extend(["-i", key_file])

    full_cmd_list = ["scp"] + scp_opts + [scp_src, scp_dst]

    if not password:
        res = subprocess.run(full_cmd_list)
        sys.exit(res.returncode)

    try:
        child = pexpect.spawn(full_cmd_list[0], full_cmd_list[1:], timeout=300, encoding="utf-8")
        while True:
            idx = child.expect([
                r"(?i)are you sure you want to continue connecting \(yes/no",
                r"(?i)password:",
                r"(?i)enter passphrase for key",
                pexpect.EOF,
                pexpect.TIMEOUT
            ], timeout=15)
            if idx == 0:
                child.sendline("yes")
            elif idx == 1 or idx == 2:
                child.sendline(password)
                break
            elif idx == 3 or idx == 4:
                break
                
        child.expect(pexpect.EOF, timeout=300)
        output = child.before
        if output:
            print(output, end="")
        child.close()
        sys.exit(child.exitstatus or 0)
    except Exception as e:
        print(f"\n[SCP Error]: {e}", file=sys.stderr)
        sys.exit(1)

if __name__ == "__main__":
    main()
''';

  static Future<String?> _prepareSshHelpers(List<ServerModel> servers) async {
    if (servers.isEmpty) return null;
    try {
      final home = Platform.environment['HOME'] ?? '';
      if (home.isEmpty) return null;
      final helperDir = Directory('$home/.ai_type_agent/ssh_helpers');
      if (!helperDir.existsSync()) {
        helperDir.createSync(recursive: true);
      }
      if (!Platform.isWindows) {
        try {
          Process.runSync('chmod', ['700', helperDir.path]);
        } catch (_) {}
      }

      // Write runner scripts
      final sshRunnerFile = File('${helperDir.path}/ssh_runner.py');
      sshRunnerFile.writeAsStringSync(_sshRunnerScript);
      final scpRunnerFile = File('${helperDir.path}/scp_runner.py');
      scpRunnerFile.writeAsStringSync(_scpRunnerScript);
      if (!Platform.isWindows) {
        try {
          Process.runSync('chmod', ['755', sshRunnerFile.path, scpRunnerFile.path]);
        } catch (_) {}
      }

      for (final s in servers) {
        final id = sanitizeServerIdentifier(s.name.isNotEmpty ? s.name : s.serverIp);
        String? passFilePath;
        if (s.sshPass.isNotEmpty) {
          final passFile = File('${helperDir.path}/.pass_$id');
          passFile.writeAsStringSync(s.sshPass);
          if (!Platform.isWindows) {
            try {
              Process.runSync('chmod', ['600', passFile.path]);
            } catch (_) {}
          }
          passFilePath = passFile.path;
        }

        String? keyFilePath;
        if (s.sshKey != null && s.sshKey!.trim().isNotEmpty) {
          final keyFile = File('${helperDir.path}/.key_$id');
          keyFile.writeAsStringSync(s.sshKey!.trim());
          if (!Platform.isWindows) {
            try {
              Process.runSync('chmod', ['600', keyFile.path]);
            } catch (_) {}
          }
          keyFilePath = keyFile.path;
        }

        final passArg = passFilePath != null ? '--pass-file "$passFilePath"' : '';
        final keyArg = keyFilePath != null ? '--key-file "$keyFilePath"' : '';
        final remoteDir = s.remoteWorkDir.isNotEmpty ? s.remoteWorkDir : '';

        // Write Unix bash wrapper
        final sshSh = File('${helperDir.path}/ssh_$id');
        sshSh.writeAsStringSync('''#!/usr/bin/env bash
DIR="\$(cd "\$(dirname "\${BASH_SOURCE[0]}")" && pwd)"
exec python3 "\$DIR/ssh_runner.py" --host "${s.serverIp}" --port "${s.sshPort}" --user "${s.sshUser}" $passArg $keyArg --dir "$remoteDir" -- "\$@"
''');

        final scpSh = File('${helperDir.path}/scp_$id');
        scpSh.writeAsStringSync('''#!/usr/bin/env bash
DIR="\$(cd "\$(dirname "\${BASH_SOURCE[0]}")" && pwd)"
exec python3 "\$DIR/scp_runner.py" --host "${s.serverIp}" --port "${s.sshPort}" --user "${s.sshUser}" $passArg $keyArg --dir "$remoteDir" -- "\$@"
''');

        if (!Platform.isWindows) {
          try {
            Process.runSync('chmod', ['755', sshSh.path, scpSh.path]);
          } catch (_) {}
        }
      }
      return helperDir.path;
    } catch (_) {
      return null;
    }
  }

  Future<void> _runCliAgent({
    required String sessionId,
    required String cliName,
    required String prompt,
    List<AttachmentItem>? attachments,
    List<Map<String, dynamic>>? history,
    String? workingDir,
    List<String>? docFiles,
    ServerModel? targetServerModel,
    List<ServerModel>? targetServers,
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

    // Build attachments instruction text if attachments exist
    String attachmentPromptBlock = '';
    if (attachments != null && attachments.isNotEmpty) {
      final attBuf = StringBuffer();
      attBuf.writeln('\n=== TỆP & ẢNH ĐÍNH KÈM TỪ NGƯỜI DÙNG ===');
      for (final att in attachments) {
        final loc = att.remotePath != null && att.remotePath!.isNotEmpty
            ? 'Đường dẫn tệp trên VPS: `${att.remotePath}`'
            : (att.path != null && att.path!.isNotEmpty
                  ? 'Đường dẫn tệp cục bộ: `${att.path}`'
                  : '');
        if (att.isImage) {
          attBuf.writeln('\n- [Ảnh: ${att.name}]');
          if (loc.isNotEmpty) attBuf.writeln('  $loc');
          attBuf.writeln(
            '  Người dùng đã đính kèm ảnh này. Agent hãy dùng công cụ/tool đọc tệp hoặc xem ảnh tại đường dẫn trên để nắm bắt thông tin giao diện hoặc lỗi và xử lý trực tiếp.',
          );
        } else {
          attBuf.writeln('\n- [Tệp: ${att.name}]');
          if (loc.isNotEmpty) attBuf.writeln('  $loc');
          if (att.isMediaFile) {
            attBuf.writeln(
              '  Loại tệp: video/audio. Không thể đọc trực tiếp nội dung tệp video/audio. '
              'Trả lời NGẮN GỌN lý do không xử lý được tệp này.',
            );
          } else if (att.content.isNotEmpty &&
              !att.content.startsWith('data:')) {
            attBuf.writeln('  Nội dung tệp:\n${att.content}');
          }
        }
      }
      attBuf.writeln(
        '\n[YÊU CẦU XỬ LÝ ĐÍNH KÈM]: Agent hãy chủ động đọc, phân tích tệp/ảnh tại đường dẫn trên để giải quyết yêu cầu của người dùng. TUYỆT ĐỐI KHÔNG lặp lại hoặc in lại đoạn văn bản "=== TỆP & ẢNH ĐÍNH KÈM TỪ NGƯỜI DÙNG ===" này trong câu trả lời.',
      );
      attBuf.writeln('=== HẾT PHẦN ĐÍNH KÈM ===\n');
      attachmentPromptBlock = attBuf.toString();
    }

    final serversList = <ServerModel>[
      ...?targetServers,
      if ((targetServers == null || targetServers.isEmpty) &&
          targetServerModel != null)
        targetServerModel,
    ];
    final sshHelperPath = await _prepareSshHelpers(serversList);

    try {
      final workDir = (workingDir != null && Directory(workingDir).existsSync())
          ? workingDir
          : (Platform.environment['HOME'] ?? Directory.current.path);

      String promptSuffix;
      if (customPromptTemplate != null &&
          customPromptTemplate.trim().isNotEmpty) {
        promptSuffix = customPromptTemplate
            .replaceAll('{workDir}', workDir)
            .replaceAll('\$workDir', workDir)
            .trim();
      } else {
        promptSuffix =
            '''(Yêu cầu thực thi bắt buộc dành cho Agent CLI):
- THƯ MỤC LÀM VIỆC MỤC TIÊU (SCOPE BẮT BUỘC): `$workDir`
- Mọi lệnh terminal, tạo file, cấu hình mã nguồn, cài đặt gói BẮT BUỘC thực hiện trực tiếp tại thư mục `$workDir` (hoặc tạo thư mục con ngay trong `$workDir`). Tuyệt đối KHÔNG tạo ở scratch/ hay bất kỳ thư mục nào khác ngoài `$workDir`.
- TUYỆT ĐỐI KHÔNG TỰ CHẠY LỆNH SERVER CHẠY NỀN VÔ TẬN (như `npm run dev`, `npm run start`, `node server.js`, `python manage.py runserver`, `flask run`). Hãy biên dịch kiểm tra lỗi bằng `npm run build` hoặc lệnh test tương tự, sau đó in rõ câu lệnh và hướng dẫn người dùng chạy server ở Terminal hoặc ngoài hệ thống.
- Viết tiếng Việt có đầy đủ dấu thanh chuẩn chính tả, tuyệt đối không dùng emoji hay icon trong câu trả lời, trình bày bằng định dạng markdown kỹ thuật chuẩn.
- Khi tạo dự án hoặc cài đặt mã nguồn/thư viện (như Payload CMS, Next.js, npm, npx, pip, cargo): HÃY THỰC THI ĐỒNG BỘ VÀ HOÀN TẤT TRỌN VẸN TRONG LƯỢT NÀY. Luôn truyền cờ tự động không tương tác (ví dụ: -y, --yes, --template blank, --db sqlite) để lệnh tự động cài đặt xong ngay.
- TUYỆT ĐỐI CẤM TRUY CẬP, ĐỌC, IN RA MÀN HÌNH HOẶC GIẢI MÃ BẤT KỲ FILE CẤU HÌNH TÀI KHOẢN NÀO (như config*.json, ~/.ai_type_agent/config*.json, ~/.tadu_ai_agent/config*.json, .env, chat_history*.db, các khóa bảo mật hệ thống). Nếu người dùng yêu cầu đọc file config tài khoản, phải từ chối vì lý do bảo mật.
- Tuyệt đối KHÔNG kết thúc sớm khi chưa có kết quả đầy đủ. Hãy đợi kiểm tra/cài đặt hoàn tất, xác nhận cấu trúc thư mục/kết quả đã tạo và báo cáo cho người dùng.
- TRÌNH BÀY SÚC TÍCH, CHỐNG TRÀN VĂN BẢN: Trong lúc đang chạy lệnh/công cụ, KHÔNG viết văn bản suy nghĩ dài dòng hay in lại nội dung file/log ra câu trả lời. Khi báo cáo kết quả cuối cùng, hãy tóm tắt ngắn gọn, đi thẳng vào trọng tâm (khoảng 15 - 30 dòng).''';
      }

      // Bổ sung thông tin các máy chủ SSH đã liên kết - Scope vẫn là ưu tiên chính
      if (serversList.isNotEmpty) {
        final srvBuf = StringBuffer();
        srvBuf.writeln(
          '\n\n=== MÁY CHỦ TỪ XA ĐÃ LIÊN KẾT CHO PHIÊN NÀY (SSH TARGETS) ===',
        );
        srvBuf.writeln(
          '- Môi trường thực thi chính của Agent: Máy tính cục bộ tại Scope `$workDir`.',
        );
        srvBuf.writeln(
          '- Phiên làm việc này được người dùng liên kết với các máy chủ sau để điều khiển qua SSH:',
        );
        for (final s in serversList) {
          final idName = sanitizeServerIdentifier(
            s.name.isNotEmpty ? s.name : s.serverIp,
          );
          srvBuf.writeln('\n* MÁY CHỦ [${s.name}] (${s.serverIp})');
          srvBuf.writeln(
            '  + Tài khoản: ${s.sshUser}@${s.serverIp}:${s.sshPort}',
          );
          srvBuf.writeln(
            '  + Thư mục làm việc trên Server (Remote WorkDir): `${s.remoteWorkDir}`',
          );
          srvBuf.writeln('  + LỆNH ĐIỀU KHIỂN TỪ XA: `ssh_$idName "<command>"`');
          srvBuf.writeln(
            '    (Lệnh này đã được cấu hình sẵn thông tin đăng nhập tự động. Khi gọi `ssh_$idName "<command>"`, lệnh sẽ tự động được gửi qua SSH đến máy chủ và thực thi tại `${s.remoteWorkDir}`).',
          );
          srvBuf.writeln('  + LỆNH SAO CHÉP TỆP HAI CHIỀU:');
          srvBuf.writeln(
            '    - Từ Scope lên Server: `scp_$idName <đường_dẫn_local> <đường_dẫn_remote>`',
          );
          srvBuf.writeln(
            '    - Từ Server về Scope: `scp_$idName :<đường_dẫn_remote> <đường_dẫn_local>`',
          );
        }
        srvBuf.writeln('\n- HƯỚNG DẪN ĐIỀU KHIỂN VÀ TRIỂN KHAI:');
        srvBuf.writeln(
          '  1. Bạn chạy lệnh `ssh_<tên_server> "<lệnh>"` hoặc `scp_<tên_server> ...` trực tiếp trong công cụ terminal/bash của bạn.',
        );
        srvBuf.writeln(
          '  2. Máy chủ từ xa KHÔNG cần cài đặt agy, claude hay bất kỳ AI CLI nào. Mọi thao tác được thực hiện trực tiếp thông qua giao thức SSH tiêu chuẩn.',
        );
        srvBuf.writeln(
          '  3. Luôn đối chiếu kỹ mã nguồn tại Scope cục bộ trước khi đồng bộ hoặc ghi đè lên Server từ xa.',
        );
        srvBuf.writeln('=== HẾT DANH SÁCH MÁY CHỦ LIÊN KẾT ===\n');
        promptSuffix = '$promptSuffix${srvBuf.toString()}';
      }

      // Đọc và đính kèm nội dung các file tài liệu / rules được chọn vào prompt
      if (docFiles != null && docFiles.isNotEmpty) {
        final docsBuffer = StringBuffer();
        docsBuffer.writeln(
          '\n\n=== TÀI LIỆU DỰ ÁN & RULES BẮT BUỘC THAM CHIẾU (SCOPE DOCS) ===',
        );
        docsBuffer.writeln(
          'Người dùng đã chỉ định các tệp tài liệu và rules dưới đây để Agent tuân thủ và hiểu rõ yêu cầu dự án:\n',
        );

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
                docsBuffer.writeln(
                  '- Đường dẫn file tài liệu: `$docPath` (Kích thước lớn: ${(len / 1024).round()} KB, Agent hãy chủ động đọc khi cần)',
                );
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

      // Ưu tiên tài liệu phân tích kiến trúc có sẵn (thư mục cache ẩn) thay vì đọc toàn bộ mã nguồn
      final knowledgeGuide = _buildKnowledgeGuide(workDir);
      if (knowledgeGuide != null) {
        promptSuffix = '$promptSuffix\n$knowledgeGuide';
      }

      final effectiveLocalPrompt = attachmentPromptBlock.isNotEmpty
          ? '$prompt\n\n$attachmentPromptBlock\n$promptSuffix'
          : '$prompt\n\n$promptSuffix';
      final cleanPrompt = effectiveLocalPrompt;

      final m = cliName.toLowerCase();

      // Build contextual prompt for CLI models that do not support multi-turn session IDs
      String contextualPrompt = cleanPrompt;
      if (m.contains('gemini') ||
          (!m.contains('agy') &&
              !m.contains('antigravity') &&
              !m.contains('claude'))) {
        final recentHistory = (history != null && history.isNotEmpty)
            ? history
            : (await _dbService.getMessages(sessionId, limit: 10)).messages
                  .map((e) => {'role': e.role, 'content': e.content})
                  .toList();
        final pastMessages = recentHistory
            .where(
              (h) =>
                  (h['content']?.toString().trim().isNotEmpty ?? false) &&
                  h['content'] != prompt,
            )
            .toList();
        if (pastMessages.isNotEmpty) {
          final historyBuf = StringBuffer();
          historyBuf.writeln('=== LỊCH SỬ HỘI THOẠI TRƯỚC ĐÓ ===');
          for (final h in pastMessages) {
            final roleName = (h['role'] == 'user') ? 'Người dùng' : 'Trợ lý AI';
            historyBuf.writeln('[$roleName]: ${h['content']}');
          }
          historyBuf.writeln('=== KẾT THÚC LỊCH SỬ HỘI THOẠI ===\n');
          contextualPrompt =
              '${historyBuf.toString()}\n[Câu hỏi / Yêu cầu mới nhất của Người dùng]:\n$prompt\n\n$promptSuffix';
        }
      }

      // Augmented PATH environment so subprocesses (node, git, etc.) are always found
      final env = Map<String, String>.from(Platform.environment);
      final home = Platform.environment['HOME'] ?? '';
      final currentPath = env['PATH'] ?? '';
      final extraPaths = <String>[
        if (sshHelperPath != null && sshHelperPath.isNotEmpty) sshHelperPath,
        '$home/.ai_type_agent/ssh_helpers',
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
          args = [
            '--session-id',
            cliConvId,
            '-p',
            cleanPrompt,
            '--output-format',
            'stream-json',
            '--verbose',
            '--dangerously-skip-permissions',
          ];
        } else {
          args = [
            '-p',
            cleanPrompt,
            '--output-format',
            'stream-json',
            '--verbose',
            '--dangerously-skip-permissions',
          ];
        }
      } else if (m.contains('antigravity') || m == 'agy') {
        if (cliConvId != null && cliConvId.isNotEmpty) {
          args = [
            '--conversation',
            cliConvId,
            '--print',
            cleanPrompt,
            '--input-format',
            'text',
            '--output-format',
            'stream-json',
            '--dangerously-skip-permissions',
          ];
        } else {
          args = [
            '--print',
            cleanPrompt,
            '--input-format',
            'text',
            '--output-format',
            'stream-json',
            '--dangerously-skip-permissions',
          ];
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

      void finishSession([String? fallbackReply, String? warningSuffix]) {
        if (hasFinished) return;
        hasFinished = true;
        final rawResult = fullOutput.toString().trim();
        final result = stripSystemMessages(rawResult);
        final defaultEmpty =
            'Agent $cliName đã dừng tiến trình mà chưa xuất bản báo cáo kết quả. '
            'Nếu công việc chưa hoàn tất, hãy nhắn "tiếp tục" để agent chạy nốt.';
        var finalText = result.isNotEmpty
            ? result
            : (fallbackReply ?? defaultEmpty);
        if (warningSuffix != null && warningSuffix.isNotEmpty) {
          finalText = '$finalText\n\n$warningSuffix';
        }
        onDone(finalText);
        try {
          process.kill();
        } catch (_) {}
      }

      // Close stdin asynchronously
      process.stdin.close().catchError((_) {});

      // Watchdog chống treo tiến trình CLI: người dùng hủy tác vụ hoặc tiến
      // trình im lặng quá lâu (không còn stdout/stderr) thì chủ động kill và
      // kết thúc phiên, thay vì chờ exitCode vô hạn.
      const cliInactivity = Duration(minutes: 3);
      int lastCliActivityMs = DateTime.now().millisecondsSinceEpoch;
      void resetCliActivity() {
        lastCliActivityMs = DateTime.now().millisecondsSinceEpoch;
      }

      final cliWatchdog = Timer.periodic(const Duration(seconds: 5), (t) {
        if (hasFinished) {
          t.cancel();
          return;
        }
        if (isCancelled()) {
          t.cancel();
          finishSession(
            null,
            'Đã dừng tiến trình $cliName theo yêu cầu của người dùng.',
          );
          return;
        }
        final elapsed =
            DateTime.now().millisecondsSinceEpoch - lastCliActivityMs;
        if (elapsed >= cliInactivity.inMilliseconds) {
          t.cancel();
          finishSession(
            null,
            'Tiến trình $cliName không xuất thêm dữ liệu nào trong ${cliInactivity.inMinutes} phút nên đã bị dừng. '
            'Nếu công việc chưa xong, hãy nhắn "tiếp tục" để agent chạy nốt.',
          );
        }
      });

      final stepCmdByIndex = <int, String>{};
      final activeEmittedSteps = <int>{};
      final claudeEmittedToolIds = <String>{};

      process.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen((
        line,
      ) {
        resetCliActivity();
        if (isCancelled() || hasFinished) return;
        final trimmed = line.trim();
        if (trimmed.isEmpty) return;
        rawStdout.writeln(line);

        try {
          final json = jsonDecode(trimmed);
          if (json is Map<String, dynamic>) {
            // Track and store persistent conversation_id for subsequent turns
            final emittedConvId =
                json['conversation_id']?.toString() ??
                (json['result'] as Map<String, dynamic>?)?['conversation_id']
                    ?.toString() ??
                (json['step_update']
                        as Map<String, dynamic>?)?['conversation_id']
                    ?.toString() ??
                json['session_id']?.toString();
            if (emittedConvId != null &&
                emittedConvId.isNotEmpty &&
                emittedConvId != cliConvId) {
              cliConvId = emittedConvId;
              _dbService.setCliConversationId(sessionId, emittedConvId);
            }

            // 1. Antigravity CLI (agy) streaming protocol
            if (json.containsKey('event')) {
              final event = json['event'];
              if (event == 'step_update') {
                final step = asJsonMap(json['step_update']);
                final stepType = step?['step_type']?.toString();
                final textDelta =
                    step?['text_delta']?.toString() ??
                    step?['content']?.toString() ??
                    step?['text']?.toString();
                final errorMsg = step?['error']?.toString();

                if (stepType == 'thought' || stepType == 'thinking') {
                  onStatus('AI đang suy nghĩ và lập kế hoạch...');
                } else if (textDelta != null && textDelta.isNotEmpty) {
                  fullOutput.write(textDelta);
                  onToken(textDelta);
                } else if (errorMsg != null && errorMsg.isNotEmpty) {
                  fullOutput.write('\n[Lỗi]: $errorMsg\n');
                  onToken('\n[Lỗi]: $errorMsg\n');
                } else if (stepType == 'tool' || stepType == 'tool_call') {
                  final state = step?['state']?.toString().toUpperCase();
                  final stepIdx = step?['step_index'] is int
                      ? step!['step_index'] as int
                      : int.tryParse(step?['step_index']?.toString() ?? '');
                  final toolInfo = asJsonMap(step?['tool_info']);
                  final toolParams = extractCliToolParams(step);
                  final toolName =
                      step?['tool_name']?.toString() ??
                      toolInfo?['name']?.toString() ??
                      'công cụ';

                  var cmdDesc = describeCliToolCall(
                    toolName: toolName,
                    toolParams: toolParams,
                    workingDir: workDir,
                  );
                  if (cmdDesc != toolName &&
                      cmdDesc.isNotEmpty &&
                      stepIdx != null) {
                    stepCmdByIndex[stepIdx] = cmdDesc;
                  } else if ((cmdDesc.isEmpty || cmdDesc == toolName) &&
                      stepIdx != null &&
                      stepCmdByIndex.containsKey(stepIdx)) {
                    cmdDesc = stepCmdByIndex[stepIdx]!;
                  }
                  if (cmdDesc.isEmpty) {
                    cmdDesc = toolName;
                  }

                  if (state == 'ACTIVE' || state == 'RUNNING') {
                    if (fullOutput.isNotEmpty) {
                      fullOutput.clear();
                      onToken('__CLEAR_INTERMEDIATE_THOUGHTS__');
                    }
                    final statusLabel = cmdDesc == toolName
                        ? 'Đang thực thi $toolName...'
                        : 'Đang thực thi $toolName: $cmdDesc...';
                    onStatus(statusLabel);
                    if (stepIdx == null || activeEmittedSteps.add(stepIdx)) {
                      onTool(
                        ToolExecutionItem(
                          tool: toolName,
                          command: cmdDesc,
                          output: 'Đang thực thi...',
                        ),
                      );
                    }
                  } else {
                    final rawOut =
                        toolInfo?['output']?.toString() ??
                        step?['output']?.toString() ??
                        step?['tool_result']?.toString() ??
                        '';
                    final toolErr =
                        toolInfo?['error']?.toString() ??
                        step?['error_message']?.toString() ??
                        '';
                    final plainCacheDir = StealthVault.cacheDirName.replaceAll(
                      r'\.',
                      '.',
                    );
                    final isInternalCache =
                        plainCacheDir.isNotEmpty &&
                        cmdDesc.contains('ngữ cảnh kiến trúc dự án');
                    final output = rawOut.isNotEmpty
                        ? rawOut
                        : (toolErr.isNotEmpty && !isInternalCache
                              ? 'Lỗi: $toolErr'
                              : '');
                    onTool(
                      ToolExecutionItem(
                        tool: toolName,
                        command: cmdDesc,
                        output: output,
                      ),
                    );
                  }
                } else if (stepType == 'thought' || stepType == 'thinking') {
                  onStatus('AI đang suy nghĩ và lập kế hoạch...');
                }
              } else if (event == 'result') {
                final res = json['result'] as Map<String, dynamic>?;
                final resp = res?['response']?.toString();
                final status = res?['status']?.toString();
                final errorMsg = res?['error']?.toString();
                if (resp != null && resp.isNotEmpty) {
                  fullOutput.clear();
                  fullOutput.write(resp);
                  onToken('__CLEAR_INTERMEDIATE_THOUGHTS__');
                  onToken(resp);
                } else if (status == 'ERROR' &&
                    errorMsg != null &&
                    errorMsg.isNotEmpty &&
                    fullOutput.isEmpty) {
                  fullOutput.write('\n[Lỗi Antigravity]: $errorMsg\n');
                  onToken('\n[Lỗi Antigravity]: $errorMsg\n');
                }
                // Do not finishSession() here - wait for full process exitCode!
              } else if (event == 'error') {
                final err =
                    json['error']?.toString() ??
                    json['message']?.toString() ??
                    '';
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
                final err =
                    json['error']?.toString() ??
                    json['message']?.toString() ??
                    '';
                if (err.isNotEmpty) {
                  fullOutput.write('\n[Lỗi Claude]: $err\n');
                  onToken('\n[Lỗi Claude]: $err\n');
                }
              } else if (type == 'assistant') {
                final msg = asJsonMap(json['message']);
                final contents = msg?['content'] as List<dynamic>?;
                if (contents != null) {
                  for (final c in contents) {
                    if (c is Map && c['type'] == 'text') {
                      final t = c['text']?.toString();
                      if (t != null && fullOutput.isEmpty) {
                        fullOutput.write(t);
                        onToken(t);
                      }
                    } else if (c is Map && c['type'] == 'tool_use') {
                      final tId = c['id']?.toString() ?? '';
                      final tName = c['name']?.toString() ?? 'tool';
                      final tParams = asJsonMap(c['input']);
                      final desc = describeCliToolCall(
                        toolName: tName,
                        toolParams: tParams,
                        workingDir: workDir,
                      );
                      onStatus(
                        desc == tName
                            ? 'Đang thực thi $tName...'
                            : 'Đang thực thi $tName: $desc...',
                      );
                      if (tId.isEmpty || claudeEmittedToolIds.add(tId)) {
                        onTool(
                          ToolExecutionItem(
                            tool: tName,
                            command: desc,
                            output: '',
                          ),
                        );
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
        resetCliActivity();
        if (!isCancelled() && !hasFinished) {
          errOutput.write(data);
          debugPrint('[$cliName stderr]: $data');
        }
      });

      final exitCode = await process.exitCode;
      cliWatchdog.cancel();
      if (!hasFinished) {
        if (exitCode == 0) {
          finishSession();
        } else if (fullOutput.isNotEmpty) {
          // Agent bi dung giua chung (timeout/crash) nhung da co output -
          // bao xong kem canh bao ro rang de nguoi dung biet tac vu CHUA hoan tat
          final rawResult = fullOutput.toString().trim();
          final result = stripSystemMessages(rawResult);
          finishSession(
            '$result\n\n> **Cảnh báo:** Agent $cliName đã bị dừng đột ngột (mã thoát: $exitCode) trước khi hoàn tất tác vụ. '
            'Câu trả lời trên có thể chưa đủ — hãy yêu cầu "tiếp tục" để agent làm nốt phần còn lại.',
          );
        } else {
          final errStr = errOutput.toString().trim();
          final rawStr = rawStdout.toString().trim();
          final displayErr = errStr.isNotEmpty
              ? errStr
              : (rawStr.isNotEmpty
                    ? rawStr
                    : 'Không có phản hồi từ tiến trình (Mã thoát: $exitCode)');
          onError('Agent $cliName báo lỗi (mã $exitCode): $displayErr');
        }
      }
    } catch (e) {
      onError(
        'Không thể chạy CLI $cliName: $e. Hãy kiểm tra đường dẫn hoặc quyền thực thi.',
      );
    }
  }
}
