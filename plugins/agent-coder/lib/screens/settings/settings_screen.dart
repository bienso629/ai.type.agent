import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/services/api_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_toast.dart';
import '../../providers/server_provider.dart';

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
      final m = cfg['ai_model']?.toString() ?? 'glm-5.3';
      _modelCtrl.text = (m.contains('cli') || m == 'agy' || m == 'claude') ? 'glm-5.3' : m;
      if (cfg['proxy_base_url'] != null) _baseUrlCtrl.text = cfg['proxy_base_url'].toString();
      if (cfg['proxy_api_key'] != null) _apiKeyCtrl.text = cfg['proxy_api_key'].toString();
    } catch (_) {}
  }

  Future<void> _saveAISettings() async {
    try {
      final ok = await _api.saveConfig({
        'ai_model': _modelCtrl.text.trim(),
        'proxy_base_url': _baseUrlCtrl.text.trim(),
        'proxy_api_key': _apiKeyCtrl.text.trim(),
      });
      if (mounted) {
        if (ok) {
          final serverProvider = context.read<ServerProvider>();
          serverProvider.setCloudAiModel(_modelCtrl.text.trim());
          serverProvider.fetchModels(
            forceRefresh: true,
            customBaseUrl: _baseUrlCtrl.text.trim(),
            customApiKey: _apiKeyCtrl.text.trim(),
          );
          AppToast.success(context, 'Đã lưu cấu hình AI Model & API thành công!');
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
                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
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
                        const SizedBox(height: 12),
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
                          obscureText: true,
                          decoration: const InputDecoration(
                            hintText: 'sk-or-v1-... / sk-... (API Key)',
                            prefixIcon: Icon(Icons.key_rounded, size: 18),
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
