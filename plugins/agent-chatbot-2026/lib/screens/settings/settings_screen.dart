import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import '../../core/services/api_service.dart';
import '../../core/services/local_config_service.dart';
import '../../core/services/storage_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_logo_widget.dart';
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
  final TextEditingController _logoCtrl = TextEditingController();

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
    _logoCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadGlobalConfig() async {
    try {
      final savedLogo = await StorageService().getCustomLogoPath();
      if (savedLogo != null && savedLogo.isNotEmpty) {
        _logoCtrl.text = savedLogo;
      }
      final cfg = await _api.getConfig();
      if (cfg['ai_model'] != null) _modelCtrl.text = cfg['ai_model'].toString();
      if (cfg['proxy_base_url'] != null) _baseUrlCtrl.text = cfg['proxy_base_url'].toString();
      if (cfg['proxy_api_key'] != null) _apiKeyCtrl.text = cfg['proxy_api_key'].toString();
      if (cfg['custom_logo_path'] != null && cfg['custom_logo_path'].toString().isNotEmpty) {
        _logoCtrl.text = cfg['custom_logo_path'].toString();
      }
    } catch (_) {}
  }

  Future<void> _pickLogoFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['jpg', 'jpeg', 'png', 'webp', 'svg'],
        allowMultiple: false,
        withData: true,
      );

      if (result != null && result.files.isNotEmpty) {
        final picked = result.files.first;
        String? targetPath;

        // Lưu bản sao logo vào thư mục dữ liệu cục bộ của app để không phụ thuộc file gốc
        final appDataDir = p.join(Platform.environment['HOME'] ?? '', '.agent_chatbot_2026', 'branding');
        final targetDir = Directory(appDataDir);
        if (!targetDir.existsSync()) {
          targetDir.createSync(recursive: true);
        }

        final ext = p.extension(picked.name).isNotEmpty ? p.extension(picked.name) : '.png';
        final savedFile = File(p.join(appDataDir, 'app_logo$ext'));

        if (picked.bytes != null && picked.bytes!.isNotEmpty) {
          await savedFile.writeAsBytes(picked.bytes!, flush: true);
          targetPath = savedFile.path;
        } else if (picked.path != null && picked.path!.isNotEmpty) {
          final srcFile = File(picked.path!);
          if (await srcFile.exists()) {
            await srcFile.copy(savedFile.path);
            targetPath = savedFile.path;
          } else {
            targetPath = picked.path;
          }
        }

        if (targetPath != null && targetPath.isNotEmpty) {
          setState(() {
            _logoCtrl.text = targetPath!;
          });
          await _saveLogoSetting(targetPath);
        }
      }
    } catch (e) {
      if (mounted) {
        AppToast.error(context, 'Lỗi tải ảnh logo: $e');
      }
    }
  }

  Future<void> _resetLogo() async {
    setState(() {
      _logoCtrl.clear();
    });
    await _saveLogoSetting('');
    if (mounted) {
      AppToast.info(context, 'Đã khôi phục logo mặc định của ứng dụng');
    }
  }

  Future<void> _saveLogoSetting(String path) async {
    try {
      final trimmed = path.trim();
      await StorageService().setCustomLogoPath(trimmed.isEmpty ? null : trimmed);
      if (mounted) {
        context.read<ServerProvider>().setCustomLogo(trimmed.isEmpty ? null : trimmed);
      }

      final cfg = await _api.getConfig();
      cfg['custom_logo_path'] = trimmed;
      await _api.saveConfig(cfg);

      if (mounted && trimmed.isNotEmpty) {
        AppToast.success(context, 'Đã tải lên và đổi Logo ứng dụng thành công!');
      }
    } catch (e) {
      if (mounted) {
        AppToast.error(context, 'Không thể lưu logo: $e');
      }
    }
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
      cfg['custom_logo_path'] = _logoCtrl.text.trim();
      final ok = await _api.saveConfig(cfg);
      if (mounted) {
        if (ok) {
          final serverProv = context.read<ServerProvider>();
          serverProv.setGlobalAiModel(_modelCtrl.text.trim());
          final logoPath = _logoCtrl.text.trim();
          await StorageService().setCustomLogoPath(logoPath.isEmpty ? null : logoPath);
          if (mounted) {
            serverProv.setCustomLogo(logoPath.isEmpty ? null : logoPath);
            AppToast.success(context, 'Đã lưu cấu hình hệ thống thành công!');
          }
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

                  // GROUP 2: LOGO & BRANDING CUSTOMIZATION
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
                            Icon(Icons.image_rounded, size: 20, color: AppColors.accentCyan),
                            SizedBox(width: 10),
                            Text(
                              '2. Nhận Diện Thương Hiệu (Logo Ứng Dụng)',
                              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.textWhite),
                            ),
                          ],
                        ),
                        const Divider(height: 24),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Logo Preview
                            Container(
                              width: 80,
                              height: 80,
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: AppColors.inputBg,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: AppColors.borderDark),
                              ),
                              child: const AppLogoWidget(
                                width: 72,
                                height: 72,
                                borderRadius: 6,
                              ),
                            ),
                            const SizedBox(width: 18),
                            // Description and Action
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Bấm nút "Tải Logo Lên" để chọn ảnh từ máy tính (PNG, JPG, WEBP, SVG). Logo mới sẽ được tự động đồng bộ ngay lập tức trên thanh Menu Sidebar, màn hình Đăng nhập, Avatar trợ lý AI và báo cáo PDF.',
                                    style: TextStyle(fontSize: 11.5, color: AppColors.textMuted, height: 1.5),
                                  ),
                                  const SizedBox(height: 12),
                                  Row(
                                    children: [
                                      ElevatedButton.icon(
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: AppColors.primary,
                                          foregroundColor: Colors.white,
                                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                                          elevation: 0,
                                        ),
                                        icon: const Icon(Icons.cloud_upload_rounded, size: 16),
                                        label: const Text('Tải Logo Lên', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                        onPressed: _pickLogoFile,
                                      ),
                                      if (serverProvider.customLogoPath != null && serverProvider.customLogoPath!.isNotEmpty) ...[
                                        const SizedBox(width: 10),
                                        OutlinedButton.icon(
                                          style: OutlinedButton.styleFrom(
                                            foregroundColor: AppColors.textMuted,
                                            side: const BorderSide(color: AppColors.borderDark),
                                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                                          ),
                                          icon: const Icon(Icons.restart_alt_rounded, size: 15),
                                          label: const Text('Khôi phục mặc định', style: TextStyle(fontSize: 12)),
                                          onPressed: _resetLogo,
                                        ),
                                      ],
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // GROUP 3: USER ACCOUNT & ENVIRONMENT
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
                              '3. Thông Tin Tài Khoản & Bản Quyền',
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

                  // GROUP 4: SECURITY & STORAGE INFO
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
                              '4. Bảo Mật & Thông Tin Hệ Thống',
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
