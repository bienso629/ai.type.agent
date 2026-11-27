import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../core/services/api_service.dart';
import '../../core/services/native_ai_service.dart';
import '../../core/services/primary_host_server_service.dart';
import '../../core/services/remote_tunnel_service.dart';
import '../../core/services/storage_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_toast.dart';
import '../../core/widgets/pairing_qr_widget.dart';
import '../../providers/chat_provider.dart';
import '../../providers/gateway_provider.dart';
import '../../providers/server_provider.dart';
import '../../providers/terminal_provider.dart';
import '../logs/logs_dialog.dart';
import 'qr_scanner_screen.dart';

class SettingsScreen extends StatefulWidget {
  final VoidCallback? onOpenDrawer;

  const SettingsScreen({super.key, this.onOpenDrawer});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final ApiService _api = ApiService();
  final TextEditingController _modelCtrl = TextEditingController(text: 'glm-5.3');
  final TextEditingController _baseUrlCtrl = TextEditingController(text: 'https://openrouter.ai/api/v1');
  final TextEditingController _apiKeyCtrl = TextEditingController();
  final TextEditingController _promptCtrl = TextEditingController();

  // Điều khiển từ xa: App Chính (Host) / App Phụ (Remote) & Đường hầm Internet toàn cầu
  final TextEditingController _hostNameCtrl = TextEditingController();
  final TextEditingController _hostPortCtrl = TextEditingController(text: '8765');
  final TextEditingController _hostWorkspacesRootCtrl = TextEditingController();
  final TextEditingController _tunnelNamedTokenCtrl = TextEditingController();
  final TextEditingController _tunnelCustomUrlCtrl = TextEditingController();
  final TextEditingController _remoteUrlCtrl = TextEditingController();
  final TextEditingController _remoteTokenCtrl = TextEditingController();
  final TextEditingController _pairingPasteCtrl = TextEditingController();
  bool _obscureHostToken = true;
  bool _obscureTunnelToken = true;
  bool _obscureRemoteToken = true;
  bool _showManualRemoteConnect = false;
  String _manualConnectMode = 'paste'; // 'paste' | 'fields'
  bool _remoteControllersSeeded = false;
  bool _isApplyingRemote = false;

  String _selectedTab = 'proxy'; // 'proxy' | 'google_studio'
  final TextEditingController _googleStudioModelCtrl = TextEditingController(text: 'gemini-2.5-flash');
  final TextEditingController _newGoogleKeyCtrl = TextEditingController();
  final List<String> _googleStudioKeys = [];
  bool _obscureProxyKey = true;
  bool _obscureGoogleKeys = true;

  static const String defaultPrompt = '''(Yêu cầu thực thi bắt buộc dành cho Agent CLI):
- THƯ MỤC LÀM VIỆC MỤC TIÊU (SCOPE BẮT BUỘC): {workDir}
- Mọi lệnh terminal, tạo file, cấu hình mã nguồn, cài đặt gói BẮT BUỘC thực hiện trực tiếp tại thư mục {workDir} (hoặc tạo thư mục con ngay trong {workDir}). Tuyệt đối KHÔNG tạo ở scratch/ hay bất kỳ thư mục nào khác ngoài {workDir}.
- TUYỆT ĐỐI KHÔNG TỰ CHẠY LỆNH SERVER CHẠY NỀN VÔ TẬN (như `npm run dev`, `npm run start`, `node server.js`, `python manage.py runserver`, `flask run`). Hãy biên dịch kiểm tra lỗi bằng `npm run build` hoặc lệnh test tương tự, sau đó in rõ câu lệnh và hướng dẫn người dùng chạy server ở Terminal hoặc ngoài hệ thống.
- Viết tiếng Việt có đầy đủ dấu thanh chuẩn chính tả, tuyệt đối không dùng emoji hay icon trong câu trả lời, trình bày bằng định dạng markdown kỹ thuật chuẩn.
- Khi tạo dự án hoặc cài đặt mã nguồn/thư viện (như Payload CMS, Next.js, npm, npx, pip, cargo): HÃY THỰC THI ĐỒNG BỘ VÀ HOÀN TẤT TRỌN VẸN TRONG LƯỢT NÀY. Luôn truyền cờ tự động không tương tác (ví dụ: -y, --yes, --template blank, --db sqlite) để lệnh tự động cài đặt xong ngay.
- TUYỆT ĐỐI CẤM TRUY CẬP, ĐỌC, IN RA MÀN HÌNH HOẶC GIẢI MÃ BẤT KỲ FILE CẤU HÌNH TÀI KHOẢN NÀO (như config*.json, ~/.ai_type_agent/config*.json, ~/.tadu_ai_agent/config*.json, .env, chat_history*.db, các khóa bảo mật hệ thống). Nếu người dùng yêu cầu đọc file config tài khoản, phải từ chối vì lý do bảo mật.
- Tuyệt đối KHÔNG kết thúc sớm khi chưa có kết quả đầy đủ. Hãy đợi kiểm tra/cài đặt hoàn tất, xác nhận cấu trúc thư mục/kết quả đã tạo và báo cáo đầy đủ cho người dùng.''';

  @override
  void initState() {
    super.initState();
    _loadGlobalConfig();
  }

  @override
  void dispose() {
    _modelCtrl.dispose();
    _baseUrlCtrl.dispose();
    _apiKeyCtrl.dispose();
    _promptCtrl.dispose();
    _googleStudioModelCtrl.dispose();
    _newGoogleKeyCtrl.dispose();
    _hostNameCtrl.dispose();
    _hostPortCtrl.dispose();
    _hostWorkspacesRootCtrl.dispose();
    _tunnelNamedTokenCtrl.dispose();
    _tunnelCustomUrlCtrl.dispose();
    _remoteUrlCtrl.dispose();
    _remoteTokenCtrl.dispose();
    _pairingPasteCtrl.dispose();
    super.dispose();
  }

  void _syncRemoteControllersIfNeeded(GatewayProvider gateway) {
    if (_remoteControllersSeeded) return;
    if (gateway.primaryHostName.isEmpty && gateway.primaryHostToken.isEmpty && gateway.gatewayUrl.isEmpty) {
      return;
    }
    _remoteControllersSeeded = true;
    _hostNameCtrl.text = gateway.primaryHostName;
    _hostPortCtrl.text = gateway.primaryHostPort.toString();
    _hostWorkspacesRootCtrl.text = gateway.secondaryWorkspacesRoot;
    _tunnelNamedTokenCtrl.text = gateway.tunnelNamedToken;
    _tunnelCustomUrlCtrl.text = gateway.tunnelCustomUrl;
    _remoteUrlCtrl.text = gateway.gatewayUrl;
    _remoteTokenCtrl.text = gateway.secretToken;
  }

  Future<void> _reloadAppProvidersAfterRoleChange() async {
    if (!mounted) return;
    final serverProvider = context.read<ServerProvider>();
    final chatProvider = context.read<ChatProvider>();
    final terminalProvider = context.read<TerminalProvider>();
    await Future.wait([
      serverProvider.reloadAll(),
      chatProvider.reloadAll(),
      terminalProvider.reconnectLocalPanes(),
      _loadGlobalConfig(),
    ]);
  }

  Future<void> _switchAppRole(AppRole targetRole) async {
    final gateway = context.read<GatewayProvider>();
    if (gateway.role == targetRole) return;
    setState(() => _isApplyingRemote = true);
    try {
      await gateway.setAppRole(targetRole);
      if (targetRole == AppRole.primary || gateway.gatewayUrl.trim().isNotEmpty) {
        await _reloadAppProvidersAfterRoleChange();
      }
      if (!mounted) return;
      AppToast.success(
        context,
        targetRole == AppRole.primary
            ? 'Đã chuyển thiết bị sang chế độ App Chính (chạy cục bộ).'
            : 'Đã chuyển thiết bị sang chế độ App Phụ (điều khiển App Chính từ xa).',
      );
    } finally {
      if (mounted) setState(() => _isApplyingRemote = false);
    }
  }

  Future<void> _applyPrimaryHostSettings() async {
    final gateway = context.read<GatewayProvider>();
    final parsedPort = int.tryParse(_hostPortCtrl.text.trim());
    if (parsedPort == null || parsedPort < 1024 || parsedPort > 65535) {
      AppToast.warning(context, 'Cổng lắng nghe phải nằm trong khoảng 1024 - 65535.');
      return;
    }
    final ok = await gateway.updatePrimaryHostSettings(
      port: parsedPort,
      deviceName: _hostNameCtrl.text.trim(),
      secondaryWorkspacesRoot: _hostWorkspacesRootCtrl.text.trim(),
    );
    if (!mounted) return;
    _hostWorkspacesRootCtrl.text = gateway.secondaryWorkspacesRoot;
    if (ok) {
      AppToast.success(context, 'Đã cập nhật cấu hình máy chủ App Chính (cổng $parsedPort).');
    } else {
      AppToast.error(context, gateway.hostErrorMessage.isNotEmpty ? gateway.hostErrorMessage : 'Không thể mở cổng $parsedPort.');
    }
  }

  Future<void> _pickSecondaryWorkspacesRoot() async {
    try {
      final selected = await FilePicker.platform.getDirectoryPath(
        dialogTitle: 'Chọn thư mục gốc chứa workspace cho các App Phụ',
        initialDirectory: _hostWorkspacesRootCtrl.text.trim().isNotEmpty
            ? _hostWorkspacesRootCtrl.text.trim()
            : null,
      );
      if (selected == null || selected.trim().isEmpty || !mounted) return;
      final clean = selected.trim();
      setState(() {
        _hostWorkspacesRootCtrl.text = clean;
      });
      final gateway = context.read<GatewayProvider>();
      await gateway.updatePrimaryHostSettings(secondaryWorkspacesRoot: clean);
      if (!mounted) return;
      AppToast.success(context, 'Đã đặt thư mục chứa workspace App Phụ: $clean');
    } catch (e) {
      if (!mounted) return;
      AppToast.error(context, 'Không thể mở trình chọn thư mục: $e');
    }
  }

  Future<void> _openWorkspaceFolder(String dirPath) async {
    final clean = dirPath.trim();
    if (clean.isEmpty) return;
    try {
      final d = Directory(clean);
      if (!d.existsSync()) {
        d.createSync(recursive: true);
      }
      if (Platform.isLinux) {
        await Process.start('xdg-open', [clean], mode: ProcessStartMode.detached);
      } else if (Platform.isMacOS) {
        await Process.start('open', [clean], mode: ProcessStartMode.detached);
      } else if (Platform.isWindows) {
        await Process.start('explorer', [clean], mode: ProcessStartMode.detached);
      }
    } catch (_) {}
  }

  Future<void> _disconnectSecondaryFromPrimary() async {
    final gateway = context.read<GatewayProvider>();
    setState(() => _isApplyingRemote = true);
    try {
      await gateway.disconnectFromPrimary(clearSavedCredentials: true);
      _remoteUrlCtrl.clear();
      _remoteTokenCtrl.clear();
      _pairingPasteCtrl.clear();
      await _reloadAppProvidersAfterRoleChange();
      if (!mounted) return;
      setState(() => _showManualRemoteConnect = false);
      AppToast.info(context, 'Đã ngắt kết nối khỏi App Chính.');
    } finally {
      if (mounted) setState(() => _isApplyingRemote = false);
    }
  }

  Future<void> _refreshSecondaryConnection() async {
    final gateway = context.read<GatewayProvider>();
    setState(() => _isApplyingRemote = true);
    try {
      final ok = await gateway.testConnection();
      if (ok) {
        await _reloadAppProvidersAfterRoleChange();
      }
      if (!mounted) return;
      if (ok) {
        AppToast.success(
          context,
          'Kết nối App Chính ổn định (${gateway.remoteHostName} • ${gateway.pingMs} ms).',
        );
      } else {
        AppToast.warning(
          context,
          gateway.errorMessage.isNotEmpty ? gateway.errorMessage : 'Không thể liên lạc tới App Chính.',
        );
      }
    } finally {
      if (mounted) setState(() => _isApplyingRemote = false);
    }
  }

  Future<void> _connectSecondaryToPrimary() async {
    final gateway = context.read<GatewayProvider>();
    if (gateway.isWaitingPairingApproval) {
      gateway.cancelOneTapPairing();
    }

    var rawUrl = '';
    var rawToken = '';
    var fallbackUrls = const <String>[];

    if (_manualConnectMode == 'paste') {
      final pasted = _pairingPasteCtrl.text.trim();
      if (pasted.isEmpty) {
        AppToast.warning(
          context,
          'Vui lòng dán chuỗi ghép nối lấy từ nút "Sao chép chuỗi ghép nối" trên App Chính.',
        );
        return;
      }
      final parsed = StorageService.parsePairingString(pasted);
      if (parsed.url.isEmpty) {
        AppToast.warning(
          context,
          'Chuỗi ghép nối không hợp lệ. Chuỗi đúng có dạng http://IP:8765#<mã> hoặc https://...#<mã>.',
        );
        return;
      }
      rawUrl = parsed.url;
      rawToken = parsed.token;
      fallbackUrls = parsed.fallbackUrls;
      _remoteUrlCtrl.text = rawUrl;
      if (rawToken.isNotEmpty) _remoteTokenCtrl.text = rawToken;
    } else {
      rawUrl = _remoteUrlCtrl.text.trim();
      rawToken = _remoteTokenCtrl.text.trim();
      if (rawUrl.contains('#')) {
        final parsed = StorageService.parsePairingString(rawUrl);
        if (parsed.url.isNotEmpty) {
          rawUrl = parsed.url;
          _remoteUrlCtrl.text = rawUrl;
        }
        if (rawToken.isEmpty && parsed.token.isNotEmpty) {
          rawToken = parsed.token;
          _remoteTokenCtrl.text = rawToken;
        }
        fallbackUrls = parsed.fallbackUrls;
      }
      if (rawUrl.isEmpty) {
        AppToast.warning(
          context,
          'Vui lòng nhập Địa chỉ máy tính App Chính (ví dụ: http://192.168.1.10:8765).',
        );
        return;
      }
      if (rawToken.isEmpty) {
        AppToast.warning(
          context,
          'Vui lòng nhập Mã ghép nối lấy từ mục 0 trên máy tính App Chính.',
        );
        return;
      }
    }

    setState(() => _isApplyingRemote = true);
    try {
      final ok = await gateway.setGatewayConfig(rawUrl, rawToken, fallbackUrls: fallbackUrls);
      if (ok) {
        _remoteUrlCtrl.text = gateway.gatewayUrl;
        _remoteTokenCtrl.text = gateway.secretToken;
        _pairingPasteCtrl.clear();
        await _reloadAppProvidersAfterRoleChange();
        if (!mounted) return;
        setState(() => _showManualRemoteConnect = false);
        AppToast.success(
          context,
          'Đã kết nối và đồng bộ thành công với App Chính (${gateway.remoteHostName})!',
        );
      } else {
        if (!mounted) return;
        AppToast.error(
          context,
          gateway.errorMessage.isNotEmpty ? gateway.errorMessage : 'Kết nối tới App Chính thất bại.',
        );
      }
    } finally {
      if (mounted) setState(() => _isApplyingRemote = false);
    }
  }

