import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/services/api_service.dart';
import '../../core/services/native_ai_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_toast.dart';
import '../../providers/server_provider.dart';
import '../logs/logs_dialog.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final ApiService _api = ApiService();
  final TextEditingController _modelCtrl = TextEditingController(text: 'glm-5.3');
  final TextEditingController _baseUrlCtrl = TextEditingController(text: 'https://openrouter.ai/api/v1');
  final TextEditingController _apiKeyCtrl = TextEditingController();
  final TextEditingController _promptCtrl = TextEditingController();

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
    super.dispose();
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

    return Scaffold(
      backgroundColor: AppColors.bgDark,
      body: Column(
        children: [
          // Topbar Header (Height 66px)
          Container(
            height: 66,
            padding: const EdgeInsets.symmetric(horizontal: 24),
            decoration: const BoxDecoration(
              color: AppColors.bgDark,
              border: Border(bottom: BorderSide(color: AppColors.borderDark, width: 1)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(Icons.tune_rounded, color: AppColors.primaryLight, size: 24),
                    const SizedBox(width: 12),
                    Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Cấu Hình AI Agent & Hệ Thống',
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.textWhite),
                        ),
                        Text(
                          'Thiết lập mô hình AI Model, API Key và môi trường hoạt động (${serverProvider.currentAiModel})',
                          style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
                        ),
                      ],
                    ),
                  ],
                ),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  ),
                  icon: const Icon(Icons.save_rounded, size: 16),
                  label: const Text('Lưu Cấu Hình', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  onPressed: _saveAISettings,
                ),
              ],
            ),
          ),

          // Scrollable Content
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // GROUP 1: AI MODEL & API CONFIGURATION
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: AppColors.cardBg,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: AppColors.borderDark),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Row(
                              children: [
                                Icon(Icons.memory_rounded, size: 18, color: AppColors.primaryLight),
                                SizedBox(width: 8),
                                Text(
                                  '1. Cấu Hình AI Model & Proxy API',
                                  style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                            Container(
                              padding: const EdgeInsets.all(3),
                              decoration: BoxDecoration(
                                color: AppColors.inputBg,
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: AppColors.borderDark),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  _buildTabButton(
                                    id: 'proxy',
                                    icon: Icons.hub_rounded,
                                    label: 'AI Model & Proxy',
                                  ),
                                  const SizedBox(width: 4),
                                  _buildTabButton(
                                    id: 'google_studio',
                                    icon: Icons.auto_awesome_rounded,
                                    label: 'API key Google Studio',
                                    badgeCount: _googleStudioKeys.length,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        if (_selectedTab == 'proxy') ...[
                          const Text(
                            'Chọn nhà cung cấp nhanh (Quick Presets):',
                            style: TextStyle(fontSize: 11, color: AppColors.textDim),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              _buildPresetChip('OpenRouter (GLM-5.3)', 'https://openrouter.ai/api/v1', 'glm-5.3'),
                              _buildPresetChip('OpenAI (GPT-4o)', 'https://api.openai.com/v1', 'gpt-4o'),
                              _buildPresetChip('DeepSeek', 'https://api.deepseek.com/v1', 'deepseek-chat'),
                              _buildPresetChip('Local Ollama', 'http://127.0.0.1:11434/v1', 'llama3.2:latest'),
                              _buildPresetChip('Zhipu GLM', 'https://open.bigmodel.cn/api/paas/v4', 'glm-4-flash'),
                            ],
                          ),
                          const Divider(height: 24),
                          Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text('Tên Model (AI Model Name)', style: TextStyle(fontSize: 11.5, color: AppColors.textDim)),
                                    const SizedBox(height: 6),
                                    TextField(
                                      controller: _modelCtrl,
                                      decoration: const InputDecoration(
                                        hintText: 'glm-5.3 hoặc gpt-4o hoặc deepseek-chat',
                                        prefixIcon: Icon(Icons.smart_toy_outlined, size: 18),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text('Địa Chỉ API (Base URL)', style: TextStyle(fontSize: 11.5, color: AppColors.textDim)),
                                    const SizedBox(height: 6),
                                    TextField(
                                      controller: _baseUrlCtrl,
                                      decoration: const InputDecoration(
                                        hintText: 'https://openrouter.ai/api/v1',
                                        prefixIcon: Icon(Icons.link_rounded, size: 18),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          const Text('API Key (Khoá xác thực bí mật)', style: TextStyle(fontSize: 11.5, color: AppColors.textDim)),
                          const SizedBox(height: 6),
                          TextField(
                            controller: _apiKeyCtrl,
                            obscureText: _obscureProxyKey,
                            decoration: InputDecoration(
                              hintText: 'sk-or-v1-... / sk-... (API Key)',
                              prefixIcon: const Icon(Icons.key_rounded, size: 18),
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
                          const SizedBox(height: 14),
                          const Text(
                            'Chọn nhanh Model Gemini (Google AI Studio):',
                            style: TextStyle(fontSize: 11, color: AppColors.textDim),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              _buildGoogleModelChip('gemini-2.5-flash'),
                              _buildGoogleModelChip('gemini-2.5-pro'),
                              _buildGoogleModelChip('gemini-2.5-flash-lite'),
                              _buildGoogleModelChip('gemini-2.0-flash'),
                            ],
                          ),
                          const SizedBox(height: 14),
                          Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text('Tên Model Gemini (Google AI Studio)', style: TextStyle(fontSize: 11.5, color: AppColors.textDim)),
                                    const SizedBox(height: 6),
                                    TextField(
                                      controller: _googleStudioModelCtrl,
                                      decoration: const InputDecoration(
                                        hintText: 'gemini-2.5-flash hoặc gemini-2.5-pro',
                                        prefixIcon: Icon(Icons.auto_awesome_outlined, size: 18),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text('Địa Chỉ API Google AI Studio', style: TextStyle(fontSize: 11.5, color: AppColors.textDim)),
                                    const SizedBox(height: 6),
                                    TextField(
                                      readOnly: true,
                                      controller: TextEditingController(text: 'https://generativelanguage.googleapis.com/v1beta/openai'),
                                      style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
                                      decoration: const InputDecoration(
                                        prefixIcon: Icon(Icons.cloud_done_rounded, size: 18, color: AppColors.accent),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'Thêm API Key Google Studio (Có thể dán 1 hoặc nhiều key cách nhau bởi dấu phẩy / khoảng trắng / xuống dòng):',
                            style: TextStyle(fontSize: 11.5, color: AppColors.textDim),
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Expanded(
                                child: SizedBox(
                                  height: 40,
                                  child: TextField(
                                    controller: _newGoogleKeyCtrl,
                                    onSubmitted: (_) => _addGoogleStudioKeysFromInput(),
                                    style: const TextStyle(fontSize: 12.5),
                                    decoration: const InputDecoration(
                                      hintText: 'AIzaSy... (1 hoặc nhiều API Key)',
                                      hintStyle: TextStyle(fontSize: 11.5),
                                      prefixIcon: Icon(Icons.vpn_key_rounded, size: 16),
                                      isDense: true,
                                      contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                      prefixIconConstraints: BoxConstraints(minWidth: 36),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.primaryLight,
                                  foregroundColor: AppColors.bgDark,
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 0),
                                  minimumSize: const Size(0, 40),
                                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                ),
                                icon: const Icon(Icons.add_circle_outline_rounded, size: 16),
                                label: const Text('Thêm Key', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                onPressed: _addGoogleStudioKeysFromInput,
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Danh sách API Key Google Studio đang hoạt động (${_googleStudioKeys.length} keys):',
                                style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: AppColors.textWhite),
                              ),
                              Row(
                                children: [
                                  if (_googleStudioKeys.isNotEmpty) ...[
                                    TextButton.icon(
                                      style: TextButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                        minimumSize: Size.zero,
                                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                      ),
                                      icon: Icon(
                                        _obscureGoogleKeys ? Icons.visibility_rounded : Icons.visibility_off_rounded,
                                        size: 14,
                                        color: AppColors.accentCyan,
                                      ),
                                      label: Text(
                                        _obscureGoogleKeys ? 'Hiện Key' : 'Ẩn Key',
                                        style: const TextStyle(fontSize: 11, color: AppColors.accentCyan),
                                      ),
                                      onPressed: () => setState(() => _obscureGoogleKeys = !_obscureGoogleKeys),
                                    ),
                                    const SizedBox(width: 8),
                                    TextButton.icon(
                                      style: TextButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                        minimumSize: Size.zero,
                                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                      ),
                                      icon: const Icon(Icons.delete_sweep_rounded, size: 14, color: Colors.redAccent),
                                      label: const Text('Xoá tất cả', style: TextStyle(fontSize: 11, color: Colors.redAccent)),
                                      onPressed: () => setState(() => _googleStudioKeys.clear()),
                                    ),
                                  ],
                                ],
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          if (_googleStudioKeys.isEmpty)
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
                              decoration: BoxDecoration(
                                color: AppColors.inputBg,
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: AppColors.borderDark),
                              ),
                              child: const Column(
                                children: [
                                  Icon(Icons.key_off_rounded, size: 24, color: AppColors.textMuted),
                                  SizedBox(height: 6),
                                  Text(
                                    'Chưa có API Key Google Studio nào. Hãy thêm 1 hoặc nhiều key miễn phí vào ô bên trên rồi bấm Lưu Cấu Hình.',
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
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Text(
                                            _maskApiKey(k),
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
                        const Divider(height: 24),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Custom Prompt & Yêu Cầu Thực Thi AI Model / CLI Agent',
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.textWhite),
                            ),
                            TextButton.icon(
                              style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
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
                          maxLines: 8,
                          style: const TextStyle(fontSize: 12, fontFamily: 'monospace', height: 1.45, color: AppColors.textWhite),
                          decoration: const InputDecoration(
                            hintText: 'Nhập custom prompt & yêu cầu dành cho AI Model...',
                            contentPadding: EdgeInsets.all(12),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // GROUP 2: SYSTEM ENVIRONMENT & STORAGE INFO
                  Container(
                    padding: const EdgeInsets.all(18),
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
                            Text(
                              '2. Môi Trường Thực Thi & Cơ Sở Dữ Liệu',
                              style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                        const Divider(height: 24),
                        Row(
                          children: [
                            Expanded(
                              child: _buildInfoBox(
                                'Hệ Điều Hành Local',
                                '${Platform.operatingSystem.toUpperCase()} (Linux 64-bit)',
                                tooltip: '${Platform.operatingSystem.toUpperCase()} (${Platform.operatingSystemVersion})',
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _buildInfoBox(
                                'Trình Thực Thi Shell',
                                Platform.environment['SHELL'] ?? (Platform.isWindows ? 'cmd.exe' : '/bin/bash'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _buildInfoBox(
                                'Chế Độ Hoạt Động',
                                'Local Machine & Quản trị Máy Chủ VPS',
                                tooltip: 'Thực thi lệnh trên Local Shell và Máy chủ từ xa qua SSH',
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: _buildInfoBox(
                                'Thư Mục Dữ Liệu Local',
                                Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '.',
                                tooltip: 'Đường dẫn thư mục Home người dùng hiện tại',
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _buildInfoBox(
                                'Bảo Mật Cơ Sở Dữ Liệu',
                                'SQLite Encrypted Storage (~/.ai_type_agent/)',
                                tooltip: 'Cơ sở dữ liệu SQLite mã hóa AES an toàn',
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _buildInfoBox(
                                'Phiên Bản Ứng Dụng',
                                'AI Type Desktop v1.3.0',
                                tooltip: 'Phiên bản Flutter Desktop Native Client',
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        const Divider(height: 20),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Column(
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
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.inputBg,
                                foregroundColor: AppColors.textWhite,
                                side: const BorderSide(color: AppColors.borderDark),
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
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
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabButton({
    required String id,
    required IconData icon,
    required String label,
    int badgeCount = 0,
  }) {
    final isSelected = _selectedTab == id;
    return InkWell(
      borderRadius: BorderRadius.circular(4),
      onTap: () => setState(() => _selectedTab = id),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 14,
              color: isSelected ? AppColors.textWhite : AppColors.textMuted,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                color: isSelected ? AppColors.textWhite : AppColors.textMuted,
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

  Widget _buildGoogleModelChip(String model) {
    final isSelected = _googleStudioModelCtrl.text.trim() == model;
    return ActionChip(
      backgroundColor: isSelected ? AppColors.primary.withValues(alpha: 0.25) : AppColors.inputBg,
      side: BorderSide(color: isSelected ? AppColors.primaryLight : AppColors.borderDark),
      label: Text(
        model,
        style: TextStyle(
          fontSize: 11,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          color: isSelected ? AppColors.accentCyan : AppColors.textWhite,
        ),
      ),
      onPressed: () => _applyGoogleModelPreset(model),
    );
  }

  Widget _buildPresetChip(String label, String url, String model) {
    return ActionChip(
      backgroundColor: AppColors.inputBg,
      side: const BorderSide(color: AppColors.borderDark),
      label: Text(label, style: const TextStyle(fontSize: 11, color: AppColors.textWhite)),
      onPressed: () => _applyPreset(label, url, model),
    );
  }

  Widget _buildInfoBox(String title, String desc, {String? tooltip}) {
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
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
          const SizedBox(height: 4),
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
