import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/services/api_service.dart';
import '../../core/services/local_config_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_toast.dart';
import '../../providers/auth_provider.dart';
import '../../providers/server_provider.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final ApiService _api = ApiService();
  final TextEditingController _modelCtrl = TextEditingController(text: 'glm-5.3');
  final TextEditingController _baseUrlCtrl = TextEditingController(text: 'https://api.mitom.ai/v1');
  final TextEditingController _apiKeyCtrl = TextEditingController();

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
    super.dispose();
  }

  Future<void> _loadGlobalConfig() async {
    try {
      final cfg = await _api.getConfig();
      if (cfg['ai_model'] != null) _modelCtrl.text = cfg['ai_model'].toString();
      if (cfg['proxy_base_url'] != null) _baseUrlCtrl.text = cfg['proxy_base_url'].toString();
      if (cfg['proxy_api_key'] != null) _apiKeyCtrl.text = cfg['proxy_api_key'].toString();
    } catch (_) {}
  }

  Future<void> _saveAISettings() async {
    final rawBaseUrl = _baseUrlCtrl.text.trim();
    if (rawBaseUrl.isNotEmpty && !LocalConfigService.isValidMitomProxyUrl(rawBaseUrl)) {
      AppToast.error(context, 'Chỉ chấp nhận Proxy Base URL thuộc domain *.mitom.ai (Ví dụ: https://api.mitom.ai/v1)');
      return;
    }

    try {
      final cfg = await _api.getConfig();
      cfg['ai_model'] = _modelCtrl.text.trim();
      cfg['proxy_base_url'] = rawBaseUrl;
      cfg['proxy_api_key'] = _apiKeyCtrl.text.trim();
      final ok = await _api.saveConfig(cfg);
      if (mounted) {
        if (ok) {
          context.read<ServerProvider>().setGlobalAiModel(_modelCtrl.text.trim());
          AppToast.success(context, 'Đã lưu cấu hình AI thành công!');
        } else {
          AppToast.error(context, 'Lưu cấu hình AI thất bại!');
        }
      }
    } catch (e) {
      if (mounted) {
        AppToast.error(context, 'Lỗi: ');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final serverProvider = context.watch<ServerProvider>();
    final auth = context.watch<AuthProvider>();

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
                          'Cài Đặt Hệ Thống & Cấu Hình AI',
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.textWhite),
                        ),
                        Text(
                          'Cấu hình AI Model (${serverProvider.currentAiModel}) và Proxy API',
                          style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
                        ),
                      ],
                    ),
                  ],
                ),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
                  icon: const Icon(Icons.check_rounded, size: 16),
                  label: const Text('Lưu Thay Đổi', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
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
                  // GROUP 1: AI MODEL & PROXY CONFIGURATION
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: AppColors.cardBg,
                      borderRadius: BorderRadius.circular(8),
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
                                Icon(Icons.memory_rounded, size: 20, color: AppColors.primaryLight),
                                SizedBox(width: 10),
                                Text(
                                  '1. Cấu Hình AI Model & Proxy API',
                                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.textWhite),
                                ),
                              ],
                            ),
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.cardBg,
                                side: const BorderSide(color: AppColors.primary),
                              ),
                              icon: const Icon(Icons.save_rounded, size: 16, color: AppColors.primaryLight),
                              label: const Text('Lưu Cấu Hình AI', style: TextStyle(color: AppColors.primaryLight, fontSize: 12)),
                              onPressed: _saveAISettings,
                            ),
                          ],
                        ),
                        const Divider(height: 24),
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('AI Model Name', style: TextStyle(fontSize: 11, color: AppColors.textDim, fontWeight: FontWeight.w600)),
                                  const SizedBox(height: 6),
                                  TextField(
                                    controller: _modelCtrl,
                                    decoration: const InputDecoration(hintText: 'glm-5.3'),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('Proxy Base URL', style: TextStyle(fontSize: 11, color: AppColors.textDim, fontWeight: FontWeight.w600)),
                                  const SizedBox(height: 6),
                                  TextField(
                                    controller: _baseUrlCtrl,
                                    obscureText: true,
                                    decoration: const InputDecoration(hintText: 'https://api.mitom.ai/v1'),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        const Text('Proxy API Key', style: TextStyle(fontSize: 11, color: AppColors.textDim, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 6),
                        TextField(
                          controller: _apiKeyCtrl,
                          obscureText: true,
                          decoration: const InputDecoration(hintText: 'sk-... hoặc mitom key'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // GROUP 2: USER ACCOUNT & ENVIRONMENT
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: AppColors.cardBg,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.borderDark),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.person_rounded, size: 20, color: AppColors.primaryLight),
                            SizedBox(width: 10),
                            Text(
                              '2. Thông Tin Tài Khoản & Bản Quyền',
                              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.textWhite),
                            ),
                          ],
                        ),
                        const Divider(height: 24),
                        Row(
                          children: [
                            Expanded(
                              child: _buildInfoBox('Tài Khoản Đang Đăng Nhập', auth.userEmail ?? 'Chưa đăng nhập'),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _buildInfoBox('Hạn Mức Token', '50.000 Tokens (Sử dụng nội bộ)'),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _buildInfoBox('Trạng Thái Dịch Vụ', 'Hoạt động độc lập (Offline/Local)'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // GROUP 3: SECURITY & STORAGE INFO
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: AppColors.cardBg,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.borderDark),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.shield_rounded, size: 20, color: AppColors.accent),
                            SizedBox(width: 10),
                            Text(
                              '3. Bảo Mật & Thông Tin Hệ Thống',
                              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.textWhite),
                            ),
                          ],
                        ),
                        const Divider(height: 24),
                        Row(
                          children: [
                            Expanded(
                              child: _buildInfoBox('Chuẩn Mã Hoá', 'AES-256 GCM + HMAC-SHA256 lưu trữ an toàn trong config.json'),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _buildInfoBox('Cơ Sở Dữ Liệu', 'SQLite Cục Bộ (Lịch sử chat & Tài khoản an toàn)'),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _buildInfoBox('Nền Tảng Hỗ Trợ', 'Cross-platform (Linux / Windows / macOS / Web)'),
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

  Widget _buildInfoBox(String title, String desc) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.inputBg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.borderDark),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.textWhite)),
          const SizedBox(height: 4),
          Text(desc, style: const TextStyle(fontSize: 10, color: AppColors.textMuted)),
        ],
      ),
    );
  }
}
