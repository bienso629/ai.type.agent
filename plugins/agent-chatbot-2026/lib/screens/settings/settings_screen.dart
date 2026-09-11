import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import '../../core/services/api_service.dart';
import '../../core/services/local_config_service.dart';
import '../../core/services/storage_service.dart';
import '../../core/services/tts_service.dart';
import '../../core/services/user_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_logo_widget.dart';
import '../../core/widgets/app_toast.dart';
import '../../core/widgets/tadu_dialog.dart';
import '../../providers/auth_provider.dart';
import '../../providers/server_provider.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final ApiService _api = ApiService();
  final TextEditingController _modelCtrl = TextEditingController(text: 'gemini-2.5-flash');
  final TextEditingController _baseUrlCtrl = TextEditingController(text: 'https://api-vn-sg.mitom.ai/v1');
  final TextEditingController _apiKeyCtrl = TextEditingController();
  final TextEditingController _logoCtrl = TextEditingController();
  final TextEditingController _appTitleCtrl = TextEditingController(text: 'AI Agent Chatbot');
  final TextEditingController _brandTitleCtrl = TextEditingController(text: 'AI Agent');
  final TextEditingController _brandSubtitleCtrl = TextEditingController(text: 'AI AGENT CHATBOT');

  bool _voiceEnabled = false;
  String _selectedVoice = 'vi-VN-HoaiMyNeural';
  bool _isTestingVoice = false;

  List<String> _availableModels = [];
  bool _isLoadingModels = false;

  @override
  void initState() {
    super.initState();
    _initSettings();
  }

  Future<void> _initSettings() async {
    await _loadGlobalConfig();
    if (mounted) {
      await _fetchModelsList();
    }
  }

  @override
  void dispose() {
    _modelCtrl.dispose();
    _baseUrlCtrl.dispose();
    _apiKeyCtrl.dispose();
    _logoCtrl.dispose();
    _appTitleCtrl.dispose();
    _brandTitleCtrl.dispose();
    _brandSubtitleCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadGlobalConfig() async {
    try {
      final tts = TtsService();
      await tts.init();
      if (mounted) {
        setState(() {
          _voiceEnabled = tts.isVoiceEnabled;
          _selectedVoice = tts.currentVoice;
        });
      }

      final savedLogo = await StorageService().getCustomLogoPath();
      if (savedLogo != null && savedLogo.isNotEmpty) {
        _logoCtrl.text = savedLogo;
      }
      final savedAppTitle = await StorageService().getAppTitle();
      if (savedAppTitle != null && savedAppTitle.isNotEmpty) {
        _appTitleCtrl.text = savedAppTitle;
      }
      final savedBrandTitle = await StorageService().getBrandTitle();
      if (savedBrandTitle != null && savedBrandTitle.isNotEmpty) {
        _brandTitleCtrl.text = savedBrandTitle;
      }
      final savedBrandSubtitle = await StorageService().getBrandSubtitle();
      if (savedBrandSubtitle != null && savedBrandSubtitle.isNotEmpty) {
        _brandSubtitleCtrl.text = savedBrandSubtitle;
      }
      final cfg = await _api.getConfig();
      if (cfg['ai_model'] != null) _modelCtrl.text = cfg['ai_model'].toString();
      if (cfg['proxy_base_url'] != null) _baseUrlCtrl.text = cfg['proxy_base_url'].toString();
      if (cfg['proxy_api_key'] != null) _apiKeyCtrl.text = cfg['proxy_api_key'].toString();
      if (cfg['custom_logo_path'] != null && cfg['custom_logo_path'].toString().isNotEmpty) {
        _logoCtrl.text = cfg['custom_logo_path'].toString();
      }
      if (cfg['app_title'] != null && cfg['app_title'].toString().isNotEmpty) {
        _appTitleCtrl.text = cfg['app_title'].toString();
      }
      if (cfg['brand_title'] != null && cfg['brand_title'].toString().isNotEmpty) {
        _brandTitleCtrl.text = cfg['brand_title'].toString();
      }
      if (cfg['brand_subtitle'] != null && cfg['brand_subtitle'].toString().isNotEmpty) {
        _brandSubtitleCtrl.text = cfg['brand_subtitle'].toString();
      }
    } catch (_) {}
  }

  Future<void> _fetchModelsList({bool forceRefresh = false}) async {
    if (_isLoadingModels) return;
    setState(() {
      _isLoadingModels = true;
    });

    try {
      final baseUrl = _baseUrlCtrl.text.trim();
      final apiKey = _apiKeyCtrl.text.trim();
      final models = await _api.fetchAvailableModels(
        customBaseUrl: baseUrl.isNotEmpty ? baseUrl : null,
        apiKey: apiKey.isNotEmpty ? apiKey : null,
      );

      if (mounted) {
        setState(() {
          if (models.isNotEmpty) {
            _availableModels = models;
          }
          // Nếu model hiện tại chưa nằm trong danh sách, thêm vào đầu
          final current = _modelCtrl.text.trim();
          if (current.isNotEmpty && !_availableModels.contains(current)) {
            _availableModels.insert(0, current);
          }
          _isLoadingModels = false;
        });

        if (forceRefresh && models.isNotEmpty) {
          AppToast.success(context, 'Đã cập nhật ${models.length} model từ API!');
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingModels = false;
        });
        if (forceRefresh) {
          AppToast.error(context, 'Không thể tải danh sách model: $e');
        }
      }
    }
  }

  void _openModelSelectorDialog() {
    final searchCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            final query = searchCtrl.text.trim().toLowerCase();
            final filtered = _availableModels.where((m) {
              if (query.isEmpty) return true;
              return m.toLowerCase().contains(query);
            }).toList();

            return TaduDialog(
              minWidth: 480,
              maxWidth: 580,
              maxHeight: 620,
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Icon(Icons.psychology_rounded, size: 18, color: AppColors.primaryLight),
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Chọn AI Model', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.textWhite)),
                        SizedBox(height: 2),
                        Text('Danh sách đồng bộ thời gian thực từ API', style: TextStyle(fontSize: 11, color: AppColors.textMuted, fontWeight: FontWeight.normal)),
                      ],
                    ),
                  ),
                  if (_isLoadingModels)
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primaryLight),
                    )
                  else
                    IconButton(
                      icon: const Icon(Icons.refresh_rounded, size: 18, color: AppColors.accentCyan),
                      tooltip: 'Làm mới danh sách model',
                      onPressed: () async {
                        await _fetchModelsList(forceRefresh: true);
                        setModalState(() {});
                      },
                    ),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: searchCtrl,
                    autofocus: false,
                    onChanged: (_) => setModalState(() {}),
                    style: const TextStyle(fontSize: 13, color: AppColors.textWhite),
                    decoration: InputDecoration(
                      hintText: 'Tìm kiếm model (vd: deepseek, glm, qwen...)...',
                      prefixIcon: const Icon(Icons.search_rounded, size: 18, color: AppColors.textDim),
                      suffixIcon: searchCtrl.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear_rounded, size: 16, color: AppColors.textDim),
                              onPressed: () {
                                searchCtrl.clear();
                                setModalState(() {});
                              },
                            )
                          : null,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Tổng số: ${filtered.length} model khả dụng',
                        style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
                      ),
                      if (_modelCtrl.text.trim().isNotEmpty)
                        Text(
                          'Đang dùng: ${_modelCtrl.text.trim()}',
                          style: const TextStyle(fontSize: 11, color: AppColors.primaryLight, fontWeight: FontWeight.bold),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 360,
                    child: filtered.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.search_off_rounded, size: 36, color: AppColors.textDim),
                                const SizedBox(height: 8),
                                Text(
                                  query.isNotEmpty ? 'Không tìm thấy model nào khớp với "$query"' : 'Chưa có danh sách model',
                                  style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
                                ),
                                if (query.isNotEmpty) ...[
                                  const SizedBox(height: 12),
                                  ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppColors.primary,
                                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                    ),
                                    icon: const Icon(Icons.check_rounded, size: 14, color: Colors.white),
                                    label: Text('Dùng model "$query"', style: const TextStyle(fontSize: 12, color: Colors.white)),
                                    onPressed: () {
                                      setState(() {
                                        _modelCtrl.text = query;
                                        if (!_availableModels.contains(query)) {
                                          _availableModels.insert(0, query);
                                        }
                                      });
                                      Navigator.pop(dialogCtx);
                                      AppToast.success(context, 'Đã chọn: $query');
                                    },
                                  ),
                                ],
                              ],
                            ),
                          )
                        : ListView.separated(
                            itemCount: filtered.length,
                            separatorBuilder: (_, _) => const SizedBox(height: 4),
                            itemBuilder: (context, idx) {
                              final m = filtered[idx];
                              final isSelected = _modelCtrl.text.trim().toLowerCase() == m.toLowerCase();

                              IconData icon = Icons.psychology_outlined;
                              Color iconColor = AppColors.primaryLight;
                              if (m.contains('deepseek')) {
                                icon = Icons.terminal_rounded;
                                iconColor = AppColors.accentCyan;
                              } else if (m.contains('glm')) {
                                icon = Icons.auto_awesome_rounded;
                                iconColor = Colors.amber;
                              } else if (m.contains('qwen')) {
                                icon = Icons.smart_toy_outlined;
                                iconColor = Colors.tealAccent;
                              } else if (m.contains('doubao') || m.contains('seed')) {
                                icon = Icons.bolt_rounded;
                                iconColor = Colors.orangeAccent;
                              } else if (m.contains('minimax') || m.contains('MiniMax')) {
                                icon = Icons.view_in_ar_rounded;
                                iconColor = Colors.purpleAccent;
                              } else if (m.contains('wan') || m.contains('image') || m.contains('video')) {
                                icon = Icons.video_collection_outlined;
                                iconColor = Colors.pinkAccent;
                              }

                              return InkWell(
                                borderRadius: BorderRadius.circular(6),
                                onTap: () {
                                  setState(() {
                                    _modelCtrl.text = m;
                                  });
                                  Navigator.pop(dialogCtx);
                                  AppToast.success(context, 'Đã chọn model: $m');
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                  decoration: BoxDecoration(
                                    color: isSelected ? AppColors.primary.withValues(alpha: 0.15) : AppColors.inputBg,
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(
                                      color: isSelected ? AppColors.primaryLight : AppColors.borderDark,
                                      width: isSelected ? 1.5 : 1,
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(6),
                                        decoration: BoxDecoration(
                                          color: iconColor.withValues(alpha: 0.15),
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Icon(icon, size: 16, color: iconColor),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          m,
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                            color: isSelected ? AppColors.primaryLight : AppColors.textWhite,
                                          ),
                                        ),
                                      ),
                                      if (isSelected)
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: AppColors.primary,
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: const Text('ĐANG CHỌN', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.white)),
                                        )
                                      else
                                        const Icon(Icons.arrow_forward_ios_rounded, size: 12, color: AppColors.textDim),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogCtx),
                  child: const Text('Hủy', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _toggleVoiceEnabled(bool val) async {
    setState(() {
      _voiceEnabled = val;
    });
    await TtsService().setVoiceEnabled(val);
    if (mounted) {
      if (val) {
        AppToast.success(context, 'Đã bật tính năng đọc voice tự động cho AI');
      } else {
        AppToast.info(context, 'Đã tắt tính năng phát giọng nói');
      }
    }
  }

  Future<void> _changeVoice(String voice) async {
    setState(() {
      _selectedVoice = voice;
    });
    await TtsService().setVoice(voice);
  }

  Future<void> _testVoicePlayback() async {
    if (_isTestingVoice) {
      await TtsService().stop();
      if (mounted) {
        setState(() {
          _isTestingVoice = false;
        });
      }
      return;
    }

    setState(() {
      _isTestingVoice = true;
    });

    final sampleText = _selectedVoice.contains('NamMinh')
        ? 'Xin chào bạn, tôi là trợ lý Nam Minh. Giọng đọc tiếng Việt đã sẵn sàng phục vụ bạn.'
        : 'Xin chào bạn, tôi là trợ lý Hoài My. Giọng đọc tiếng Việt đã sẵn sàng phục vụ bạn.';

    final ok = await TtsService().speak(sampleText, ignoreEnabledCheck: true, wait: true);
    if (mounted) {
      setState(() {
        _isTestingVoice = false;
      });
      if (!ok) {
        AppToast.error(context, 'Không thể phát âm thanh. Vui lòng kiểm tra lại dịch vụ edge-tts hoặc kết nối mạng.');
      }
    }
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

  Future<void> _saveBrandTitles() async {
    try {
      final appTitle = _appTitleCtrl.text.trim().isEmpty ? 'AI Agent Chatbot' : _appTitleCtrl.text.trim();
      final brandTitle = _brandTitleCtrl.text.trim().isEmpty ? 'AI Agent' : _brandTitleCtrl.text.trim();
      final brandSubtitle = _brandSubtitleCtrl.text.trim().isEmpty ? 'AI AGENT CHATBOT' : _brandSubtitleCtrl.text.trim();

      final serverProv = context.read<ServerProvider>();
      await serverProv.setAppTitle(appTitle);
      await serverProv.setBrandTitle(brandTitle);
      await serverProv.setBrandSubtitle(brandSubtitle);

      final cfg = await _api.getConfig();
      cfg['app_title'] = appTitle;
      cfg['brand_title'] = brandTitle;
      cfg['brand_subtitle'] = brandSubtitle;
      await _api.saveConfig(cfg);

      if (mounted) {
        AppToast.success(context, 'Đã cập nhật tiêu đề thương hiệu thành công!');
      }
    } catch (e) {
      if (mounted) {
        AppToast.error(context, 'Không thể lưu tiêu đề: $e');
      }
    }
  }

  Future<void> _resetBrandTitles() async {
    setState(() {
      _appTitleCtrl.text = 'AI Agent Chatbot';
      _brandTitleCtrl.text = 'AI Agent';
      _brandSubtitleCtrl.text = 'AI AGENT CHATBOT';
    });
    await _saveBrandTitles();
    if (mounted) {
      AppToast.info(context, 'Đã khôi phục tiêu đề mặc định');
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
      cfg['app_title'] = _appTitleCtrl.text.trim().isEmpty ? 'AI Agent Chatbot' : _appTitleCtrl.text.trim();
      cfg['brand_title'] = _brandTitleCtrl.text.trim().isEmpty ? 'AI Agent' : _brandTitleCtrl.text.trim();
      cfg['brand_subtitle'] = _brandSubtitleCtrl.text.trim().isEmpty ? 'AI AGENT CHATBOT' : _brandSubtitleCtrl.text.trim();

      final ok = await _api.saveConfig(cfg);
      if (mounted) {
        if (ok) {
          final serverProv = context.read<ServerProvider>();
          serverProv.setGlobalAiModel(_modelCtrl.text.trim());
          final logoPath = _logoCtrl.text.trim();
          await StorageService().setCustomLogoPath(logoPath.isEmpty ? null : logoPath);
          await serverProv.setAppTitle(cfg['app_title']);
          await serverProv.setBrandTitle(cfg['brand_title']);
          await serverProv.setBrandSubtitle(cfg['brand_subtitle']);
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

  void _showChangePasswordDialog(String? userEmail) {
    if (userEmail == null || userEmail.isEmpty) {
      AppToast.error(context, 'Bạn chưa đăng nhập');
      return;
    }

    final currentPassCtrl = TextEditingController();
    final newPassCtrl = TextEditingController();
    final confirmPassCtrl = TextEditingController();
    bool obscureCurrent = true;
    bool obscureNew = true;
    bool obscureConfirm = true;
    bool isSubmitting = false;
    String? dialogError;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              backgroundColor: AppColors.cardBg,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: const BorderSide(color: AppColors.borderDark),
              ),
              title: const Row(
                children: [
                  Icon(Icons.lock_reset_rounded, color: AppColors.primaryLight, size: 22),
                  SizedBox(width: 10),
                  Text(
                    'Đổi Mật Khẩu Tài Khoản',
                    style: TextStyle(color: AppColors.textWhite, fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              content: SizedBox(
                width: 420,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Tài khoản: $userEmail',
                        style: const TextStyle(fontSize: 13, color: AppColors.primaryLight, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 16),
                      if (dialogError != null) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          margin: const EdgeInsets.only(bottom: 14),
                          decoration: BoxDecoration(
                            color: AppColors.danger.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: AppColors.danger.withValues(alpha: 0.4)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.error_outline_rounded, color: AppColors.danger, size: 18),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  dialogError!,
                                  style: const TextStyle(color: AppColors.danger, fontSize: 13),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      const Text('Mật khẩu hiện tại', style: TextStyle(fontSize: 13, color: AppColors.textBody, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 6),
                      TextField(
                        controller: currentPassCtrl,
                        obscureText: obscureCurrent,
                        style: const TextStyle(fontSize: 14, color: AppColors.textWhite),
                        decoration: InputDecoration(
                          hintText: 'Nhập mật khẩu hiện tại...',
                          suffixIcon: IconButton(
                            icon: Icon(
                              obscureCurrent ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                              size: 20,
                              color: AppColors.textDim,
                            ),
                            onPressed: () => setDialogState(() => obscureCurrent = !obscureCurrent),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      const Text('Mật khẩu mới', style: TextStyle(fontSize: 13, color: AppColors.textBody, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 6),
                      TextField(
                        controller: newPassCtrl,
                        obscureText: obscureNew,
                        style: const TextStyle(fontSize: 14, color: AppColors.textWhite),
                        decoration: InputDecoration(
                          hintText: 'Tối thiểu 6 ký tự...',
                          suffixIcon: IconButton(
                            icon: Icon(
                              obscureNew ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                              size: 20,
                              color: AppColors.textDim,
                            ),
                            onPressed: () => setDialogState(() => obscureNew = !obscureNew),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      const Text('Xác nhận mật khẩu mới', style: TextStyle(fontSize: 13, color: AppColors.textBody, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 6),
                      TextField(
                        controller: confirmPassCtrl,
                        obscureText: obscureConfirm,
                        style: const TextStyle(fontSize: 14, color: AppColors.textWhite),
                        decoration: InputDecoration(
                          hintText: 'Nhập lại mật khẩu mới...',
                          suffixIcon: IconButton(
                            icon: Icon(
                              obscureConfirm ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                              size: 20,
                              color: AppColors.textDim,
                            ),
                            onPressed: () => setDialogState(() => obscureConfirm = !obscureConfirm),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSubmitting ? null : () => Navigator.pop(dialogCtx),
                  child: const Text('Huỷ Bỏ', style: TextStyle(color: AppColors.textDim, fontSize: 13)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  ),
                  onPressed: isSubmitting
                      ? null
                      : () async {
                          final curPass = currentPassCtrl.text;
                          final newPass = newPassCtrl.text;
                          final confirmPass = confirmPassCtrl.text;

                          if (curPass.isEmpty || newPass.isEmpty || confirmPass.isEmpty) {
                            setDialogState(() => dialogError = 'Vui lòng nhập đầy đủ các thông tin mật khẩu');
                            return;
                          }
                          if (newPass.length < 6) {
                            setDialogState(() => dialogError = 'Mật khẩu mới phải có tối thiểu 6 ký tự');
                            return;
                          }
                          if (newPass != confirmPass) {
                            setDialogState(() => dialogError = 'Mật khẩu xác nhận không khớp');
                            return;
                          }
                          if (newPass == curPass) {
                            setDialogState(() => dialogError = 'Mật khẩu mới phải khác mật khẩu hiện tại');
                            return;
                          }

                          setDialogState(() {
                            isSubmitting = true;
                            dialogError = null;
                          });

                          try {
                            await UserService().changePassword(
                               email: userEmail,
                              currentPassword: curPass,
                              newPassword: newPass,
                            );

                            if (dialogCtx.mounted) {
                              Navigator.pop(dialogCtx);
                            }
                            if (mounted) {
                              AppToast.success(context, 'Đổi mật khẩu tài khoản thành công!');
                            }
                          } catch (err) {
                            final msg = err.toString().replaceFirst('Exception: ', '');
                            setDialogState(() {
                              isSubmitting = false;
                              dialogError = msg;
                            });
                          }
                        },
                  child: isSubmitting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Cập Nhật Mật Khẩu', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                ),
              ],
            );
          },
        );
      },
    );
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
                                  Row(
                                    children: [
                                      const Text('AI Model Name', style: TextStyle(fontSize: 13, color: AppColors.textBody, fontWeight: FontWeight.w600)),
                                      const Spacer(),
                                      if (_isLoadingModels)
                                        const SizedBox(
                                          width: 14,
                                          height: 14,
                                          child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primaryLight),
                                        )
                                      else
                                        InkWell(
                                          onTap: () => _fetchModelsList(forceRefresh: true),
                                          child: const Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(Icons.refresh_rounded, size: 13, color: AppColors.accentCyan),
                                              SizedBox(width: 4),
                                              Text('Cập nhật API', style: TextStyle(fontSize: 11, color: AppColors.accentCyan, fontWeight: FontWeight.w500)),
                                            ],
                                          ),
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  InkWell(
                                    borderRadius: BorderRadius.circular(6),
                                    onTap: _openModelSelectorDialog,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                                      decoration: BoxDecoration(
                                        color: AppColors.inputBg,
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(color: AppColors.borderDark),
                                      ),
                                      child: Row(
                                        children: [
                                          const Icon(Icons.psychology_rounded, size: 18, color: AppColors.primaryLight),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: Text(
                                              _modelCtrl.text.trim().isEmpty ? 'Chọn AI Model...' : _modelCtrl.text.trim(),
                                              style: TextStyle(
                                                fontSize: 13.5,
                                                fontWeight: FontWeight.w600,
                                                color: _modelCtrl.text.trim().isEmpty ? AppColors.textDim : AppColors.textWhite,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                          if (_availableModels.isNotEmpty)
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: AppColors.primary.withValues(alpha: 0.2),
                                                borderRadius: BorderRadius.circular(4),
                                              ),
                                              child: Text(
                                                '${_availableModels.length}',
                                                style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.primaryLight),
                                              ),
                                            ),
                                          const SizedBox(width: 6),
                                          const Icon(Icons.keyboard_arrow_down_rounded, size: 20, color: AppColors.textMuted),
                                        ],
                                      ),
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
                                  const Text('Proxy Base URL', style: TextStyle(fontSize: 13, color: AppColors.textBody, fontWeight: FontWeight.w600)),
                                  const SizedBox(height: 6),
                                  TextField(
                                    controller: _baseUrlCtrl,
                                    obscureText: true,
                                    style: const TextStyle(fontSize: 14, color: AppColors.textWhite),
                                    decoration: const InputDecoration(hintText: 'https://api.mitom.ai/v1'),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        const Text('Proxy API Key', style: TextStyle(fontSize: 13, color: AppColors.textBody, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 6),
                        TextField(
                          controller: _apiKeyCtrl,
                          obscureText: true,
                          style: const TextStyle(fontSize: 14, color: AppColors.textWhite),
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
                                  if (auth.isAdmin)
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
                                    )
                                   else
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                      decoration: BoxDecoration(
                                        color: AppColors.warning.withValues(alpha: 0.1),
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(color: AppColors.warning.withValues(alpha: 0.3)),
                                      ),
                                      child: const Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(Icons.lock_rounded, size: 14, color: AppColors.warning),
                                          SizedBox(width: 6),
                                          Text(
                                            'Chỉ Admin đầu tiên mới có quyền thay đổi logo thương hiệu.',
                                            style: TextStyle(fontSize: 11.5, color: AppColors.warning),
                                          ),
                                        ],
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        const Divider(height: 1),
                        const SizedBox(height: 16),
                        // Sub-section: Text Branding Titles
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Tiêu Đề Thương Hiệu & Tên Hiển Thị Ứng Dụng',
                              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: AppColors.textWhite),
                            ),
                            if (auth.isAdmin)
                              Row(
                                children: [
                                  OutlinedButton.icon(
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: AppColors.textMuted,
                                      side: const BorderSide(color: AppColors.borderDark),
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                                    ),
                                    icon: const Icon(Icons.restart_alt_rounded, size: 14),
                                    label: const Text('Mặc định', style: TextStyle(fontSize: 11)),
                                    onPressed: _resetBrandTitles,
                                  ),
                                  const SizedBox(width: 8),
                                  ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppColors.primary,
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                                      elevation: 0,
                                    ),
                                    icon: const Icon(Icons.save_rounded, size: 14),
                                    label: const Text('Lưu Tiêu Đề', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                                    onPressed: _saveBrandTitles,
                                  ),
                                ],
                              ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              flex: 3,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('Tiêu đề chính Menu ("AI Agent")', style: TextStyle(fontSize: 13, color: AppColors.textBody, fontWeight: FontWeight.w600)),
                                  const SizedBox(height: 6),
                                  TextField(
                                    controller: _brandTitleCtrl,
                                    enabled: auth.isAdmin,
                                    style: const TextStyle(fontSize: 14, color: AppColors.textWhite),
                                    decoration: InputDecoration(
                                      hintText: 'AI Agent',
                                      filled: true,
                                      fillColor: auth.isAdmin ? AppColors.inputBg : AppColors.cardBg,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              flex: 4,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('Phụ đề Menu ("AI AGENT CHATBOT")', style: TextStyle(fontSize: 13, color: AppColors.textBody, fontWeight: FontWeight.w600)),
                                  const SizedBox(height: 6),
                                  TextField(
                                    controller: _brandSubtitleCtrl,
                                    enabled: auth.isAdmin,
                                    style: const TextStyle(fontSize: 14, color: AppColors.textWhite),
                                    decoration: InputDecoration(
                                      hintText: 'AI AGENT CHATBOT',
                                      filled: true,
                                      fillColor: auth.isAdmin ? AppColors.inputBg : AppColors.cardBg,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              flex: 4,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('Tiêu đề cửa sổ ứng dụng (Title)', style: TextStyle(fontSize: 13, color: AppColors.textBody, fontWeight: FontWeight.w600)),
                                  const SizedBox(height: 6),
                                  TextField(
                                    controller: _appTitleCtrl,
                                    enabled: auth.isAdmin,
                                    style: const TextStyle(fontSize: 14, color: AppColors.textWhite),
                                    decoration: InputDecoration(
                                      hintText: 'AI Agent Chatbot',
                                      filled: true,
                                      fillColor: auth.isAdmin ? AppColors.inputBg : AppColors.cardBg,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        if (!auth.isAdmin) ...[
                          const SizedBox(height: 10),
                          const Row(
                            children: [
                              Icon(Icons.lock_rounded, size: 13, color: AppColors.warning),
                              SizedBox(width: 6),
                              Text(
                                'Chỉ Admin đầu tiên mới có quyền đổi các tiêu đề thương hiệu này.',
                                style: TextStyle(fontSize: 11, color: AppColors.warning),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // GROUP 3: EDGE TTS VOICE CONFIGURATION (MỞ CHO TẤT CẢ NGƯỜI DÙNG)
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
                                Icon(Icons.record_voice_over_rounded, size: 20, color: AppColors.accent),
                                SizedBox(width: 10),
                                Text(
                                  '3. Tự động đọc',
                                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.textWhite),
                                ),
                              ],
                            ),
                            Switch(
                              value: _voiceEnabled,
                              onChanged: _toggleVoiceEnabled,
                              activeThumbColor: Colors.white,
                              activeTrackColor: AppColors.accent,
                              inactiveThumbColor: AppColors.textDim,
                              inactiveTrackColor: AppColors.borderDark,
                              trackOutlineColor: WidgetStateProperty.resolveWith<Color?>(
                                (states) => states.contains(WidgetState.selected)
                                    ? AppColors.accent.withValues(alpha: 0.5)
                                    : AppColors.borderLight,
                              ),
                            ),
                          ],
                        ),
                        const Divider(height: 24),
                        const Text(
                          'Tự động đọc câu trả lời của AI theo thời gian thực (bắn chữ đến đâu đọc ngay đến đó) bằng giọng trí tuệ nhân tạo Tiếng Việt chuẩn.',
                          style: TextStyle(fontSize: 11.5, color: AppColors.textMuted, height: 1.5),
                        ),
                        if (_voiceEnabled) ...[
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Container(
                                height: 38,
                                padding: const EdgeInsets.symmetric(horizontal: 10),
                                decoration: BoxDecoration(
                                  color: AppColors.inputBg,
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: AppColors.borderDark),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.mic_none_rounded, size: 16, color: AppColors.primaryLight),
                                    const SizedBox(width: 8),
                                    const Text(
                                      'Giọng đọc:',
                                      style: TextStyle(fontSize: 12, color: AppColors.textMuted, fontWeight: FontWeight.w600),
                                    ),
                                    const SizedBox(width: 8),
                                    DropdownButtonHideUnderline(
                                      child: DropdownButton<String>(
                                        value: _selectedVoice,
                                        dropdownColor: AppColors.cardBg,
                                        style: const TextStyle(fontSize: 12, color: AppColors.textWhite),
                                        items: const [
                                          DropdownMenuItem(
                                            value: 'vi-VN-HoaiMyNeural',
                                            child: Text('Hoài My (Nữ)', style: TextStyle(fontSize: 12, color: AppColors.textWhite)),
                                          ),
                                          DropdownMenuItem(
                                            value: 'vi-VN-NamMinhNeural',
                                            child: Text('Nam Minh (Nam)', style: TextStyle(fontSize: 12, color: AppColors.textWhite)),
                                          ),
                                        ],
                                        onChanged: (val) {
                                          if (val != null) {
                                            _changeVoice(val);
                                          }
                                        },
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 12),
                              SizedBox(
                                height: 38,
                                child: ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: _isTestingVoice ? Colors.amber.shade800 : AppColors.primaryLight,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(horizontal: 14),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                                    elevation: 0,
                                  ),
                                  icon: Icon(_isTestingVoice ? Icons.stop_rounded : Icons.volume_up_rounded, size: 16),
                                  label: Text(
                                    _isTestingVoice ? 'Dừng phát' : 'Nghe thử giọng đọc',
                                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                                  ),
                                  onPressed: _testVoicePlayback,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // GROUP 4: USER ACCOUNT & ENVIRONMENT
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
                                Icon(Icons.person_rounded, size: 20, color: AppColors.primaryLight),
                                SizedBox(width: 10),
                                Text(
                                  '4. Thông Tin Tài Khoản & Bản Quyền',
                                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.textWhite),
                                ),
                              ],
                            ),
                            if (auth.isAuthenticated && auth.userEmail != null && auth.userEmail != 'local.admin@agent.chatbot')
                              ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.cardBg,
                                  side: const BorderSide(color: AppColors.primaryLight),
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                ),
                                icon: const Icon(Icons.lock_reset_rounded, size: 16, color: AppColors.primaryLight),
                                label: const Text(
                                  'Đổi Mật Khẩu',
                                  style: TextStyle(color: AppColors.primaryLight, fontSize: 12, fontWeight: FontWeight.w600),
                                ),
                                onPressed: () => _showChangePasswordDialog(auth.userEmail),
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

                  // GROUP 5: SECURITY & STORAGE INFO
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
                              '5. Bảo Mật & Thông Tin Hệ Thống',
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
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.inputBg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.borderDark),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.textWhite)),
          const SizedBox(height: 6),
          Text(desc, style: const TextStyle(fontSize: 12, color: AppColors.textBody, height: 1.4)),
        ],
      ),
    );
  }
}