  Future<void> _scanQrAndConnect() async {
    final gateway = context.read<GatewayProvider>();
    if (gateway.isWaitingPairingApproval) {
      gateway.cancelOneTapPairing();
    }

    final scanned = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const QrScannerScreen()),
    );
    if (!mounted || scanned == null || scanned.trim().isEmpty) return;

    final parsed = StorageService.parsePairingString(scanned);
    if (parsed.url.isEmpty) {
      AppToast.warning(context, 'Mã QR không chứa địa chỉ ghép nối hợp lệ.');
      return;
    }

    _remoteUrlCtrl.text = parsed.url;
    _remoteTokenCtrl.text = parsed.token;
    setState(() => _isApplyingRemote = true);
    try {
      final ok = await gateway.setGatewayConfig(
        parsed.url,
        parsed.token,
        fallbackUrls: parsed.fallbackUrls,
      );
      if (ok) {
        _remoteUrlCtrl.text = gateway.gatewayUrl;
        _remoteTokenCtrl.text = gateway.secretToken;
        await _reloadAppProvidersAfterRoleChange();
        if (!mounted) return;
        AppToast.success(
          context,
          'Quét QR và kết nối thành công với App Chính (${gateway.remoteHostName})!',
        );
      } else {
        if (!mounted) return;
        AppToast.error(
          context,
          gateway.errorMessage.isNotEmpty
              ? gateway.errorMessage
              : 'Đã quét QR nhưng chưa chạm được App Chính. Kiểm tra Wi-Fi/Tailscale hoặc Internet trên máy tính.',
        );
      }
    } finally {
      if (mounted) setState(() => _isApplyingRemote = false);
    }
  }

  Future<void> _requestOneTapPair(DiscoveredPrimaryHost host) async {
    final gateway = context.read<GatewayProvider>();
    final ok = await gateway.requestOneTapPairing(host);
    if (!mounted) return;
    if (ok) {
      _remoteUrlCtrl.text = gateway.gatewayUrl;
      _remoteTokenCtrl.text = gateway.secretToken;
      await _reloadAppProvidersAfterRoleChange();
      if (!mounted) return;
      AppToast.success(
        context,
        'Kết nối thành công với App Chính (${gateway.remoteHostName})!',
      );
    } else if (gateway.errorMessage.isNotEmpty) {
      AppToast.warning(context, gateway.errorMessage);
    }
  }

  Future<void> _loadGlobalConfig() async {
    try {
      final cfg = await _api.getConfig();
      final m = cfg['ai_model']?.toString() ?? 'glm-5.3';
      _modelCtrl.text = (m.contains('cli') || m == 'agy' || m == 'claude') ? 'glm-5.3' : m;
      if (cfg['proxy_base_url'] != null) _baseUrlCtrl.text = cfg['proxy_base_url'].toString();
      if (cfg['proxy_api_key'] != null) _apiKeyCtrl.text = cfg['proxy_api_key'].toString();
      _promptCtrl.text = cfg['custom_prompt']?.toString() ?? defaultPrompt;

      final savedTab = cfg['ai_provider_tab']?.toString() ?? 'proxy';
      final savedGoogleModel = cfg['google_studio_model']?.toString() ?? 'gemini-2.5-flash';
      final extractedKeys = NativeAiService.extractGoogleStudioKeys(cfg);

      if (mounted) {
        setState(() {
          _selectedTab = (savedTab == 'google_studio') ? 'google_studio' : 'proxy';
          _googleStudioModelCtrl.text = savedGoogleModel.isNotEmpty ? savedGoogleModel : 'gemini-2.5-flash';
          _googleStudioKeys
            ..clear()
            ..addAll(extractedKeys);
        });
      }
    } catch (_) {}
  }

  void _addGoogleStudioKeysFromInput() {
    final raw = _newGoogleKeyCtrl.text.trim();
    if (raw.isEmpty) return;

    final parts = raw
        .split(RegExp(r'[\r\n,;\s]+'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();

    int added = 0;
    setState(() {
      for (final k in parts) {
        if (!_googleStudioKeys.contains(k)) {
          _googleStudioKeys.add(k);
          added++;
        }
      }
      _newGoogleKeyCtrl.clear();
    });

    if (added > 0) {
      AppToast.success(context, 'Đã thêm $added API Key Google Studio vào danh sách!');
    } else {
      AppToast.info(context, 'API Key này đã có trong danh sách.');
    }
  }

  void _removeGoogleStudioKey(int index) {
    if (index < 0 || index >= _googleStudioKeys.length) return;
    setState(() {
      _googleStudioKeys.removeAt(index);
    });
  }

  String _maskApiKey(String key) {
    if (!_obscureGoogleKeys) return key;
    if (key.length <= 10) return '••••••••••';
    return '${key.substring(0, 6)}••••••••••••••••••••${key.substring(key.length - 4)}';
  }

  void _applyGoogleModelPreset(String modelName) {
    setState(() {
      _googleStudioModelCtrl.text = modelName;
    });
    AppToast.info(context, 'Đã chọn model Google Studio: $modelName');
  }

  Future<void> _saveAISettings() async {
    try {
      if (_newGoogleKeyCtrl.text.trim().isNotEmpty) {
        _addGoogleStudioKeysFromInput();
      }

      final activeModel = _selectedTab == 'google_studio'
          ? (_googleStudioModelCtrl.text.trim().isNotEmpty ? _googleStudioModelCtrl.text.trim() : 'gemini-2.5-flash')
          : _modelCtrl.text.trim();

      final ok = await _api.saveConfig({
        'ai_provider_tab': _selectedTab,
        'ai_model': activeModel,
        'proxy_base_url': _baseUrlCtrl.text.trim(),
        'proxy_api_key': _apiKeyCtrl.text.trim(),
        'google_studio_model': _googleStudioModelCtrl.text.trim().isNotEmpty
            ? _googleStudioModelCtrl.text.trim()
            : 'gemini-2.5-flash',
        'google_studio_api_keys': List<String>.from(_googleStudioKeys),
        'custom_prompt': _promptCtrl.text.trim(),
      });
      if (mounted) {
        if (ok) {
          final serverProvider = context.read<ServerProvider>();
          serverProvider.setCloudAiModel(activeModel);
          await serverProvider.loadGlobalConfig();
          if (!mounted) return;
          if (_selectedTab == 'google_studio') {
            serverProvider.fetchModels(
              forceRefresh: true,
              customBaseUrl: 'https://generativelanguage.googleapis.com/v1beta/openai',
              customApiKey: _googleStudioKeys.isNotEmpty ? _googleStudioKeys.first : '',
            );
          } else {
            serverProvider.fetchModels(
              forceRefresh: true,
              customBaseUrl: _baseUrlCtrl.text.trim(),
              customApiKey: _apiKeyCtrl.text.trim(),
            );
          }
          AppToast.success(
            context,
            _selectedTab == 'google_studio'
                ? 'Đã lưu cấu hình Google AI Studio (${_googleStudioKeys.length} API Keys) thành công!'
                : 'Đã lưu cấu hình AI Model, Proxy API & Custom Prompt thành công!',
          );
        } else {
          AppToast.error(context, 'Lưu cấu hình thất bại!');
        }
      }
    } catch (e) {
      if (mounted) {
        AppToast.error(context, 'Lỗi: $e');
      }
    }
  }

  void _applyPreset(String name, String baseUrl, String defaultModel) {
    setState(() {
      _baseUrlCtrl.text = baseUrl;
      _modelCtrl.text = defaultModel;
    });
    AppToast.info(context, 'Đã áp dụng mẫu cấu hình: $name');
  }

  void _resetCustomPrompt() {
    setState(() {
      _promptCtrl.text = defaultPrompt;
    });
    AppToast.info(context, 'Đã khôi phục Prompt mẫu mặc định');
  }

  @override
  Widget build(BuildContext context) {
    final serverProvider = context.watch<ServerProvider>();
    final gateway = context.watch<GatewayProvider>();
    _syncRemoteControllersIfNeeded(gateway);

    return Scaffold(
      backgroundColor: AppColors.bgDark,
      body: Column(
        children: [
          // Topbar Header
          Builder(
            builder: (context) {
              final isCompactMobile = MediaQuery.sizeOf(context).width < 600;
              return Container(
                height: isCompactMobile ? 56 : 66,
                padding: EdgeInsets.symmetric(horizontal: isCompactMobile ? 12 : 24),
                decoration: const BoxDecoration(
                  color: AppColors.bgDark,
                  border: Border(bottom: BorderSide(color: AppColors.borderDark, width: 1)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          if (widget.onOpenDrawer != null) ...[
                            IconButton(
                              tooltip: 'Mở menu điều hướng',
                              style: IconButton.styleFrom(
                                padding: EdgeInsets.zero,
                                minimumSize: const Size(34, 34),
                                fixedSize: const Size(34, 34),
                                maximumSize: const Size(34, 34),
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                visualDensity: VisualDensity.standard,
                              ),
                              constraints: const BoxConstraints.tightFor(width: 34, height: 34),
                              onPressed: widget.onOpenDrawer,
                              icon: const Icon(Icons.menu_rounded, size: 20, color: AppColors.textWhite),
                            ),
                            const SizedBox(width: 6),
                          ],
                          const Icon(Icons.tune_rounded, color: AppColors.primaryLight, size: 22),
                          SizedBox(width: isCompactMobile ? 8 : 12),
                          Expanded(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Cấu Hình AI Agent & Hệ Thống',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.textWhite),
                                ),
                                Text(
                                  'Thiết lập mô hình AI Model, API Key và môi trường hoạt động (${serverProvider.currentAiModel})',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        padding: EdgeInsets.symmetric(horizontal: isCompactMobile ? 10 : 14, vertical: 0),
                        minimumSize: const Size(0, 32),
                        fixedSize: const Size.fromHeight(32),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      icon: const Icon(Icons.save_rounded, size: 16),
                      label: Text(
                        isCompactMobile ? 'Lưu' : 'Lưu Cấu Hình',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                      onPressed: _saveAISettings,
                    ),
                  ],
                ),
              );
            },
          ),

          // Scrollable Content
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isCompactMobile = constraints.maxWidth < 640;
                final pagePadding = isCompactMobile ? 12.0 : 20.0;
                final cardPadding = isCompactMobile ? 14.0 : 18.0;

                final proxyPresets = <Map<String, String>>[
                  {'label': 'OpenRouter (GLM-5.3)', 'url': 'https://openrouter.ai/api/v1', 'model': 'glm-5.3'},
                  {'label': 'OpenAI (GPT-4o)', 'url': 'https://api.openai.com/v1', 'model': 'gpt-4o'},
                  {'label': 'DeepSeek', 'url': 'https://api.deepseek.com/v1', 'model': 'deepseek-chat'},
                  {'label': 'Local Ollama', 'url': 'http://127.0.0.1:11434/v1', 'model': 'llama3.2:latest'},
                  {'label': 'Zhipu GLM', 'url': 'https://open.bigmodel.cn/api/paas/v4', 'model': 'glm-4-flash'},
                ];

                final googleModels = <String>[
                  'gemini-2.5-flash',
                  'gemini-2.5-pro',
                  'gemini-2.5-flash-lite',
                  'gemini-2.0-flash',
                ];

                final osLabel = Platform.isAndroid
                    ? 'ANDROID (Mobile)'
                    : Platform.isIOS
                        ? 'iOS (Mobile)'
                        : '${Platform.operatingSystem.toUpperCase()} (64-bit)';
                final shellLabel = Platform.isAndroid
                    ? '/system/bin/sh (SSH ưu tiên)'
                    : (Platform.environment['SHELL'] ?? (Platform.isWindows ? 'cmd.exe' : '/bin/bash'));
                final dataDirLabel = (Platform.isAndroid || Platform.isIOS)
                    ? 'App Sandbox Storage'
                    : (Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '.');

                final envBoxes = <Widget>[
                  _buildInfoBox(
                    'Hệ Điều Hành Local',
                    osLabel,
                    tooltip: '${Platform.operatingSystem.toUpperCase()} (${Platform.operatingSystemVersion})',
                  ),
                  _buildInfoBox(
                    'Trình Thực Thi Shell',
                    shellLabel,
                  ),
                  _buildInfoBox(
                    'Chế Độ Hoạt Động',
                    'Local & Quản trị Máy Chủ VPS',
                    tooltip: 'Thực thi lệnh trên Local Shell và Máy chủ từ xa qua SSH',
                  ),
                  _buildInfoBox(
                    'Thư Mục Dữ Liệu Local',
                    dataDirLabel,
                    tooltip: 'Đường dẫn lưu trữ dữ liệu cục bộ của ứng dụng',
                  ),
                  _buildInfoBox(
                    'Bảo Mật Cơ Sở Dữ Liệu',
                    'SQLite Encrypted Storage',
                    tooltip: 'Cơ sở dữ liệu SQLite mã hóa AES an toàn',
                  ),
                  _buildInfoBox(
                    'Phiên Bản Ứng Dụng',
                    'AI Type Agent v1.5.10',
                    tooltip: 'Phiên bản AI Type Agent Client',
                  ),
                ];

                final providerSwitcher = Container(
                  width: isCompactMobile ? double.infinity : null,
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    color: AppColors.inputBg,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: AppColors.borderDark),
                  ),
                  child: Row(
                    mainAxisSize: isCompactMobile ? MainAxisSize.max : MainAxisSize.min,
                    children: [
                      if (isCompactMobile)
                        Expanded(
                          child: _buildTabButton(
                            id: 'proxy',
                            icon: Icons.hub_rounded,
                            label: 'AI Model & Proxy',
                            expand: true,
                          ),
                        )
                      else
                        _buildTabButton(
                          id: 'proxy',
                          icon: Icons.hub_rounded,
                          label: 'AI Model & Proxy',
                        ),
                      const SizedBox(width: 4),
                      if (isCompactMobile)
                        Expanded(
                          child: _buildTabButton(
                            id: 'google_studio',
                            icon: Icons.auto_awesome_rounded,
                            label: 'Google Studio',
                            badgeCount: _googleStudioKeys.length,
                            expand: true,
                          ),
                        )
                      else
                        _buildTabButton(
                          id: 'google_studio',
                          icon: Icons.auto_awesome_rounded,
                          label: 'API key Google Studio',
                          badgeCount: _googleStudioKeys.length,
                        ),
                    ],
                  ),
                );

                return SingleChildScrollView(
                  padding: EdgeInsets.all(pagePadding),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // GROUP 0: VAI TRÒ ỨNG DỤNG (APP CHÍNH / APP PHỤ) & ĐIỀU KHIỂN TỪ XA
                      _buildRoleControlCard(
                        gateway: gateway,
                        isCompactMobile: isCompactMobile,
                        cardPadding: cardPadding,
                      ),
                      SizedBox(height: isCompactMobile ? 14 : 20),

                      // GROUP 1: AI MODEL & API CONFIGURATION
                      Container(
                        padding: EdgeInsets.all(cardPadding),
                        decoration: BoxDecoration(
                          color: AppColors.cardBg,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: AppColors.borderDark),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Row(
                              children: [
                                Icon(Icons.memory_rounded, size: 18, color: AppColors.primaryLight),
                                SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    '1. Cấu Hình AI Model & Proxy API',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            providerSwitcher,
                            const SizedBox(height: 14),
                            if (_selectedTab == 'proxy') ...[
                              const Text(
                                'Chọn nhà cung cấp nhanh (Quick Presets):',
                                style: TextStyle(fontSize: 11, color: AppColors.textDim),
                              ),
                              const SizedBox(height: 8),
                              _buildAlignedGrid(
                                columns: isCompactMobile ? 2 : 3,
                                spacing: 8,
                                children: proxyPresets
                                    .map((p) => _buildPresetTile(p['label']!, p['url']!, p['model']!))
                                    .toList(),
                              ),
                              const Divider(height: 22),
                              if (isCompactMobile) ...[
                                _buildLabeledField(
                                  label: 'Tên Model (AI Model Name)',
                                  child: TextField(
                                    controller: _modelCtrl,
                                    maxLines: 1,
                                    textAlignVertical: TextAlignVertical.center,
                                    style: const TextStyle(fontSize: 12.5),
                                    decoration: const InputDecoration(
                                      hintText: 'glm-5.3 hoặc gpt-4o hoặc deepseek-chat',
                                      hintStyle: TextStyle(fontSize: 11.5),
                                      prefixIcon: Icon(Icons.smart_toy_outlined, size: 16),
                                      isDense: true,
                                      contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                                      constraints: BoxConstraints(minHeight: 34, maxHeight: 34),
                                      prefixIconConstraints: BoxConstraints(minWidth: 34, minHeight: 34),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                _buildLabeledField(
                                  label: 'Địa Chỉ API (Base URL)',
                                  child: TextField(
                                    controller: _baseUrlCtrl,
                                    maxLines: 1,
                                    textAlignVertical: TextAlignVertical.center,
                                    style: const TextStyle(fontSize: 12.5),
                                    decoration: const InputDecoration(
                                      hintText: 'https://openrouter.ai/api/v1',
                                      hintStyle: TextStyle(fontSize: 11.5),
                                      prefixIcon: Icon(Icons.link_rounded, size: 16),
                                      isDense: true,
                                      contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                                      constraints: BoxConstraints(minHeight: 34, maxHeight: 34),
                                      prefixIconConstraints: BoxConstraints(minWidth: 34, minHeight: 34),
                                    ),
                                  ),
                                ),
                              ] else
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Expanded(
                                      child: _buildLabeledField(
                                        label: 'Tên Model (AI Model Name)',
                                        child: TextField(
                                          controller: _modelCtrl,
                                          maxLines: 1,
                                          textAlignVertical: TextAlignVertical.center,
                                          style: const TextStyle(fontSize: 12.5),
                                          decoration: const InputDecoration(
                                            hintText: 'glm-5.3 hoặc gpt-4o hoặc deepseek-chat',
                                            hintStyle: TextStyle(fontSize: 11.5),
                                            prefixIcon: Icon(Icons.smart_toy_outlined, size: 16),
                                            isDense: true,
                                            contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                                            constraints: BoxConstraints(minHeight: 34, maxHeight: 34),
                                            prefixIconConstraints: BoxConstraints(minWidth: 34, minHeight: 34),
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: _buildLabeledField(
                                        label: 'Địa Chỉ API (Base URL)',
                                        child: TextField(
                                          controller: _baseUrlCtrl,
                                          maxLines: 1,
                                          textAlignVertical: TextAlignVertical.center,
                                          style: const TextStyle(fontSize: 12.5),
                                          decoration: const InputDecoration(
                                            hintText: 'https://openrouter.ai/api/v1',
                                            hintStyle: TextStyle(fontSize: 11.5),
                                            prefixIcon: Icon(Icons.link_rounded, size: 16),
                                            isDense: true,
                                            contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                                            constraints: BoxConstraints(minHeight: 34, maxHeight: 34),
                                            prefixIconConstraints: BoxConstraints(minWidth: 34, minHeight: 34),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              const SizedBox(height: 12),
                              _buildLabeledField(
                                label: 'API Key (Khoá xác thực bí mật)',
                                child: TextField(
                                  controller: _apiKeyCtrl,
                                  obscureText: _obscureProxyKey,
                                  maxLines: 1,
                                  textAlignVertical: TextAlignVertical.center,
                                  style: const TextStyle(fontSize: 12.5),
                                  decoration: InputDecoration(
                                    hintText: 'sk-or-v1-... / sk-... (API Key)',
                                    hintStyle: const TextStyle(fontSize: 11.5),
                                    prefixIcon: const Icon(Icons.key_rounded, size: 16),
                                    isDense: true,
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                                    constraints: const BoxConstraints(minHeight: 34, maxHeight: 34),
                                    prefixIconConstraints: const BoxConstraints(minWidth: 34, minHeight: 34),
                                    suffixIcon: IconButton(
                                      icon: Icon(
                                        _obscureProxyKey ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                                        size: 16,
                                        color: AppColors.textMuted,
                                      ),
                                      onPressed: () => setState(() => _obscureProxyKey = !_obscureProxyKey),
                                    ),
                                  ),
                                ),
                              ),
                            ] else ...[
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: AppColors.primary.withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(color: AppColors.primaryLight.withValues(alpha: 0.3)),
                                ),
                                child: const Row(
                                  children: [
                                    Icon(Icons.auto_awesome_rounded, size: 18, color: AppColors.accentCyan),
                                    SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        'Cấu hình nhiều API Key của Google AI Studio miễn phí (aistudio.google.com). Hệ thống tự động xoay vòng (Round-Robin) giữa các Key và tự động đổi sang Key khác ngay lập tức nếu gặp giới hạn Rate Limit (429).',
                                        style: TextStyle(fontSize: 11.5, color: AppColors.textWhite, height: 1.4),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 12),
                              const Text(
                                'Chọn nhanh Model Gemini (Google AI Studio):',
                                style: TextStyle(fontSize: 11, color: AppColors.textDim),
                              ),
                              const SizedBox(height: 8),
                              _buildAlignedGrid(
                                columns: isCompactMobile ? 2 : 4,
                                spacing: 8,
                                children: googleModels.map(_buildGoogleModelTile).toList(),
                              ),
                              const SizedBox(height: 14),
                              if (isCompactMobile) ...[
                                _buildLabeledField(
                                  label: 'Tên Model Gemini (Google AI Studio)',
                                  child: TextField(
                                    controller: _googleStudioModelCtrl,
                                    maxLines: 1,
                                    textAlignVertical: TextAlignVertical.center,
                                    style: const TextStyle(fontSize: 12.5),
                                    decoration: const InputDecoration(
                                      hintText: 'gemini-2.5-flash hoặc gemini-2.5-pro',
                                      hintStyle: TextStyle(fontSize: 11.5),
                                      prefixIcon: Icon(Icons.auto_awesome_outlined, size: 16),
                                      isDense: true,
                                      contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                                      constraints: BoxConstraints(minHeight: 34, maxHeight: 34),
                                      prefixIconConstraints: BoxConstraints(minWidth: 34, minHeight: 34),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                _buildLabeledField(
                                  label: 'Địa Chỉ API Google AI Studio',
                                  child: TextField(
                                    readOnly: true,
                                    controller: TextEditingController(text: 'https://generativelanguage.googleapis.com/v1beta/openai'),
                                    maxLines: 1,
                                    textAlignVertical: TextAlignVertical.center,
                                    style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
                                    decoration: const InputDecoration(
                                      prefixIcon: Icon(Icons.cloud_done_rounded, size: 16, color: AppColors.accent),
                                      isDense: true,
                                      contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                                      constraints: BoxConstraints(minHeight: 34, maxHeight: 34),
                                      prefixIconConstraints: BoxConstraints(minWidth: 34, minHeight: 34),
                                    ),
                                  ),
                                ),
                              ] else
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Expanded(
                                      child: _buildLabeledField(
                                        label: 'Tên Model Gemini (Google AI Studio)',
                                        child: TextField(
                                          controller: _googleStudioModelCtrl,
                                          maxLines: 1,
                                          textAlignVertical: TextAlignVertical.center,
                                          style: const TextStyle(fontSize: 12.5),
                                          decoration: const InputDecoration(
                                            hintText: 'gemini-2.5-flash hoặc gemini-2.5-pro',
                                            hintStyle: TextStyle(fontSize: 11.5),
                                            prefixIcon: Icon(Icons.auto_awesome_outlined, size: 16),
                                            isDense: true,
                                            contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                                            constraints: BoxConstraints(minHeight: 34, maxHeight: 34),
                                            prefixIconConstraints: BoxConstraints(minWidth: 34, minHeight: 34),
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: _buildLabeledField(
                                        label: 'Địa Chỉ API Google AI Studio',
                                        child: TextField(
                                          readOnly: true,
                                          controller: TextEditingController(text: 'https://generativelanguage.googleapis.com/v1beta/openai'),
                                          maxLines: 1,
                                          textAlignVertical: TextAlignVertical.center,
                                          style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
                                          decoration: const InputDecoration(
                                            prefixIcon: Icon(Icons.cloud_done_rounded, size: 16, color: AppColors.accent),
                                            isDense: true,
                                            contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                                            constraints: BoxConstraints(minHeight: 34, maxHeight: 34),
                                            prefixIconConstraints: BoxConstraints(minWidth: 34, minHeight: 34),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              const SizedBox(height: 14),
                              const Text(
                                'Thêm API Key Google Studio (Có thể dán 1 hoặc nhiều key cách nhau bởi dấu phẩy / khoảng trắng / xuống dòng):',
                                style: TextStyle(fontSize: 11.5, color: AppColors.textDim),
                              ),
                              const SizedBox(height: 6),
                              SizedBox(
                                height: 34,
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    Expanded(
                                      child: TextField(
                                        controller: _newGoogleKeyCtrl,
                                        onSubmitted: (_) => _addGoogleStudioKeysFromInput(),
                                        maxLines: 1,
                                        textAlignVertical: TextAlignVertical.center,
                                        style: const TextStyle(fontSize: 12.5),
                                        decoration: const InputDecoration(
                                          hintText: 'AIzaSy... (1 hoặc nhiều API Key)',
                                          hintStyle: TextStyle(fontSize: 11.5),
                                          prefixIcon: Icon(Icons.vpn_key_rounded, size: 16),
                                          isDense: true,
                                          contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                                          constraints: BoxConstraints(minHeight: 34, maxHeight: 34),
                                          prefixIconConstraints: BoxConstraints(minWidth: 34, minHeight: 34),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    ElevatedButton.icon(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: AppColors.primaryLight,
                                        foregroundColor: AppColors.bgDark,
                                        padding: EdgeInsets.symmetric(horizontal: isCompactMobile ? 10 : 14, vertical: 0),
                                        minimumSize: const Size(0, 34),
                                        fixedSize: const Size.fromHeight(34),
                                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                      ),
                                      icon: const Icon(Icons.add_circle_outline_rounded, size: 15),
                                      label: Text(
                                        isCompactMobile ? 'Thêm' : 'Thêm Key',
                                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                                      ),
                                      onPressed: _addGoogleStudioKeysFromInput,
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 14),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Text(
                                      'Danh sách API Key Google Studio (${_googleStudioKeys.length} keys):',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: AppColors.textWhite),
                                    ),
                                  ),
                                  if (_googleStudioKeys.isNotEmpty) ...[
                                    const SizedBox(width: 8),
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        TextButton.icon(
                                          style: TextButton.styleFrom(
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                                            minimumSize: Size.zero,
                                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                          ),
                                          icon: Icon(
                                            _obscureGoogleKeys ? Icons.visibility_rounded : Icons.visibility_off_rounded,
                                            size: 14,
                                            color: AppColors.accentCyan,
                                          ),
                                          label: Text(
                                            _obscureGoogleKeys ? 'Hiện' : 'Ẩn',
                                            style: const TextStyle(fontSize: 11, color: AppColors.accentCyan),
                                          ),
                                          onPressed: () => setState(() => _obscureGoogleKeys = !_obscureGoogleKeys),
                                        ),
                                        const SizedBox(width: 4),
                                        TextButton.icon(
                                          style: TextButton.styleFrom(
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                                            minimumSize: Size.zero,
                                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                          ),
                                          icon: const Icon(Icons.delete_sweep_rounded, size: 14, color: Colors.redAccent),
                                          label: const Text('Xoá hết', style: TextStyle(fontSize: 11, color: Colors.redAccent)),
                                          onPressed: () => setState(() => _googleStudioKeys.clear()),
                                        ),
                                      ],
                                    ),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 8),
                              if (_googleStudioKeys.isEmpty)
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 14),
                                  decoration: BoxDecoration(
                                    color: AppColors.inputBg,
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(color: AppColors.borderDark),
                                  ),
                                  child: const Column(
                                    children: [
                                      Icon(Icons.key_off_rounded, size: 22, color: AppColors.textMuted),
                                      SizedBox(height: 6),
                                      Text(
                                        'Chưa có API Key Google Studio nào. Hãy thêm 1 hoặc nhiều key miễn phí vào ô bên trên rồi bấm Lưu.',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(fontSize: 11.5, color: AppColors.textMuted),
                                      ),
                                    ],
                                  ),
                                )
                              else
                                Container(
                                  constraints: BoxConstraints(maxHeight: (_googleStudioKeys.length * 46).clamp(100.0, 420.0).toDouble()),
                                  decoration: BoxDecoration(
                                    color: AppColors.inputBg,
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(color: AppColors.borderDark),
                                  ),
                                  child: ListView.separated(
                                    shrinkWrap: true,
                                    itemCount: _googleStudioKeys.length,
                                    separatorBuilder: (_, _) => const Divider(height: 1, color: AppColors.borderDark),
                                    itemBuilder: (ctx, idx) {
                                      final k = _googleStudioKeys[idx];
                                      return Padding(
                                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                        child: Row(
                                          children: [
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: AppColors.primary.withValues(alpha: 0.2),
                                                borderRadius: BorderRadius.circular(4),
                                              ),
                                              child: Text(
                                                'Key #${idx + 1}',
                                                style: const TextStyle(
                                                  fontSize: 10.5,
                                                  fontWeight: FontWeight.bold,
                                                  color: AppColors.accentCyan,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 10),
                                            Expanded(
                                              child: Text(
                                                _maskApiKey(k),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                  fontFamily: 'monospace',
                                                  fontSize: 12,
                                                  color: AppColors.textWhite,
                                                ),
                                              ),
                                            ),
                                            IconButton(
                                              icon: const Icon(Icons.close_rounded, size: 16, color: Colors.redAccent),
                                              tooltip: 'Xoá API Key này',
                                              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                                              padding: EdgeInsets.zero,
                                              onPressed: () => _removeGoogleStudioKey(idx),
                                            ),
                                          ],
                                        ),
                                      );
                                    },
                                  ),
                                ),
                            ],
                            const Divider(height: 22),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Expanded(
                                  child: Text(
                                    'Custom Prompt & Yêu Cầu Thực Thi AI Model / CLI Agent',
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.textWhite),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                TextButton.icon(
                                  style: TextButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                    minimumSize: Size.zero,
                                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  ),
                                  icon: const Icon(Icons.restore_rounded, size: 14, color: AppColors.accentCyan),
                                  label: const Text('Mặc Định', style: TextStyle(fontSize: 11, color: AppColors.accentCyan)),
                                  onPressed: _resetCustomPrompt,
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              'Toàn bộ yêu cầu chỉ thị và quy tắc thực thi (Scope làm việc {workDir}, quy chuẩn tiếng Việt, không chạy server nền, hoàn tất đồng bộ...). Có thể tùy chỉnh theo ý muốn.',
                              style: TextStyle(fontSize: 11, color: AppColors.textMuted),
                            ),
                            const SizedBox(height: 10),
                            TextField(
                              controller: _promptCtrl,
                              maxLines: isCompactMobile ? 6 : 8,
                              style: const TextStyle(fontSize: 12, fontFamily: 'monospace', height: 1.45, color: AppColors.textWhite),
                              decoration: const InputDecoration(
                                hintText: 'Nhập custom prompt & yêu cầu dành cho AI Model...',
                                contentPadding: EdgeInsets.all(12),
                              ),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(height: isCompactMobile ? 14 : 20),

                      // GROUP 2: SYSTEM ENVIRONMENT & STORAGE INFO
                      Container(
                        padding: EdgeInsets.all(cardPadding),
                        decoration: BoxDecoration(
                          color: AppColors.cardBg,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: AppColors.borderDark),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Row(
                              children: [
                                Icon(Icons.laptop_chromebook_rounded, size: 18, color: AppColors.accent),
                                SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    '2. Môi Trường Thực Thi & Cơ Sở Dữ Liệu',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ],
                            ),
                            const Divider(height: 20),
                            _buildAlignedGrid(
                              columns: isCompactMobile ? 2 : 3,
                              spacing: 8,
                              children: envBoxes,
                            ),
                            const Divider(height: 22),
                            if (isCompactMobile) ...[
                              const Text(
                                'Nhật Ký Hoạt Động & Lịch Sử Lệnh',
                                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.textWhite),
                              ),
                              const SizedBox(height: 2),
                              const Text(
                                'Theo dõi chi tiết logs thực thi của AI Agent và hệ thống (Local & Máy chủ từ xa)',
                                style: TextStyle(fontSize: 11, color: AppColors.textMuted),
                              ),
                              const SizedBox(height: 10),
                              SizedBox(
                                width: double.infinity,
                                height: 34,
                                child: ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppColors.inputBg,
                                    foregroundColor: AppColors.textWhite,
                                    side: const BorderSide(color: AppColors.borderDark),
                                    minimumSize: const Size(0, 34),
                                    fixedSize: const Size.fromHeight(34),
                                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                                  ),
                                  icon: const Icon(Icons.receipt_long_rounded, size: 16, color: AppColors.accent),
                                  label: const Text('Mở Hộp Thoại Nhật Ký (Logs)', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
                                  onPressed: () => LogsDialog.show(context),
                                ),
                              ),
                            ] else
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Nhật Ký Hoạt Động & Lịch Sử Lệnh',
                                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.textWhite),
                                        ),
                                        SizedBox(height: 2),
                                        Text(
                                          'Theo dõi chi tiết logs thực thi của AI Agent và hệ thống (Local & Máy chủ từ xa)',
                                          style: TextStyle(fontSize: 11, color: AppColors.textMuted),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppColors.inputBg,
                                      foregroundColor: AppColors.textWhite,
                                      side: const BorderSide(color: AppColors.borderDark),
                                      minimumSize: const Size(0, 32),
                                      fixedSize: const Size.fromHeight(32),
                                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 0),
                                    ),
                                    icon: const Icon(Icons.receipt_long_rounded, size: 16, color: AppColors.accent),
                                    label: const Text('Mở Hộp Thoại Nhật Ký (Logs)', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
                                    onPressed: () => LogsDialog.show(context),
                                  ),
                                ],
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  IconData _clientOsIcon(String os) {
    switch (os.trim().toLowerCase()) {
      case 'android':
        return Icons.phone_android_rounded;
      case 'ios':
        return Icons.phone_iphone_rounded;
      case 'windows':
      case 'linux':
      case 'macos':
        return Icons.laptop_rounded;
      default:
        return Icons.devices_other_rounded;
    }
  }

  String _formatClientLastSeen(DateTime lastSeenAt) {
    final diff = DateTime.now().difference(lastSeenAt);
    if (diff.inSeconds < 15) return 'Vừa hoạt động';
    if (diff.inSeconds < 60) return '${diff.inSeconds} giây trước';
    if (diff.inMinutes < 60) return '${diff.inMinutes} phút trước';
    return '${diff.inHours} giờ trước';
  }

  Widget _buildClientBadge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: color.withValues(alpha: 0.4), width: 0.7),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: color),
      ),
    );
  }

  Widget _buildConnectedClientsPanel({
    required GatewayProvider gateway,
    required bool isCompactMobile,
  }) {
    final clients = gateway.connectedClients;
    final onlineCount = gateway.onlineClientsCount;
    final countColor = onlineCount > 0 ? AppColors.accent : AppColors.textMuted;

    return Container(
      key: const ValueKey('connected_secondary_clients_panel'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.inputBg,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: AppColors.borderDark),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.devices_rounded, size: 15, color: AppColors.accentCyan),
              const SizedBox(width: 6),
              const Expanded(
                child: Text(
                  'Thiết bị App Phụ đang kết nối',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.textWhite),
                ),
              ),
              Container(
                key: const ValueKey('connected_clients_count_badge'),
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: countColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: countColor.withValues(alpha: 0.45), width: 0.8),
                ),
                child: Text(
                  '$onlineCount đang online',
                  style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: countColor),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          if (clients.isEmpty)
            const Text(
              'Chưa có thiết bị App Phụ nào kết nối tới máy tính này. Khi điện thoại hoặc máy tính khác ghép nối, danh sách thiết bị và nút ngắt kết nối từng máy sẽ hiển thị tại đây.',
              style: TextStyle(fontSize: 11, color: AppColors.textMuted, height: 1.35),
            )
          else
            ...clients.map((client) {
              final stateColor = client.isRevoked
                  ? AppColors.danger
                  : (client.isOnline ? AppColors.accent : AppColors.textMuted);
              final stateLabel = client.isRevoked
                  ? 'Đã ngắt quyền'
                  : (client.isOnline ? 'Đang online' : 'Ngoại tuyến');
              final osLabel = client.os.isNotEmpty && client.os != 'unknown'
                  ? client.os.toUpperCase()
                  : 'APP PHỤ';
              final metaText = '$osLabel • ${client.ip} • ${_formatClientLastSeen(client.lastSeenAt)}';

              final statusWrap = Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  _buildClientBadge(stateLabel, stateColor),
                  if (!client.isRevoked && client.activeChats > 0)
                    _buildClientBadge('${client.activeChats} Chat', AppColors.accentCyan),
                  if (!client.isRevoked && client.activeTerminals > 0)
                    _buildClientBadge('${client.activeTerminals} Terminal', AppColors.primaryLight),
                ],
              );

              final actionBtn = client.isRevoked
                  ? SizedBox(
                      height: 28,
                      child: OutlinedButton.icon(
                        key: ValueKey('restore_client_${client.clientId}'),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, 28),
                          fixedSize: const Size.fromHeight(28),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          side: const BorderSide(color: AppColors.accent, width: 0.9),
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                        ),
                        icon: const Icon(Icons.refresh_rounded, size: 13, color: AppColors.accent),
                        label: const Text(
                          'Cho phép lại',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.accent),
                        ),
                        onPressed: () async {
                          await gateway.restoreSecondaryClient(client.clientId);
                          if (!mounted) return;
                          AppToast.success(context, 'Đã cho phép thiết bị "${client.deviceName}" kết nối lại.');
                        },
                      ),
                    )
                  : SizedBox(
                      height: 28,
                      child: OutlinedButton.icon(
                        key: ValueKey('disconnect_client_${client.clientId}'),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, 28),
                          fixedSize: const Size.fromHeight(28),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          side: const BorderSide(color: AppColors.danger, width: 0.9),
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                        ),
                        icon: const Icon(Icons.link_off_rounded, size: 13, color: AppColors.danger),
                        label: const Text(
                          'Ngắt kết nối',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.danger),
                        ),
                        onPressed: () async {
                          await gateway.disconnectSecondaryClient(client.clientId, revoke: true);
                          if (!mounted) return;
                          AppToast.info(context, 'Đã ngắt kết nối thiết bị "${client.deviceName}".');
                        },
                      ),
                    );

              return Container(
                key: ValueKey('connected_client_row_${client.clientId}'),
                margin: const EdgeInsets.only(top: 8),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.cardBg,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: client.isRevoked
                        ? AppColors.danger.withValues(alpha: 0.35)
                        : (client.isOnline
                            ? AppColors.accent.withValues(alpha: 0.35)
                            : AppColors.borderDark),
                  ),
                ),
                child: isCompactMobile
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(_clientOsIcon(client.os), size: 17, color: stateColor),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      client.deviceName,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: AppColors.textWhite,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      metaText,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 10.5,
                                        fontFamily: 'monospace',
                                        color: AppColors.textMuted,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          if (client.workspaceDir.isNotEmpty) ...[
                            const SizedBox(height: 5),
                            Row(
                              children: [
                                const Icon(Icons.folder_outlined, size: 13, color: AppColors.accentCyan),
                                const SizedBox(width: 5),
                                Expanded(
                                  child: Text(
                                    client.workspaceDir,
                                    key: ValueKey('client_workspace_${client.clientId}'),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 10.5,
                                      fontFamily: 'monospace',
                                      color: AppColors.accentCyan,
                                    ),
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'Sao chép đường dẫn thư mục',
                                  constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                                  padding: EdgeInsets.zero,
                                  icon: const Icon(Icons.copy_rounded, size: 13, color: AppColors.textMuted),
                                  onPressed: () async {
                                    await Clipboard.setData(ClipboardData(text: client.workspaceDir));
                                    if (!mounted) return;
                                    AppToast.info(context, 'Đã sao chép thư mục làm việc của "${client.deviceName}".');
                                  },
                                ),
                              ],
                            ),
                          ],
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(child: statusWrap),
                              const SizedBox(width: 8),
                              actionBtn,
                            ],
                          ),
                        ],
                      )
                    : Row(
                        children: [
                          Icon(_clientOsIcon(client.os), size: 18, color: stateColor),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Flexible(
                                      child: Text(
                                        client.deviceName,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          color: AppColors.textWhite,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    statusWrap,
                                  ],
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  metaText,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 10.5,
                                    fontFamily: 'monospace',
                                    color: AppColors.textMuted,
                                  ),
                                ),
                                if (client.workspaceDir.isNotEmpty) ...[
                                  const SizedBox(height: 3),
                                  Row(
                                    children: [
                                      const Icon(Icons.folder_outlined, size: 13, color: AppColors.accentCyan),
                                      const SizedBox(width: 5),
                                      Expanded(
                                        child: Text(
                                          client.workspaceDir,
                                          key: ValueKey('client_workspace_${client.clientId}'),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontSize: 10.5,
                                            fontFamily: 'monospace',
                                            color: AppColors.accentCyan,
                                          ),
                                        ),
                                      ),
                                      IconButton(
                                        tooltip: 'Sao chép đường dẫn thư mục',
                                        constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                                        padding: EdgeInsets.zero,
                                        icon: const Icon(Icons.copy_rounded, size: 13, color: AppColors.textMuted),
                                        onPressed: () async {
                                          await Clipboard.setData(ClipboardData(text: client.workspaceDir));
                                          if (!mounted) return;
                                          AppToast.info(context, 'Đã sao chép thư mục làm việc của "${client.deviceName}".');
                                        },
                                      ),
                                      if (!Platform.isAndroid && !Platform.isIOS)
                                        IconButton(
                                          tooltip: 'Mở thư mục trên máy tính',
                                          constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                                          padding: EdgeInsets.zero,
                                          icon: const Icon(Icons.folder_open_rounded, size: 13, color: AppColors.accentCyan),
                                          onPressed: () => _openWorkspaceFolder(client.workspaceDir),
                                        ),
                                    ],
                                  ),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(width: 10),
                          actionBtn,
                        ],
                      ),
              );
            }),
        ],
      ),
    );
  }

  Widget _buildRoleControlCard({
    required GatewayProvider gateway,
    required bool isCompactMobile,
    required double cardPadding,
  }) {
    final isPrimary = gateway.isPrimary;
    final statusColor = isPrimary
        ? (gateway.isHostRunning ? AppColors.accent : AppColors.textMuted)
        : (gateway.isConnected
            ? AppColors.accent
            : (gateway.status == GatewayStatus.error ? AppColors.danger : AppColors.warning));

    return Container(
      padding: EdgeInsets.all(cardPadding),
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: (isPrimary && gateway.isHostRunning) || (!isPrimary && gateway.isConnected)
              ? AppColors.primaryLight.withValues(alpha: 0.45)
              : AppColors.borderDark,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.devices_other_rounded, size: 18, color: AppColors.accentCyan),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  '0. Vai Trò Thiết Bị (App Chính / App Phụ)',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: statusColor.withValues(alpha: 0.5), width: 0.8),
                ),
                child: Text(
                  isPrimary
                      ? (gateway.isInternetTunnelRunning
                          ? (gateway.onlineClientsCount > 0
                              ? 'Internet • ${gateway.onlineClientsCount} máy'
                              : 'Internet HTTPS')
                          : (gateway.isHostRunning
                              ? (gateway.onlineClientsCount > 0
                                  ? 'Host :${gateway.hostBoundPort} • ${gateway.onlineClientsCount} máy'
                                  : 'Host :${gateway.hostBoundPort}')
                              : 'Cục bộ'))
                      : (gateway.isConnected
                          ? '${gateway.isSecondaryOverInternet ? 'Internet' : 'LAN'} (${gateway.pingMs} ms)'
                          : 'Chưa kết nối'),
                  style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: statusColor),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Switcher chọn App Chính / App Phụ
          Container(
            width: isCompactMobile ? double.infinity : null,
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: AppColors.inputBg,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: AppColors.borderDark),
            ),
            child: Row(
              mainAxisSize: isCompactMobile ? MainAxisSize.max : MainAxisSize.min,
              children: [
                if (isCompactMobile)
                  Expanded(
                    child: _buildRoleSwitchBtn(
                      key: const ValueKey('role_primary_button'),
                      selected: isPrimary,
                      icon: Icons.computer_rounded,
                      label: 'App Chính (Host)',
                      expand: true,
                      onTap: _isApplyingRemote ? null : () => _switchAppRole(AppRole.primary),
                    ),
                  )
                else
                  _buildRoleSwitchBtn(
                    key: const ValueKey('role_primary_button'),
                    selected: isPrimary,
                    icon: Icons.computer_rounded,
                    label: 'App Chính (Host)',
                    onTap: _isApplyingRemote ? null : () => _switchAppRole(AppRole.primary),
                  ),
                const SizedBox(width: 4),
                if (isCompactMobile)
                  Expanded(
                    child: _buildRoleSwitchBtn(
                      key: const ValueKey('role_secondary_button'),
                      selected: !isPrimary,
                      icon: Icons.phonelink_rounded,
                      label: 'App Phụ (Remote)',
                      expand: true,
                      onTap: _isApplyingRemote ? null : () => _switchAppRole(AppRole.secondary),
                    ),
                  )
                else
                  _buildRoleSwitchBtn(
                    key: const ValueKey('role_secondary_button'),
                    selected: !isPrimary,
                    icon: Icons.phonelink_rounded,
                    label: 'App Phụ (Điều khiển từ xa)',
                    onTap: _isApplyingRemote ? null : () => _switchAppRole(AppRole.secondary),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (isPrimary) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.inputBg,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: AppColors.borderDark),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Cho phép App Phụ điều khiển từ xa',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.textWhite),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          gateway.isHostRunning
                              ? 'Đang lắng nghe trên cổng ${gateway.hostBoundPort} • Sẵn sàng nhận lệnh từ App Phụ'
                              : 'Bật để điện thoại hoặc máy tính khác (App Phụ) kết nối và điều khiển máy này',
                          style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Switch(
                    key: const ValueKey('primary_host_toggle'),
                    value: gateway.primaryHostEnabled,
                    activeThumbColor: AppColors.accent,
                    onChanged: (val) async {
                      final ok = await gateway.setPrimaryHostEnabled(val);
                      if (!mounted) return;
                      if (val && ok) {
                        AppToast.success(context, 'Đã bật dịch vụ điều khiển từ xa trên cổng ${gateway.hostBoundPort}.');
                      } else if (val && !ok) {
                        AppToast.error(context, gateway.hostErrorMessage);
                      } else {
                        AppToast.info(context, 'Đã tắt dịch vụ điều khiển từ xa.');
                      }
                    },
                  ),
                ],
              ),
            ),
            if (gateway.hostErrorMessage.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                gateway.hostErrorMessage,
                style: const TextStyle(fontSize: 11.5, color: AppColors.danger),
              ),
            ],
            const SizedBox(height: 12),
            if (isCompactMobile) ...[
              _buildLabeledField(
                label: 'Tên thiết bị App Chính',
                child: TextField(
                  controller: _hostNameCtrl,
                  maxLines: 1,
                  textAlignVertical: TextAlignVertical.center,
                  style: const TextStyle(fontSize: 12.5),
                  decoration: const InputDecoration(
                    hintText: 'VD: Workstation Ubuntu',
                    prefixIcon: Icon(Icons.badge_outlined, size: 16),
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                    constraints: BoxConstraints(minHeight: 34, maxHeight: 34),
                    prefixIconConstraints: BoxConstraints(minWidth: 34, minHeight: 34),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: _buildLabeledField(
                      label: 'Cổng lắng nghe (Port)',
                      child: TextField(
                        controller: _hostPortCtrl,
                        keyboardType: TextInputType.number,
                        maxLines: 1,
                        textAlignVertical: TextAlignVertical.center,
                        style: const TextStyle(fontSize: 12.5, fontFamily: 'monospace'),
                        decoration: const InputDecoration(
                          hintText: '8765',
                          prefixIcon: Icon(Icons.lan_outlined, size: 16),
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                          constraints: BoxConstraints(minHeight: 34, maxHeight: 34),
                          prefixIconConstraints: BoxConstraints(minWidth: 34, minHeight: 34),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      minimumSize: const Size(0, 34),
                      fixedSize: const Size.fromHeight(34),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 0),
                    ),
                    onPressed: _applyPrimaryHostSettings,
                    child: const Text('Áp dụng', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ] else
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    flex: 3,
                    child: _buildLabeledField(
                      label: 'Tên thiết bị App Chính',
                      child: TextField(
                        controller: _hostNameCtrl,
                        maxLines: 1,
                        textAlignVertical: TextAlignVertical.center,
                        style: const TextStyle(fontSize: 12.5),
                        decoration: const InputDecoration(
                          hintText: 'VD: Workstation Ubuntu',
                          prefixIcon: Icon(Icons.badge_outlined, size: 16),
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                          constraints: BoxConstraints(minHeight: 34, maxHeight: 34),
                          prefixIconConstraints: BoxConstraints(minWidth: 34, minHeight: 34),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 140,
                    child: _buildLabeledField(
                      label: 'Cổng (Port)',
                      child: TextField(
                        controller: _hostPortCtrl,
                        keyboardType: TextInputType.number,
                        maxLines: 1,
                        textAlignVertical: TextAlignVertical.center,
                        style: const TextStyle(fontSize: 12.5, fontFamily: 'monospace'),
                        decoration: const InputDecoration(
                          hintText: '8765',
                          prefixIcon: Icon(Icons.lan_outlined, size: 16),
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                          constraints: BoxConstraints(minHeight: 34, maxHeight: 34),
                          prefixIconConstraints: BoxConstraints(minWidth: 34, minHeight: 34),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      minimumSize: const Size(0, 34),
                      fixedSize: const Size.fromHeight(34),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 0),
                    ),
                    onPressed: _applyPrimaryHostSettings,
                    child: const Text('Áp dụng', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            const SizedBox(height: 12),
            // THƯ MỤC GỐC CHỨA CÁC THƯ MỤC LÀM VIỆC RIÊNG CHO TỪNG APP PHỤ
            if (isCompactMobile) ...[
              _buildLabeledField(
                label: 'Thư mục gốc chứa thư mục làm việc cho các App Phụ',
                child: TextField(
                  key: const ValueKey('secondary_workspaces_root_input'),
                  controller: _hostWorkspacesRootCtrl,
                  maxLines: 1,
                  textAlignVertical: TextAlignVertical.center,
                  style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                  decoration: const InputDecoration(
                    hintText: 'VD: /home/user/AI_Type_Workspaces',
                    prefixIcon: Icon(Icons.folder_shared_outlined, size: 16),
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                    constraints: BoxConstraints(minHeight: 34, maxHeight: 34),
                    prefixIconConstraints: BoxConstraints(minWidth: 34, minHeight: 34),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      key: const ValueKey('pick_secondary_workspaces_root_button'),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 32),
                        fixedSize: const Size.fromHeight(32),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        side: const BorderSide(color: AppColors.borderLight),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                      ),
                      icon: const Icon(Icons.folder_open_rounded, size: 14, color: AppColors.accentCyan),
                      label: const Text(
                        'Chọn thư mục',
                        style: TextStyle(fontSize: 11.5, color: AppColors.textBody),
                      ),
                      onPressed: _pickSecondaryWorkspacesRoot,
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    key: const ValueKey('save_secondary_workspaces_root_button'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      minimumSize: const Size(0, 32),
                      fixedSize: const Size.fromHeight(32),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 0),
                    ),
                    onPressed: _applyPrimaryHostSettings,
                    child: const Text('Lưu', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ] else
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: _buildLabeledField(
                      label: 'Thư mục gốc chứa thư mục làm việc cho các App Phụ',
                      child: TextField(
                        key: const ValueKey('secondary_workspaces_root_input'),
                        controller: _hostWorkspacesRootCtrl,
                        maxLines: 1,
                        textAlignVertical: TextAlignVertical.center,
                        style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                        decoration: const InputDecoration(
                          hintText: 'VD: /home/user/AI_Type_Workspaces',
                          prefixIcon: Icon(Icons.folder_shared_outlined, size: 16),
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                          constraints: BoxConstraints(minHeight: 34, maxHeight: 34),
                          prefixIconConstraints: BoxConstraints(minWidth: 34, minHeight: 34),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    key: const ValueKey('pick_secondary_workspaces_root_button'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 34),
                      fixedSize: const Size.fromHeight(34),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      side: const BorderSide(color: AppColors.borderLight),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                    ),
                    icon: const Icon(Icons.folder_open_rounded, size: 15, color: AppColors.accentCyan),
                    label: const Text(
                      'Chọn thư mục',
                      style: TextStyle(fontSize: 12, color: AppColors.textBody),
                    ),
                    onPressed: _pickSecondaryWorkspacesRoot,
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    key: const ValueKey('save_secondary_workspaces_root_button'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      minimumSize: const Size(0, 34),
                      fixedSize: const Size.fromHeight(34),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 0),
                    ),
                    onPressed: _applyPrimaryHostSettings,
                    child: const Text('Lưu', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            const SizedBox(height: 4),
            const Text(
              'Mỗi thiết bị App Phụ khi kết nối sẽ tự động được cấp một thư mục con riêng bên trong thư mục này để chạy Agent, tải tệp và mở Terminal.',
              style: TextStyle(fontSize: 10.5, color: AppColors.textMuted, height: 1.35),
            ),
            const SizedBox(height: 12),
            // PANEL TRUY CẬP INTERNET TOÀN CẦU (MỌI NƠI — 4G/5G / KHÁC MẠNG)
            _buildInternetTunnelPanel(
              gateway: gateway,
              isCompactMobile: isCompactMobile,
            ),
            const SizedBox(height: 12),
            // Hiển thị Mã QR ghép nối nhanh + địa chỉ Internet / VPN / LAN cho App Phụ
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.inputBg,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: AppColors.borderDark),
              ),
              child: Builder(
                builder: (ctx) {
                  final qrWidget = Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      PairingQrWidget(
                        key: const ValueKey('primary_pairing_qr'),
                        data: gateway.primaryPairingString,
                        size: isCompactMobile ? 168 : 148,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        gateway.isInternetTunnelRunning
                            ? 'Mã QR Internet (Mọi nơi + LAN)'
                            : 'Mã QR Mạng LAN',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.bold,
                          color: gateway.isInternetTunnelRunning ? AppColors.accent : AppColors.accentCyan,
                        ),
                      ),
                    ],
                  );

                  final detailsColumn = Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'Quét mã QR trên điện thoại (App Phụ) để kết nối ngay:',
                              style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: AppColors.textWhite),
                            ),
                          ),
                          InkWell(
                            onTap: () => gateway.refreshLocalIps(),
                            borderRadius: BorderRadius.circular(4),
                            child: const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.refresh_rounded, size: 13, color: AppColors.accentCyan),
                                  SizedBox(width: 4),
                                  Text('Làm mới IP', style: TextStyle(fontSize: 11, color: AppColors.accentCyan)),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Trên điện thoại: mở Cấu hình -> App Phụ -> bấm "Quét mã QR trên máy tính" hoặc "Tìm máy tính gần đây".',
                        style: TextStyle(fontSize: 11, color: AppColors.textMuted, height: 1.35),
                      ),
                      const SizedBox(height: 8),
                      if (gateway.isInternetTunnelRunning) ...[
                        SelectableText(
                          'Internet (Mọi nơi): ${gateway.publicTunnelUrl}',
                          style: const TextStyle(
                            fontSize: 11.5,
                            fontFamily: 'monospace',
                            fontWeight: FontWeight.bold,
                            color: AppColors.accent,
                          ),
                        ),
                        const SizedBox(height: 4),
                      ],
                      if (gateway.vpnIps.isNotEmpty) ...[
                        SelectableText(
                          'VPN (Tailscale): ${gateway.vpnIps.map((ip) => 'http://$ip:${gateway.primaryHostPort}').join('  |  ')}',
                          style: const TextStyle(fontSize: 11.5, fontFamily: 'monospace', color: AppColors.primaryLight),
                        ),
                        const SizedBox(height: 4),
                      ],
                      SelectableText(
                        gateway.lanIps.isNotEmpty
                            ? 'Mạng LAN: ${gateway.lanIps.map((ip) => 'http://$ip:${gateway.primaryHostPort}').join('  |  ')}'
                            : 'Mạng LAN: http://127.0.0.1:${gateway.primaryHostPort}',
                        style: const TextStyle(fontSize: 11.5, fontFamily: 'monospace', color: AppColors.accentCyan),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Mã ghép nối: ${_obscureHostToken ? '••••••••••••••••••••' : gateway.primaryHostToken}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 11.5, fontFamily: 'monospace', color: AppColors.textBody),
                            ),
                          ),
                          IconButton(
                            tooltip: _obscureHostToken ? 'Hiện mã' : 'Ẩn mã',
                            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                            padding: EdgeInsets.zero,
                            icon: Icon(
                              _obscureHostToken ? Icons.visibility_rounded : Icons.visibility_off_rounded,
                              size: 15,
                              color: AppColors.textMuted,
                            ),
                            onPressed: () => setState(() => _obscureHostToken = !_obscureHostToken),
                          ),
                          IconButton(
                            tooltip: 'Tạo mã ghép nối mới',
                            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                            padding: EdgeInsets.zero,
                            icon: const Icon(Icons.autorenew_rounded, size: 15, color: AppColors.warning),
                            onPressed: () async {
                              await gateway.regeneratePrimaryToken();
                              if (!mounted) return;
                              AppToast.info(context, 'Đã tạo mã ghép nối và mã QR mới.');
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          SizedBox(
                            width: isCompactMobile ? double.infinity : null,
                            height: 32,
                            child: OutlinedButton.icon(
                              key: const ValueKey('copy_pairing_string_button'),
                              style: OutlinedButton.styleFrom(
                                minimumSize: const Size(0, 32),
                                fixedSize: const Size.fromHeight(32),
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                side: BorderSide(
                                  color: gateway.isInternetTunnelRunning ? AppColors.accent : AppColors.primaryLight,
                                ),
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                              ),
                              icon: Icon(
                                gateway.isInternetTunnelRunning ? Icons.public_rounded : Icons.copy_rounded,
                                size: 14,
                                color: gateway.isInternetTunnelRunning ? AppColors.accent : AppColors.primaryLight,
                              ),
                              label: Text(
                                gateway.isInternetTunnelRunning
                                    ? 'Sao chép chuỗi ghép nối Internet (Mọi nơi)'
                                    : 'Sao chép chuỗi ghép nối nhanh',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600,
                                  color: gateway.isInternetTunnelRunning ? AppColors.accent : AppColors.primaryLight,
                                ),
                              ),
                              onPressed: () async {
                                await Clipboard.setData(ClipboardData(text: gateway.primaryPairingString));
                                if (!mounted) return;
                                AppToast.success(
                                  context,
                                  gateway.isInternetTunnelRunning
                                      ? 'Đã sao chép chuỗi ghép nối Internet (dùng được ở mọi nơi)!'
                                      : 'Đã sao chép chuỗi ghép nối nhanh vào bộ nhớ tạm!',
                                );
                              },
                            ),
                          ),
                          if (gateway.isInternetTunnelRunning)
                            SizedBox(
                              width: isCompactMobile ? double.infinity : null,
                              height: 32,
                              child: OutlinedButton.icon(
                                key: const ValueKey('copy_lan_pairing_button'),
                                style: OutlinedButton.styleFrom(
                                  minimumSize: const Size(0, 32),
                                  fixedSize: const Size.fromHeight(32),
                                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  side: const BorderSide(color: AppColors.borderLight),
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                                ),
                                icon: const Icon(Icons.lan_outlined, size: 14, color: AppColors.textMuted),
                                label: const Text(
                                  'Sao chép LAN',
                                  style: TextStyle(fontSize: 11.5, color: AppColors.textBody),
                                ),
                                onPressed: () async {
                                  await Clipboard.setData(ClipboardData(text: gateway.primaryLanPairingString));
                                  if (!mounted) return;
                                  AppToast.info(context, 'Đã sao chép chuỗi ghép nối mạng LAN.');
                                },
                              ),
                            ),
                        ],
                      ),
                    ],
                  );

                  if (isCompactMobile) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Center(child: qrWidget),
                        const SizedBox(height: 12),
                        detailsColumn,
                      ],
                    );
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      qrWidget,
                      const SizedBox(width: 16),
                      Expanded(child: detailsColumn),
                    ],
                  );
                },
              ),
            ),
            if (gateway.isHostRunning || gateway.connectedClients.isNotEmpty) ...[
              const SizedBox(height: 12),
              _buildConnectedClientsPanel(
                gateway: gateway,
                isCompactMobile: isCompactMobile,
              ),
            ],
          ] else ...[
            // Chế độ APP PHỤ: Thẻ trạng thái + Nút Ngắt kết nối rõ ràng
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.09),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: statusColor.withValues(alpha: 0.45)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 1),
                        child: Icon(
                          gateway.isConnected ? Icons.check_circle_rounded : Icons.phonelink_setup_rounded,
                          size: 18,
                          color: statusColor,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              gateway.isConnected
                                  ? 'Đang kết nối App Chính: ${gateway.remoteHostName}'
                                      '${gateway.remoteHostOs.isNotEmpty ? ' (${gateway.remoteHostOs.toUpperCase()})' : ''}'
                                  : (gateway.errorMessage.isNotEmpty
                                      ? gateway.errorMessage
                                      : 'Chưa kết nối App Chính. Chọn 1 trong 3 cách bên dưới để điều khiển máy tính từ xa.'),
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textWhite,
                                height: 1.35,
                              ),
                            ),
                            if (gateway.isConnected && gateway.gatewayUrl.isNotEmpty) ...[
                              const SizedBox(height: 3),
                              Text(
                                '${gateway.isSecondaryOverInternet ? 'Internet' : 'LAN'} • ${gateway.gatewayUrl} • ${gateway.pingMs} ms',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontFamily: 'monospace',
                                  color: AppColors.accentCyan,
                                ),
                              ),
                            ],
                            if (gateway.isConnected && gateway.remoteClientWorkspaceDir.isNotEmpty) ...[
                              const SizedBox(height: 3),
                              Text(
                                'Thư mục làm việc: ${gateway.remoteClientWorkspaceDir}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 10.5,
                                  fontFamily: 'monospace',
                                  color: AppColors.textBody,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (gateway.isConnected) ...[
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: SizedBox(
                            height: 32,
                            child: OutlinedButton.icon(
                              key: const ValueKey('secondary_refresh_connection_button'),
                              style: OutlinedButton.styleFrom(
                                minimumSize: const Size(0, 32),
                                fixedSize: const Size.fromHeight(32),
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                side: const BorderSide(color: AppColors.borderLight),
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                              ),
                              icon: _isApplyingRemote
                                  ? const SizedBox(
                                      width: 13,
                                      height: 13,
                                      child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.textWhite),
                                    )
                                  : const Icon(Icons.refresh_rounded, size: 14, color: AppColors.textBody),
                              label: const Text(
                                'Kiểm tra lại',
                                style: TextStyle(fontSize: 11.5, color: AppColors.textBody),
                              ),
                              onPressed: _isApplyingRemote ? null : _refreshSecondaryConnection,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: SizedBox(
                            height: 32,
                            child: OutlinedButton.icon(
                              key: const ValueKey('secondary_disconnect_button'),
                              style: OutlinedButton.styleFrom(
                                minimumSize: const Size(0, 32),
                                fixedSize: const Size.fromHeight(32),
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                side: BorderSide(color: AppColors.danger.withValues(alpha: 0.7)),
                                backgroundColor: AppColors.danger.withValues(alpha: 0.1),
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                              ),
                              icon: const Icon(Icons.link_off_rounded, size: 14, color: AppColors.danger),
                              label: const Text(
                                'Ngắt kết nối',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.danger,
                                ),
                              ),
                              onPressed: _isApplyingRemote ? null : _disconnectSecondaryFromPrimary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 12),
            if (gateway.isConnected) ...[
              const Text(
                'Đổi sang máy tính App Chính khác:',
                style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: AppColors.textMuted),
              ),
              const SizedBox(height: 8),
            ],

            // 2 HÀNH ĐỘNG CHÍNH TRỰC QUAN: QUÉT MÃ QR & TÌM MÁY TÍNH GẦN ĐÂY
            if (isCompactMobile) ...[
              if (QrScannerScreen.isCameraScanSupported) ...[
                SizedBox(
                  width: double.infinity,
                  height: 40,
                  child: ElevatedButton.icon(
                    key: const ValueKey('secondary_scan_qr_button'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      minimumSize: const Size(0, 40),
                      fixedSize: const Size.fromHeight(40),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    icon: const Icon(Icons.qr_code_scanner_rounded, size: 18),
                    label: const Text(
                      'Quét mã QR trên máy tính (Nhanh nhất)',
                      style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold),
                    ),
                    onPressed: _isApplyingRemote ? null : _scanQrAndConnect,
                  ),
                ),
                const SizedBox(height: 8),
              ],
              SizedBox(
                width: double.infinity,
                height: 36,
                child: OutlinedButton.icon(
                  key: const ValueKey('secondary_discover_hosts_button'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 36),
                    fixedSize: const Size.fromHeight(36),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    side: const BorderSide(color: AppColors.accentCyan),
                  ),
                  icon: gateway.isDiscoveringHosts
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accentCyan),
                        )
                      : const Icon(Icons.radar_rounded, size: 16, color: AppColors.accentCyan),
                  label: Text(
                    gateway.isDiscoveringHosts
                        ? 'Đang tìm máy tính trong Wi-Fi...'
                        : 'Tìm máy tính gần đây (1 chạm)',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.accentCyan),
                  ),
                  onPressed: (gateway.isDiscoveringHosts || gateway.isWaitingPairingApproval)
                      ? null
                      : () => gateway.discoverNearbyPrimaryHosts(),
                ),
              ),
            ] else
              Row(
                children: [
                  if (QrScannerScreen.isCameraScanSupported) ...[
                    Expanded(
                      child: SizedBox(
                        height: 38,
                        child: ElevatedButton.icon(
                          key: const ValueKey('secondary_scan_qr_button'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            minimumSize: const Size(0, 38),
                            fixedSize: const Size.fromHeight(38),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          icon: const Icon(Icons.qr_code_scanner_rounded, size: 17),
                          label: const Text(
                            'Quét mã QR trên App Chính',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                          ),
                          onPressed: _isApplyingRemote ? null : _scanQrAndConnect,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                  ],
                  Expanded(
                    child: SizedBox(
                      height: 38,
                      child: OutlinedButton.icon(
                        key: const ValueKey('secondary_discover_hosts_button'),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, 38),
                          fixedSize: const Size.fromHeight(38),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          side: const BorderSide(color: AppColors.accentCyan),
                        ),
                        icon: gateway.isDiscoveringHosts
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accentCyan),
                              )
                            : const Icon(Icons.radar_rounded, size: 16, color: AppColors.accentCyan),
                        label: Text(
                          gateway.isDiscoveringHosts
                              ? 'Đang tìm máy tính...'
                              : 'Tìm máy tính App Chính gần đây (1 chạm)',
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.accentCyan),
                        ),
                        onPressed: (gateway.isDiscoveringHosts || gateway.isWaitingPairingApproval)
                            ? null
                            : () => gateway.discoverNearbyPrimaryHosts(),
                      ),
                    ),
                  ),
                ],
              ),

            // TRẠNG THÁI CHỜ BẤM "CHẤP NHẬN" TRÊN MÁY TÍNH (GHÉP NỐI 1 CHẠM)
            if (gateway.isWaitingPairingApproval) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.accentCyan.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: AppColors.accentCyan.withValues(alpha: 0.55)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accentCyan),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Đang chờ bạn bấm "Chấp nhận kết nối" trên màn hình máy tính ${gateway.pairingTargetName}...',
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.textWhite),
                          ),
                        ),
                      ],
                    ),
                    if (gateway.activePairingPin.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Text('Mã đối chiếu: ', style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
                          Text(
                            gateway.activePairingPin,
                            style: const TextStyle(
                              fontSize: 18,
                              fontFamily: 'monospace',
                              fontWeight: FontWeight.bold,
                              letterSpacing: 3,
                              color: AppColors.accentCyan,
                            ),
                          ),
                          const Spacer(),
                          TextButton(
                            onPressed: () => gateway.cancelOneTapPairing(),
                            child: const Text('Hủy', style: TextStyle(color: AppColors.danger, fontSize: 12)),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],

            // DANH SÁCH MÁY TÍNH APP CHÍNH TÌM THẤY TRONG MẠNG GẦN ĐÂY
            if (gateway.discoveredHosts.isNotEmpty) ...[
              const SizedBox(height: 10),
              ...gateway.discoveredHosts.map((host) {
                return Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppColors.inputBg,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: AppColors.primaryLight.withValues(alpha: 0.45)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.computer_rounded, size: 18, color: AppColors.primaryLight),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${host.deviceName} (${host.os.toUpperCase()})',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: AppColors.textWhite,
                              ),
                            ),
                            Text(
                              host.hasInternetAccess
                                  ? '${host.preferredUrl} (Sẵn sàng mọi nơi)'
                                  : host.lanUrl,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 11,
                                fontFamily: 'monospace',
                                color: AppColors.accentCyan,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          minimumSize: const Size(0, 30),
                          fixedSize: const Size.fromHeight(30),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                        ),
                        onPressed: (_isApplyingRemote || gateway.isWaitingPairingApproval)
                            ? null
                            : () => _requestOneTapPair(host),
                        child: const Text('Kết nối', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                );
              }),
            ] else if (gateway.pairingStatusMessage.isNotEmpty && !gateway.isWaitingPairingApproval) ...[
              const SizedBox(height: 8),
              Text(
                gateway.pairingStatusMessage,
                style: const TextStyle(fontSize: 11, color: AppColors.textMuted, height: 1.35),
              ),
            ],

            const SizedBox(height: 10),
            // MỤC GẬP GỌN: KẾT NỐI THỦ CÔNG (TÁCH RÕ 2 TAB: DÁN CHUỖI HOẶC NHẬP URL + MÃ)
            InkWell(
              key: const ValueKey('toggle_manual_connect_button'),
              borderRadius: BorderRadius.circular(4),
              onTap: () => setState(() => _showManualRemoteConnect = !_showManualRemoteConnect),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.inputBg,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: _showManualRemoteConnect ? AppColors.primaryLight.withValues(alpha: 0.5) : AppColors.borderDark,
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.tune_rounded, size: 14, color: AppColors.textMuted),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Kết nối thủ công (chọn Dán chuỗi hoặc Nhập URL & Mã)',
                        style: TextStyle(fontSize: 11.5, color: AppColors.textBody, fontWeight: FontWeight.w500),
                      ),
                    ),
                    Icon(
                      _showManualRemoteConnect ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                      size: 18,
                      color: AppColors.textMuted,
                    ),
                  ],
                ),
              ),
            ),

            if (_showManualRemoteConnect) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.bgDark.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: AppColors.borderDark),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Chuyển đổi rành mạch giữa 2 cách nhập thủ công (không bày trùng lắp 3 ô cùng lúc)
                    Container(
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        color: AppColors.inputBg,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: AppColors.borderDark),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: InkWell(
                              key: const ValueKey('manual_mode_paste_tab'),
                              borderRadius: BorderRadius.circular(3),
                              onTap: () => setState(() => _manualConnectMode = 'paste'),
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                                decoration: BoxDecoration(
                                  color: _manualConnectMode == 'paste'
                                      ? AppColors.primary.withValues(alpha: 0.25)
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(3),
                                  border: Border.all(
                                    color: _manualConnectMode == 'paste'
                                        ? AppColors.primaryLight.withValues(alpha: 0.65)
                                        : Colors.transparent,
                                  ),
                                ),
                                child: Text(
                                  '1. Dán chuỗi ghép nối',
                                  textAlign: TextAlign.center,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: _manualConnectMode == 'paste' ? FontWeight.bold : FontWeight.w500,
                                    color: _manualConnectMode == 'paste' ? AppColors.primaryLight : AppColors.textMuted,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: InkWell(
                              key: const ValueKey('manual_mode_fields_tab'),
                              borderRadius: BorderRadius.circular(3),
                              onTap: () => setState(() => _manualConnectMode = 'fields'),
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                                decoration: BoxDecoration(
                                  color: _manualConnectMode == 'fields'
                                      ? AppColors.primary.withValues(alpha: 0.25)
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(3),
                                  border: Border.all(
                                    color: _manualConnectMode == 'fields'
                                        ? AppColors.primaryLight.withValues(alpha: 0.65)
                                        : Colors.transparent,
                                  ),
                                ),
                                child: Text(
                                  '2. Nhập URL & Mã',
                                  textAlign: TextAlign.center,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: _manualConnectMode == 'fields' ? FontWeight.bold : FontWeight.w500,
                                    color: _manualConnectMode == 'fields' ? AppColors.primaryLight : AppColors.textMuted,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    if (_manualConnectMode == 'paste') ...[
                      const Text(
                        'Trên máy tính App Chính: bấm nút "Sao chép chuỗi ghép nối" rồi dán vào ô dưới đây (đã bao gồm sẵn địa chỉ và mã bảo mật).',
                        style: TextStyle(fontSize: 11, color: AppColors.textMuted, height: 1.35),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              key: const ValueKey('secondary_pairing_paste_input'),
                              controller: _pairingPasteCtrl,
                              maxLines: 1,
                              textAlignVertical: TextAlignVertical.center,
                              style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                              onChanged: (_) => setState(() {}),
                              decoration: const InputDecoration(
                                hintText: 'http://192.168.1.x:8765#<mã> hoặc https://...#<mã>',
                                hintStyle: TextStyle(fontSize: 11),
                                prefixIcon: Icon(Icons.content_paste_rounded, size: 15),
                                isDense: true,
                                contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                                constraints: BoxConstraints(minHeight: 34, maxHeight: 34),
                                prefixIconConstraints: BoxConstraints(minWidth: 34, minHeight: 34),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size(0, 34),
                              fixedSize: const Size.fromHeight(34),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                              side: const BorderSide(color: AppColors.borderLight),
                            ),
                            onPressed: () async {
                              final data = await Clipboard.getData(Clipboard.kTextPlain);
                              final clip = data?.text?.trim() ?? '';
                              if (clip.isEmpty) return;
                              setState(() {
                                _pairingPasteCtrl.text = clip;
                              });
                            },
                            child: const Text('Dán', style: TextStyle(fontSize: 11.5, color: AppColors.textWhite)),
                          ),
                        ],
                      ),
                      Builder(
                        builder: (_) {
                          final raw = _pairingPasteCtrl.text.trim();
                          if (raw.isEmpty) return const SizedBox.shrink();
                          final parsed = StorageService.parsePairingString(raw);
                          if (parsed.url.isEmpty) return const SizedBox.shrink();
                          return Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              'Đã nhận diện: ${parsed.url} • ${parsed.token.isNotEmpty ? 'Có mã ghép nối' : 'Chưa có mã (#token)'}',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 10.5,
                                fontFamily: 'monospace',
                                color: parsed.token.isNotEmpty ? AppColors.accent : AppColors.warning,
                              ),
                            ),
                          );
                        },
                      ),
                    ] else ...[
                      const Text(
                        'Xem trên máy tính App Chính (mục 0 -> Vai Trò Thiết Bị): sao chép dòng Mạng LAN/Internet và dòng Mã ghép nối.',
                        style: TextStyle(fontSize: 11, color: AppColors.textMuted, height: 1.35),
                      ),
                      const SizedBox(height: 8),
                      if (isCompactMobile) ...[
                        _buildLabeledField(
                          label: '1. Địa chỉ máy tính App Chính (URL)',
                          child: TextField(
                            key: const ValueKey('secondary_url_input'),
                            controller: _remoteUrlCtrl,
                            maxLines: 1,
                            textAlignVertical: TextAlignVertical.center,
                            style: const TextStyle(fontSize: 12.5, fontFamily: 'monospace'),
                            decoration: const InputDecoration(
                              hintText: 'http://192.168.1.x:8765 hoặc https://...',
                              hintStyle: TextStyle(fontSize: 11.5),
                              prefixIcon: Icon(Icons.link_rounded, size: 16),
                              isDense: true,
                              contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                              constraints: BoxConstraints(minHeight: 34, maxHeight: 34),
                              prefixIconConstraints: BoxConstraints(minWidth: 34, minHeight: 34),
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        _buildLabeledField(
                          label: '2. Mã ghép nối (Token)',
                          child: TextField(
                            key: const ValueKey('secondary_token_input'),
                            controller: _remoteTokenCtrl,
                            obscureText: _obscureRemoteToken,
                            maxLines: 1,
                            textAlignVertical: TextAlignVertical.center,
                            style: const TextStyle(fontSize: 12.5, fontFamily: 'monospace'),
                            decoration: InputDecoration(
                              hintText: 'Dán Mã ghép nối từ App Chính...',
                              hintStyle: const TextStyle(fontSize: 11.5),
                              prefixIcon: const Icon(Icons.lock_outline_rounded, size: 16),
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                              constraints: const BoxConstraints(minHeight: 34, maxHeight: 34),
                              prefixIconConstraints: const BoxConstraints(minWidth: 34, minHeight: 34),
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _obscureRemoteToken ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                                  size: 16,
                                  color: AppColors.textMuted,
                                ),
                                onPressed: () => setState(() => _obscureRemoteToken = !_obscureRemoteToken),
                              ),
                            ),
                          ),
                        ),
                      ] else
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Expanded(
                              child: _buildLabeledField(
                                label: '1. Địa chỉ máy tính App Chính (URL)',
                                child: TextField(
                                  key: const ValueKey('secondary_url_input'),
                                  controller: _remoteUrlCtrl,
                                  maxLines: 1,
                                  textAlignVertical: TextAlignVertical.center,
                                  style: const TextStyle(fontSize: 12.5, fontFamily: 'monospace'),
                                  decoration: const InputDecoration(
                                    hintText: 'http://192.168.1.x:8765 hoặc https://...',
                                    hintStyle: TextStyle(fontSize: 11.5),
                                    prefixIcon: Icon(Icons.link_rounded, size: 16),
                                    isDense: true,
                                    contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                                    constraints: BoxConstraints(minHeight: 34, maxHeight: 34),
                                    prefixIconConstraints: BoxConstraints(minWidth: 34, minHeight: 34),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: _buildLabeledField(
                                label: '2. Mã ghép nối (Token)',
                                child: TextField(
                                  key: const ValueKey('secondary_token_input'),
                                  controller: _remoteTokenCtrl,
                                  obscureText: _obscureRemoteToken,
                                  maxLines: 1,
                                  textAlignVertical: TextAlignVertical.center,
                                  style: const TextStyle(fontSize: 12.5, fontFamily: 'monospace'),
                                  decoration: InputDecoration(
                                    hintText: 'Dán Mã ghép nối từ App Chính...',
                                    hintStyle: const TextStyle(fontSize: 11.5),
                                    prefixIcon: const Icon(Icons.lock_outline_rounded, size: 16),
                                    isDense: true,
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                                    constraints: const BoxConstraints(minHeight: 34, maxHeight: 34),
                                    prefixIconConstraints: const BoxConstraints(minWidth: 34, minHeight: 34),
                                    suffixIcon: IconButton(
                                      icon: Icon(
                                        _obscureRemoteToken ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                                        size: 16,
                                        color: AppColors.textMuted,
                                      ),
                                      onPressed: () => setState(() => _obscureRemoteToken = !_obscureRemoteToken),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                    ],
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      height: 34,
                      child: ElevatedButton.icon(
                        key: const ValueKey('secondary_connect_button'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          minimumSize: const Size(0, 34),
                          fixedSize: const Size.fromHeight(34),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                        ),
                        icon: _isApplyingRemote
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.sync_rounded, size: 15),
                        label: Text(
                          _isApplyingRemote
                              ? 'Đang kết nối...'
                              : (_manualConnectMode == 'paste'
                                  ? 'Kết nối bằng chuỗi đã dán'
                                  : 'Kết nối tới App Chính'),
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                        onPressed: _isApplyingRemote ? null : _connectSecondaryToPrimary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildInternetTunnelPanel({
    required GatewayProvider gateway,
    required bool isCompactMobile,
  }) {
    final mode = gateway.tunnelMode;
    final state = gateway.tunnelState;
    final Color badgeColor = switch (state) {
      RemoteTunnelState.running => AppColors.accent,
      RemoteTunnelState.starting || RemoteTunnelState.installing => AppColors.accentCyan,
      RemoteTunnelState.error => AppColors.danger,
      RemoteTunnelState.stopped => AppColors.textMuted,
    };
    final String badgeText = switch (state) {
      RemoteTunnelState.running => 'Đang hoạt động',
      RemoteTunnelState.starting => 'Đang kết nối...',
      RemoteTunnelState.installing => 'Đang tải...',
      RemoteTunnelState.error => 'Lỗi Tunnel',
      RemoteTunnelState.stopped => mode == RemoteTunnelMode.off ? 'Tắt (Chỉ LAN)' : 'Chưa chạy',
    };

    Widget modeTile({
      required Key key,
      required RemoteTunnelMode targetMode,
      required IconData icon,
      required String label,
    }) {
      final selected = mode == targetMode;
      return InkWell(
        key: key,
        borderRadius: BorderRadius.circular(4),
        onTap: gateway.isInternetTunnelBusy
            ? null
            : () async {
                final autoStart = targetMode == RemoteTunnelMode.cloudflareQuick ||
                    targetMode == RemoteTunnelMode.off ||
                    (targetMode == RemoteTunnelMode.customUrl && _tunnelCustomUrlCtrl.text.trim().isNotEmpty) ||
                    (targetMode == RemoteTunnelMode.cloudflareNamed &&
                        _tunnelNamedTokenCtrl.text.trim().isNotEmpty &&
                        _tunnelCustomUrlCtrl.text.trim().isNotEmpty);
                await gateway.setTunnelMode(targetMode, autoStart: autoStart);
                if (!mounted) return;
                if (targetMode == RemoteTunnelMode.off) {
                  AppToast.info(context, 'Đã tắt đường hầm Internet (chỉ kết nối trong mạng LAN).');
                }
              },
        child: Container(
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: selected ? AppColors.primary.withValues(alpha: 0.22) : AppColors.bgDark,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: selected ? AppColors.primaryLight : AppColors.borderDark,
              width: selected ? 1.2 : 1,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 13.5, color: selected ? AppColors.primaryLight : AppColors.textMuted),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: selected ? FontWeight.bold : FontWeight.w500,
                    color: selected ? AppColors.textWhite : AppColors.textMuted,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.inputBg,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: gateway.isInternetTunnelRunning
              ? AppColors.accent.withValues(alpha: 0.45)
              : AppColors.borderDark,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.public_rounded,
                size: 15,
                color: gateway.isInternetTunnelRunning ? AppColors.accent : AppColors.accentCyan,
              ),
              const SizedBox(width: 6),
              const Expanded(
                child: Text(
                  'Kết nối từ bất kỳ đâu qua Internet (4G/5G / Khác mạng)',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: AppColors.textWhite),
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: badgeColor.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(3),
                  border: Border.all(color: badgeColor.withValues(alpha: 0.45), width: 0.8),
                ),
                child: Text(
                  badgeText,
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: badgeColor),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _buildAlignedGrid(
            columns: isCompactMobile ? 2 : 4,
            spacing: 6,
            children: [
              modeTile(
                key: const ValueKey('tunnel_mode_off'),
                targetMode: RemoteTunnelMode.off,
                icon: Icons.lan_outlined,
                label: 'Chỉ LAN',
              ),
              modeTile(
                key: const ValueKey('tunnel_mode_quick'),
                targetMode: RemoteTunnelMode.cloudflareQuick,
                icon: Icons.bolt_rounded,
                label: 'Internet 1 chạm',
              ),
              modeTile(
                key: const ValueKey('tunnel_mode_named'),
                targetMode: RemoteTunnelMode.cloudflareNamed,
                icon: Icons.dns_rounded,
                label: 'Domain cố định',
              ),
              modeTile(
                key: const ValueKey('tunnel_mode_custom'),
                targetMode: RemoteTunnelMode.customUrl,
                icon: Icons.vpn_lock_rounded,
                label: 'URL / VPN riêng',
              ),
            ],
          ),
          if (mode == RemoteTunnelMode.cloudflareQuick) ...[
            const SizedBox(height: 8),
            if (!RemoteTunnelService.isDesktopTunnelSupported)
              const Text(
                'Đường hầm Cloudflare 1 chạm hỗ trợ khi App Chính chạy trên máy tính (Linux, Windows, macOS). Trên điện thoại, hãy chọn "URL / VPN riêng" (Tailscale).',
                style: TextStyle(fontSize: 11, color: AppColors.textMuted, height: 1.35),
              )
            else ...[
              const Text(
                'Tự mở đường hầm HTTPS/WSS mã hóa qua Cloudflare (miễn phí, không cần tài khoản hay mở port router). Địa chỉ sẽ thay đổi nếu khởi động lại máy.',
                style: TextStyle(fontSize: 11, color: AppColors.textMuted, height: 1.35),
              ),
              const SizedBox(height: 8),
              if (!gateway.hasCloudflaredBinary && state != RemoteTunnelState.installing)
                SizedBox(
                  height: 32,
                  child: ElevatedButton.icon(
                    key: const ValueKey('install_cloudflared_button'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      minimumSize: const Size(0, 32),
                      fixedSize: const Size.fromHeight(32),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                    ),
                    icon: const Icon(Icons.download_rounded, size: 14),
                    label: const Text(
                      'Tải cloudflared tự động (không cần sudo)',
                      style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold),
                    ),
                    onPressed: () async {
                      final ok = await gateway.installCloudflared();
                      if (!mounted) return;
                      if (ok) {
                        AppToast.success(context, 'Đã cài đặt cloudflared và khởi chạy đường hầm Internet!');
                      } else {
                        AppToast.error(context, gateway.tunnelErrorMessage);
                      }
                    },
                  ),
                ),
              if (state == RemoteTunnelState.installing) ...[
                LinearProgressIndicator(
                  value: gateway.cloudflaredDownloadProgress > 0 ? gateway.cloudflaredDownloadProgress : null,
                  minHeight: 4,
                  backgroundColor: AppColors.borderDark,
                  valueColor: const AlwaysStoppedAnimation<Color>(AppColors.accentCyan),
                ),
                const SizedBox(height: 6),
              ],
              if (gateway.tunnelStatusMessage.isNotEmpty)
                Row(
                  children: [
                    if (gateway.isInternetTunnelBusy) ...[
                      const SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(strokeWidth: 1.8, color: AppColors.accentCyan),
                      ),
                      const SizedBox(width: 8),
                    ],
                    Expanded(
                      child: Text(
                        gateway.tunnelStatusMessage,
                        style: TextStyle(
                          fontSize: 11,
                          color: gateway.isInternetTunnelRunning ? AppColors.accent : AppColors.accentCyan,
                        ),
                      ),
                    ),
                    if (!gateway.isInternetTunnelBusy)
                      IconButton(
                        tooltip: 'Khởi tạo lại đường hầm Internet',
                        constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                        padding: EdgeInsets.zero,
                        icon: const Icon(Icons.refresh_rounded, size: 15, color: AppColors.accentCyan),
                        onPressed: () => gateway.restartTunnel(),
                      ),
                  ],
                ),
            ],
          ],
          if (mode == RemoteTunnelMode.cloudflareNamed) ...[
            const SizedBox(height: 8),
            const Text(
              'Dùng Cloudflare Zero Trust Tunnel để cố định tên miền mãi mãi (không đổi sau khi khởi động lại máy). Trỏ Public Hostname về http://127.0.0.1:<Port>.',
              style: TextStyle(fontSize: 11, color: AppColors.textMuted, height: 1.35),
            ),
            const SizedBox(height: 8),
            _buildLabeledField(
              label: 'Tên miền cố định của App Chính (https://...)',
              child: TextField(
                key: const ValueKey('named_tunnel_url_input'),
                controller: _tunnelCustomUrlCtrl,
                maxLines: 1,
                textAlignVertical: TextAlignVertical.center,
                style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                decoration: const InputDecoration(
                  hintText: 'https://agent.tenmiencuaban.com',
                  hintStyle: TextStyle(fontSize: 11.5),
                  prefixIcon: Icon(Icons.public_rounded, size: 15),
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                  constraints: BoxConstraints(minHeight: 34, maxHeight: 34),
                  prefixIconConstraints: BoxConstraints(minWidth: 34, minHeight: 34),
                ),
              ),
            ),
            const SizedBox(height: 8),
            _buildLabeledField(
              label: 'Cloudflare Tunnel Token',
              child: TextField(
                key: const ValueKey('named_tunnel_token_input'),
                controller: _tunnelNamedTokenCtrl,
                obscureText: _obscureTunnelToken,
                maxLines: 1,
                textAlignVertical: TextAlignVertical.center,
                style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                decoration: InputDecoration(
                  hintText: 'eyJhIjoi... (Token từ Cloudflare Zero Trust)',
                  hintStyle: const TextStyle(fontSize: 11.5),
                  prefixIcon: const Icon(Icons.vpn_key_outlined, size: 15),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                  constraints: const BoxConstraints(minHeight: 34, maxHeight: 34),
                  prefixIconConstraints: const BoxConstraints(minWidth: 34, minHeight: 34),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscureTunnelToken ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                      size: 15,
                      color: AppColors.textMuted,
                    ),
                    onPressed: () => setState(() => _obscureTunnelToken = !_obscureTunnelToken),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: isCompactMobile ? double.infinity : null,
              height: 32,
              child: ElevatedButton.icon(
                key: const ValueKey('apply_named_tunnel_button'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  minimumSize: const Size(0, 32),
                  fixedSize: const Size.fromHeight(32),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                ),
                icon: const Icon(Icons.cloud_done_rounded, size: 14),
                label: const Text(
                  'Lưu & Kết nối Domain cố định',
                  style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold),
                ),
                onPressed: gateway.isInternetTunnelBusy
                    ? null
                    : () async {
                        final ok = await gateway.applyNamedTunnel(
                          tunnelToken: _tunnelNamedTokenCtrl.text.trim(),
                          publicUrl: _tunnelCustomUrlCtrl.text.trim(),
                        );
                        if (!mounted) return;
                        if (ok) {
                          AppToast.success(context, 'Đã kết nối Domain cố định: ${gateway.publicTunnelUrl}');
                        } else {
                          AppToast.error(
                            context,
                            gateway.tunnelErrorMessage.isNotEmpty
                                ? gateway.tunnelErrorMessage
                                : 'Không thể kết nối Named Tunnel.',
                          );
                        }
                      },
              ),
            ),
          ],
          if (mode == RemoteTunnelMode.customUrl) ...[
            const SizedBox(height: 8),
            const Text(
              'Dùng địa chỉ công khai riêng (VPS Reverse Proxy, Nginx, FRP, hoặc mạng VPN Mesh Tailscale/ZeroTier).',
              style: TextStyle(fontSize: 11, color: AppColors.textMuted, height: 1.35),
            ),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: _buildLabeledField(
                    label: 'Địa chỉ công khai / IP VPN Mesh',
                    child: TextField(
                      key: const ValueKey('custom_public_url_input'),
                      controller: _tunnelCustomUrlCtrl,
                      maxLines: 1,
                      textAlignVertical: TextAlignVertical.center,
                      style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                      decoration: const InputDecoration(
                        hintText: 'https://agent.domain.com hoặc http://100.x.x.x:8765',
                        hintStyle: TextStyle(fontSize: 11.5),
                        prefixIcon: Icon(Icons.link_rounded, size: 15),
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                        constraints: BoxConstraints(minHeight: 34, maxHeight: 34),
                        prefixIconConstraints: BoxConstraints(minWidth: 34, minHeight: 34),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  key: const ValueKey('apply_custom_url_button'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    minimumSize: const Size(0, 34),
                    fixedSize: const Size.fromHeight(34),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                  ),
                  onPressed: () async {
                    final ok = await gateway.applyCustomPublicUrl(_tunnelCustomUrlCtrl.text.trim());
                    if (!mounted) return;
                    if (ok) {
                      AppToast.success(context, 'Đã áp dụng địa chỉ truy cập từ xa: ${gateway.publicTunnelUrl}');
                    } else {
                      AppToast.warning(context, 'Vui lòng nhập địa chỉ URL hợp lệ.');
                    }
                  },
                  child: const Text('Áp dụng', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
            if (gateway.vpnIps.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: gateway.vpnIps.map((vpnIp) {
                  final candidate = 'http://$vpnIp:${gateway.primaryHostPort}';
                  return InkWell(
                    borderRadius: BorderRadius.circular(4),
                    onTap: () async {
                      _tunnelCustomUrlCtrl.text = candidate;
                      await gateway.applyCustomPublicUrl(candidate);
                      if (!mounted) return;
                      AppToast.success(context, 'Đã chọn địa chỉ Tailscale VPN: $candidate');
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: AppColors.primaryLight.withValues(alpha: 0.5)),
                      ),
                      child: Text(
                        'Chọn nhanh Tailscale: $candidate',
                        style: const TextStyle(
                          fontSize: 11,
                          fontFamily: 'monospace',
                          color: AppColors.primaryLight,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ],
          if (gateway.tunnelErrorMessage.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              gateway.tunnelErrorMessage,
              style: const TextStyle(fontSize: 11, color: AppColors.danger, height: 1.35),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildRoleSwitchBtn({
    Key? key,
    required bool selected,
    required IconData icon,
    required String label,
    bool expand = false,
    VoidCallback? onTap,
  }) {
    return InkWell(
      key: key,
      borderRadius: BorderRadius.circular(4),
      onTap: onTap,
      child: Container(
        height: 32,
        padding: EdgeInsets.symmetric(horizontal: expand ? 8 : 12),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 14, color: selected ? AppColors.textWhite : AppColors.textMuted),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: selected ? FontWeight.bold : FontWeight.w500,
                  color: selected ? AppColors.textWhite : AppColors.textMuted,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLabeledField({required String label, required Widget child}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 11.5, color: AppColors.textDim),
        ),
        const SizedBox(height: 6),
        SizedBox(height: 34, child: child),
      ],
    );
  }

  /// Lưới đồng đều thẳng hàng theo số cột cố định với khoảng cách gọn gàng.
  Widget _buildAlignedGrid({
    required int columns,
    required double spacing,
    required List<Widget> children,
  }) {
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i += columns) {
      final rowItems = <Widget>[];
      for (var c = 0; c < columns; c++) {
        if (c > 0) rowItems.add(SizedBox(width: spacing));
        final idx = i + c;
        rowItems.add(
          Expanded(
            child: idx < children.length ? children[idx] : const SizedBox.shrink(),
          ),
        );
      }
      if (rows.isNotEmpty) rows.add(SizedBox(height: spacing));
      rows.add(Row(children: rowItems));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: rows,
    );
  }

  Widget _buildTabButton({
    required String id,
    required IconData icon,
    required String label,
    int badgeCount = 0,
    bool expand = false,
  }) {
    final isSelected = _selectedTab == id;
    return InkWell(
      borderRadius: BorderRadius.circular(4),
      onTap: () => setState(() => _selectedTab = id),
      child: Container(
        height: 32,
        padding: EdgeInsets.symmetric(horizontal: expand ? 8 : 12),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 14,
              color: isSelected ? AppColors.textWhite : AppColors.textMuted,
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                  color: isSelected ? AppColors.textWhite : AppColors.textMuted,
                ),
              ),
            ),
            if (badgeCount > 0) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: isSelected ? AppColors.bgDark.withValues(alpha: 0.35) : AppColors.primary.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '$badgeCount',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: isSelected ? AppColors.textWhite : AppColors.accentCyan,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildGoogleModelTile(String model) {
    final isSelected = _googleStudioModelCtrl.text.trim() == model;
    return InkWell(
      borderRadius: BorderRadius.circular(4),
      onTap: () => _applyGoogleModelPreset(model),
      child: Container(
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        alignment: Alignment.centerLeft,
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary.withValues(alpha: 0.22) : AppColors.inputBg,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: isSelected ? AppColors.primaryLight : AppColors.borderDark,
            width: isSelected ? 1.1 : 0.8,
          ),
        ),
        child: Row(
          children: [
            Icon(
              Icons.auto_awesome_rounded,
              size: 13,
              color: isSelected ? AppColors.accentCyan : AppColors.textDim,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                model,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                  color: isSelected ? AppColors.accentCyan : AppColors.textWhite,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPresetTile(String label, String url, String model) {
    final isSelected = _baseUrlCtrl.text.trim() == url && _modelCtrl.text.trim() == model;
    return InkWell(
      borderRadius: BorderRadius.circular(4),
      onTap: () => _applyPreset(label, url, model),
      child: Container(
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        alignment: Alignment.centerLeft,
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary.withValues(alpha: 0.22) : AppColors.inputBg,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: isSelected ? AppColors.primaryLight : AppColors.borderDark,
            width: isSelected ? 1.1 : 0.8,
          ),
        ),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
            color: isSelected ? AppColors.primaryLight : AppColors.textWhite,
          ),
        ),
      ),
    );
  }

  Widget _buildInfoBox(String title, String desc, {String? tooltip}) {
    return Container(
      height: 58,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.inputBg,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: AppColors.borderDark),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.textWhite),
          ),
          const SizedBox(height: 3),
          Tooltip(
            message: tooltip ?? desc,
            waitDuration: const Duration(milliseconds: 400),
            child: Text(
              desc,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
            ),
          ),
        ],
      ),
    );
  }
}
