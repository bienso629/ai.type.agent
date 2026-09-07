import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../core/services/persona_service.dart';
import '../../core/services/socks5_proxy_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_toast.dart';
import '../../models/persona_profile_model.dart';
import '../../models/server_model.dart';
import '../../providers/server_provider.dart';

class ProfilesScreen extends StatefulWidget {
  const ProfilesScreen({super.key});

  @override
  State<ProfilesScreen> createState() => _ProfilesScreenState();
}

class _ProfilesScreenState extends State<ProfilesScreen> {
  final Set<String> _openingIps = {};
  final Set<String> _closingIps = {};
  final Socks5ProxyService _socks5Service = Socks5ProxyService();
  final PersonaService _personaService = PersonaService();

  Map<String, PersonaProfile> _personas = {};
  bool _isGeneratingPersonas = false;

  @override
  void initState() {
    super.initState();
    _loadPersonas();
  }

  Future<void> _loadPersonas() async {
    final saved = await _personaService.loadSavedPersonas();
    if (mounted) {
      setState(() {
        _personas = Map.from(saved);
      });
    }
  }

  void _copyToClipboard(String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    AppToast.success(context, 'Đã sao chép $label: $text');
  }

  Future<void> _handleGeneratePersonas(List<String> targetIps) async {
    if (targetIps.isEmpty) {
      AppToast.warning(context, 'Không có địa chỉ IP nào để tạo profiles');
      return;
    }

    setState(() {
      _isGeneratingPersonas = true;
    });
    AppToast.info(context, 'AI Agent đang phân tích và tạo hồ sơ nhân vật cho ${targetIps.length} IP...');

    try {
      final newPersonas = await _personaService.generatePersonas(ips: targetIps);
      if (mounted) {
        setState(() {
          _personas.addAll(newPersonas);
        });
        AppToast.success(context, 'AI đã tạo thành công hồ sơ cho ${newPersonas.length} IP');
      }
    } catch (e) {
      if (mounted) {
        AppToast.error(context, 'Lỗi tạo profiles bằng AI: $e');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isGeneratingPersonas = false;
        });
      }
    }
  }

  void _showPersonaDetails(PersonaProfile persona) {
    final nameCtrl = TextEditingController(text: persona.name);
    final ageCtrl = TextEditingController(text: persona.age.toString());
    String selectedGender = persona.gender;
    final bioCtrl = TextEditingController(text: persona.bio);
    final promptCtrl = TextEditingController(text: persona.avatarPrompt);
    bool isSaving = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (dialogCtx, setDialogState) {
          return Dialog(
            backgroundColor: AppColors.cardBg,
            insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: const BorderSide(color: AppColors.borderDark),
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480, maxHeight: 600),
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Header
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(7),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(Icons.person_outline_rounded, color: AppColors.primaryLight, size: 20),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Hồ sơ nhân vật AI',
                                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.textWhite),
                              ),
                              Text(
                                'IP: ${persona.ip}',
                                style: const TextStyle(fontSize: 11.5, fontFamily: 'monospace', color: AppColors.primaryLight),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close_rounded, size: 18, color: AppColors.textDim),
                          onPressed: () => Navigator.of(dialogCtx).pop(),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),

                    // Scrollable form fields
                    Flexible(
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Row Tên + Tuổi + Giới tính
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  flex: 3,
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text('Tên nhân vật', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: AppColors.textWhite)),
                                      const SizedBox(height: 5),
                                      SizedBox(
                                        height: 36,
                                        child: TextField(
                                          controller: nameCtrl,
                                          style: const TextStyle(fontSize: 12),
                                          decoration: const InputDecoration(
                                            contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                            hintText: 'Nhập tên...',
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                SizedBox(
                                  width: 65,
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text('Tuổi', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: AppColors.textWhite)),
                                      const SizedBox(height: 5),
                                      SizedBox(
                                        height: 36,
                                        child: TextField(
                                          controller: ageCtrl,
                                          keyboardType: TextInputType.number,
                                          style: const TextStyle(fontSize: 12),
                                          decoration: const InputDecoration(
                                            contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                            hintText: '25',
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                SizedBox(
                                  width: 85,
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text('Giới tính', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: AppColors.textWhite)),
                                      const SizedBox(height: 5),
                                      Container(
                                        height: 36,
                                        padding: const EdgeInsets.symmetric(horizontal: 8),
                                        decoration: BoxDecoration(
                                          color: AppColors.inputBg,
                                          borderRadius: BorderRadius.circular(6),
                                          border: Border.all(color: AppColors.borderDark),
                                        ),
                                        child: DropdownButtonHideUnderline(
                                          child: DropdownButton<String>(
                                            value: selectedGender,
                                            dropdownColor: AppColors.sidebarBg,
                                            icon: const Icon(Icons.arrow_drop_down, size: 18, color: AppColors.textDim),
                                            isExpanded: true,
                                            style: const TextStyle(fontSize: 12, color: AppColors.textWhite),
                                            items: const [
                                              DropdownMenuItem(value: 'Nam', child: Text('Nam')),
                                              DropdownMenuItem(value: 'Nữ', child: Text('Nữ')),
                                            ],
                                            onChanged: (val) {
                                              if (val != null) {
                                                setDialogState(() {
                                                  selectedGender = val;
                                                });
                                              }
                                            },
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),

                            // Bio cá tính
                            const Text('Cá tính & Tiểu sử (Bio)', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: AppColors.textWhite)),
                            const SizedBox(height: 5),
                            TextField(
                              controller: bioCtrl,
                              maxLines: 2,
                              style: const TextStyle(fontSize: 12, color: AppColors.textDim, height: 1.3),
                              decoration: const InputDecoration(
                                contentPadding: EdgeInsets.all(10),
                                hintText: 'Mô tả nghề nghiệp, sở thích, tính cách...',
                              ),
                            ),
                            const SizedBox(height: 12),

                            // Prompt tạo Avatar AI
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text('Prompt tạo Avatar AI', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: AppColors.textWhite)),
                                InkWell(
                                  onTap: () => _copyToClipboard(promptCtrl.text, 'Avatar Prompt'),
                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.copy_rounded, size: 12, color: AppColors.primaryLight),
                                      SizedBox(width: 4),
                                      Text(
                                        'Sao chép prompt',
                                        style: TextStyle(fontSize: 11, color: AppColors.primaryLight, fontWeight: FontWeight.bold),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 5),
                            TextField(
                              controller: promptCtrl,
                              maxLines: 3,
                              style: const TextStyle(fontSize: 11.5, fontFamily: 'monospace', color: AppColors.primaryLight, height: 1.35),
                              decoration: const InputDecoration(
                                contentPadding: EdgeInsets.all(10),
                                hintText: 'Prompt tiếng Anh tạo chân dung...',
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Actions
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: isSaving ? null : () => Navigator.of(dialogCtx).pop(),
                          child: const Text('Hủy', style: TextStyle(fontSize: 12.5, color: AppColors.textMuted)),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton.icon(
                          onPressed: isSaving
                              ? null
                              : () async {
                                  final newName = nameCtrl.text.trim();
                                  if (newName.isEmpty) {
                                    AppToast.warning(context, 'Tên nhân vật không được để trống');
                                    return;
                                  }
                                  final newAge = int.tryParse(ageCtrl.text.trim()) ?? persona.age;
                                  final updated = PersonaProfile(
                                    ip: persona.ip,
                                    name: newName,
                                    age: newAge,
                                    gender: selectedGender,
                                    bio: bioCtrl.text.trim(),
                                    avatarPrompt: promptCtrl.text.trim(),
                                  );

                                  setDialogState(() {
                                    isSaving = true;
                                  });

                                  try {
                                    await _personaService.updatePersona(updated);
                                    if (mounted) {
                                      setState(() {
                                        _personas[updated.ip] = updated;
                                      });
                                      AppToast.success(context, 'Đã lưu nhân vật cho IP ${updated.ip} vào Database!');
                                    }
                                    if (dialogCtx.mounted) {
                                      Navigator.of(dialogCtx).pop();
                                    }
                                  } catch (e) {
                                    if (mounted) {
                                      AppToast.error(context, 'Lỗi lưu database: $e');
                                    }
                                  } finally {
                                    if (dialogCtx.mounted) {
                                      setDialogState(() {
                                        isSaving = false;
                                      });
                                    }
                                  }
                                },
                          icon: isSaving
                              ? const SizedBox(
                                  width: 13,
                                  height: 13,
                                  child: CircularProgressIndicator(strokeWidth: 1.5, color: Color(0xFF070B14)),
                                )
                              : const Icon(Icons.check_rounded, size: 15),
                          label: Text(
                            isSaving ? 'Đang lưu...' : 'Lưu vào Database',
                            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: const Color(0xFF070B14),
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final serverProvider = context.watch<ServerProvider>();
    final servers = serverProvider.servers;
    final selectedServer = serverProvider.selectedServer;

    // Gom danh sách IP contact card
    final List<_ContactIpItem> allIpCards = [];

    for (final s in servers) {
      final ips = serverProvider.getIpsForServer(s);
      final isSelected = selectedServer != null && (selectedServer.id == s.id || selectedServer.serverIp == s.serverIp);

      for (int i = 0; i < ips.length; i++) {
        final ip = ips[i];
        final isMain = ip == s.serverIp;

        allIpCards.add(
          _ContactIpItem(
            ip: ip,
            isMain: isMain,
            server: s,
            isCurrentServer: isSelected,
          ),
        );
      }
    }

    final allTargetIps = allIpCards.map((e) => e.ip).toSet().toList();

    return Scaffold(
      backgroundColor: AppColors.bgDark,
      body: Column(
        children: [
          // 1. TOP TOOLBAR
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            decoration: const BoxDecoration(
              color: AppColors.cardBg,
              border: Border(bottom: BorderSide(color: AppColors.borderDark, width: 1)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.contact_mail_rounded, color: AppColors.primaryLight, size: 20),
                          const SizedBox(width: 8),
                          const Text(
                            'Profiles / IP Contact Cards',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textWhite),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        selectedServer != null
                            ? 'Danh sách các IP trỏ vào VPS máy chủ [${selectedServer.name}] (${selectedServer.serverIp})'
                            : 'Danh sách các đầu IP đang trỏ vào hệ thống máy chủ SSH',
                        style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
                      ),
                    ],
                  ),
                ),

                // Nút "AI tạo profiles" thay thế tìm kiếm và quét lại IP
                ElevatedButton.icon(
                  onPressed: _isGeneratingPersonas
                      ? null
                      : () => _handleGeneratePersonas(allTargetIps),
                  icon: _isGeneratingPersonas
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF070B14)),
                        )
                      : const Icon(Icons.auto_awesome_rounded, size: 16),
                  label: Text(
                    _isGeneratingPersonas ? 'Đang tạo profiles...' : 'AI tạo profiles',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: const Color(0xFF070B14),
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // 2. CONTACT CARDS GRID VIEW
          Expanded(
            child: allIpCards.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.contact_mail_outlined, size: 54, color: AppColors.textDim.withValues(alpha: 0.5)),
                        const SizedBox(height: 14),
                        const Text(
                          'Chưa tìm thấy IP nào trỏ vào máy chủ',
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textWhite),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Hãy kiểm tra lại cấu hình kết nối SSH trong mục Cấu hình',
                          style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                        ),
                      ],
                    ),
                  )
                : LayoutBuilder(
                    builder: (context, constraints) {
                      // Tính toán số cột responsive linh hoạt: tối thiểu 1 cột, tối đa 5 cột
                      // Mỗi card có độ rộng lý tưởng khoảng 300 - 360px
                      int crossAxisCount = (constraints.maxWidth / 320).floor();
                      if (crossAxisCount < 1) crossAxisCount = 1;
                      if (crossAxisCount > 5) crossAxisCount = 5;

                      return GridView.builder(
                        padding: const EdgeInsets.all(16),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: crossAxisCount,
                          crossAxisSpacing: 14,
                          mainAxisSpacing: 14,
                          mainAxisExtent: 240,
                        ),
                        itemCount: allIpCards.length,
                        itemBuilder: (context, idx) {
                          final item = allIpCards[idx];
                          return _buildContactCard(item);
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  // Khung danh thiếp Contact Card cho từng IP
  Widget _buildContactCard(_ContactIpItem item) {
    final socks5 = context.watch<Socks5ProxyService>();
    final isBrowserRunning = socks5.isBrowserRunningForIp(item.ip);
    final isAlias = !item.isMain;
    final persona = _personas[item.ip];

    final Color cardBorderColor;
    final Color cardBgColor;
    final Color badgeBgColor;
    final Color badgeTextColor;
    final String statusText;
    final Color statusDotColor;

    if (isBrowserRunning) {
      if (isAlias) {
        cardBorderColor = AppColors.accent;
        cardBgColor = const Color(0xFF091E1A);
        badgeBgColor = AppColors.accent.withValues(alpha: 0.2);
        badgeTextColor = AppColors.accent;
        statusText = 'Trình duyệt đang mở';
        statusDotColor = AppColors.accent;
      } else {
        cardBorderColor = AppColors.primaryLight;
        cardBgColor = const Color(0xFF1C1908);
        badgeBgColor = AppColors.primary.withValues(alpha: 0.2);
        badgeTextColor = AppColors.primaryLight;
        statusText = 'Trình duyệt đang mở';
        statusDotColor = AppColors.primaryLight;
      }
    } else {
      cardBorderColor = item.isCurrentServer ? AppColors.primary.withValues(alpha: 0.4) : AppColors.borderDark;
      cardBgColor = AppColors.cardBg;
      badgeBgColor = item.isMain ? AppColors.accent.withValues(alpha: 0.12) : AppColors.sidebarBg;
      badgeTextColor = item.isMain ? AppColors.accent : AppColors.textDim;
      statusText = isAlias ? 'Sẵn sàng kết nối Alias' : 'Sẵn sàng kết nối';
      statusDotColor = item.isMain ? AppColors.accent : AppColors.textDim;
    }

    return Container(
      decoration: BoxDecoration(
        color: cardBgColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: cardBorderColor,
          width: isBrowserRunning ? 1.8 : (item.isCurrentServer ? 1.3 : 1),
        ),
        boxShadow: [
          BoxShadow(
            color: isBrowserRunning
                ? (isAlias ? AppColors.accent.withValues(alpha: 0.2) : AppColors.primary.withValues(alpha: 0.2))
                : Colors.black.withValues(alpha: 0.2),
            blurRadius: isBrowserRunning ? 10 : 6,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header Card (Tên máy chủ + Trạng thái Loại IP)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: isBrowserRunning
                  ? (isAlias ? const Color(0xFF0B2923) : const Color(0xFF26200A))
                  : (item.isCurrentServer ? AppColors.primary.withValues(alpha: 0.12) : AppColors.sidebarBg),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(9)),
              border: Border(bottom: BorderSide(color: isBrowserRunning ? cardBorderColor.withValues(alpha: 0.4) : AppColors.borderDark, width: 0.8)),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.dns_rounded,
                  size: 15,
                  color: isBrowserRunning
                      ? (isAlias ? AppColors.accent : AppColors.primaryLight)
                      : (item.isCurrentServer ? AppColors.primaryLight : AppColors.textDim),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    item.server.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: isBrowserRunning
                          ? (isAlias ? AppColors.accent : AppColors.primaryLight)
                          : (item.isCurrentServer ? AppColors.primaryLight : AppColors.textWhite),
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: badgeBgColor,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: isBrowserRunning ? cardBorderColor.withValues(alpha: 0.5) : AppColors.borderDark,
                    ),
                  ),
                  child: Text(
                    item.isMain ? 'IP GỐC' : 'ALIAS IP',
                    style: TextStyle(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w700,
                      color: badgeTextColor,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Body Card (IP Avatar + Persona Profile Specs)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Row 1: Avatar badge + Name / IP / Status
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: isBrowserRunning
                              ? (isAlias ? AppColors.accent.withValues(alpha: 0.15) : AppColors.primary.withValues(alpha: 0.15))
                              : AppColors.inputBg,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: isBrowserRunning
                                ? cardBorderColor
                                : (item.isMain ? AppColors.accent.withValues(alpha: 0.5) : AppColors.borderDark),
                            width: 1.2,
                          ),
                        ),
                        child: Center(
                          child: Icon(
                            persona != null
                                ? (persona.gender.toLowerCase() == 'nữ' ? Icons.face_3_rounded : Icons.face_rounded)
                                : (isBrowserRunning ? Icons.language_rounded : Icons.fingerprint_rounded),
                            color: isBrowserRunning
                                ? (isAlias ? AppColors.accent : AppColors.primaryLight)
                                : (item.isMain ? AppColors.accent : AppColors.primaryLight),
                            size: 22,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Tên nhân vật hoặc hiển thị Chưa tạo
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    persona?.name ?? 'Chưa tạo nhân vật',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                      color: persona != null ? AppColors.textWhite : AppColors.textDim,
                                    ),
                                  ),
                                ),
                                if (persona != null) ...[
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                    decoration: BoxDecoration(
                                      color: AppColors.primary.withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(3),
                                    ),
                                    child: Text(
                                      '${persona.gender} · ${persona.age}t',
                                      style: const TextStyle(fontSize: 9.5, color: AppColors.primaryLight, fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 3),
                            // IP và Trạng thái kết nối
                            Row(
                              children: [
                                InkWell(
                                  onTap: () => _copyToClipboard(item.ip, 'IP'),
                                  borderRadius: BorderRadius.circular(4),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        item.ip,
                                        style: TextStyle(
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.w600,
                                          fontFamily: 'monospace',
                                          color: isBrowserRunning
                                              ? (isAlias ? AppColors.accent : AppColors.primaryLight)
                                              : AppColors.textMuted,
                                        ),
                                      ),
                                      const SizedBox(width: 3),
                                      const Icon(Icons.copy_rounded, size: 10.5, color: AppColors.textDim),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Container(
                                  width: 5,
                                  height: 5,
                                  decoration: BoxDecoration(
                                    color: statusDotColor,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    statusText,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: statusDotColor,
                                      fontWeight: isBrowserRunning ? FontWeight.w600 : FontWeight.normal,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 8),

                  // Row 2: Bio hoặc Nút xem Prompt avatar
                  if (persona != null) ...[
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                        decoration: BoxDecoration(
                          color: AppColors.inputBg.withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: AppColors.borderDark.withValues(alpha: 0.5)),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Text(
                                persona.bio,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 11, color: AppColors.textDim, height: 1.3),
                              ),
                            ),
                            const SizedBox(width: 4),
                            Tooltip(
                              message: 'Xem chi tiết & Chỉnh sửa nhân vật',
                              child: InkWell(
                                onTap: () => _showPersonaDetails(persona),
                                borderRadius: BorderRadius.circular(4),
                                child: Container(
                                  padding: const EdgeInsets.all(5),
                                  decoration: BoxDecoration(
                                    color: AppColors.primary.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
                                  ),
                                  child: const Icon(Icons.edit_note_rounded, size: 16, color: AppColors.primaryLight),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ] else ...[
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                        decoration: BoxDecoration(
                          color: AppColors.inputBg.withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: AppColors.borderDark.withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(
                                color: statusDotColor,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                'Bấm "AI tạo profiles" để sinh danh tính và prompt avatar',
                                maxLines: 2,
                                style: const TextStyle(fontSize: 10.5, color: AppColors.textDim),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),

          // Footer Action Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: isBrowserRunning
                  ? (isAlias ? const Color(0xFF09211C) : const Color(0xFF211D09))
                  : AppColors.sidebarBg,
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(9)),
              border: Border(top: BorderSide(color: isBrowserRunning ? cardBorderColor.withValues(alpha: 0.3) : AppColors.borderDark, width: 0.8)),
            ),
            child: () {
              final isOpening = _openingIps.contains(item.ip);
              final isClosing = _closingIps.contains(item.ip);
              final isBusy = isOpening || isClosing;

              if (isBrowserRunning) {
                // Đang mở trình duyệt -> Duy nhất 1 nút "Đóng trình duyệt" (màu đỏ)
                return ElevatedButton.icon(
                  onPressed: isBusy
                      ? null
                      : () async {
                          setState(() {
                            _closingIps.add(item.ip);
                          });
                          try {
                            await _socks5Service.stopSession(item.ip);
                            if (mounted) {
                              AppToast.info(context, 'Đã đóng trình duyệt cho ${item.ip}');
                            }
                          } catch (e) {
                            if (mounted) {
                              AppToast.error(context, 'Lỗi khi đóng trình duyệt: $e');
                            }
                          } finally {
                            if (mounted) {
                              setState(() {
                                _closingIps.remove(item.ip);
                              });
                            }
                          }
                        },
                  icon: isClosing
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 1.5, color: Colors.white),
                        )
                      : const Icon(Icons.close_rounded, size: 16),
                  label: Text(
                    isClosing ? 'Đang đóng trình duyệt...' : 'Đóng trình duyệt',
                    style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.danger,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 9),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                );
              }

              // Chưa mở trình duyệt -> Duy nhất 1 nút "Mở trình duyệt"
              return ElevatedButton.icon(
                onPressed: isBusy
                    ? null
                    : () async {
                        setState(() {
                          _openingIps.add(item.ip);
                        });
                        AppToast.info(context, 'Đang mở trình duyệt cho ${item.ip}...');
                        try {
                          await _socks5Service.launchBrowserWithSocks5(
                            server: item.server,
                            ip: item.ip,
                          );
                          if (mounted) {
                            AppToast.success(context, 'Đã mở trình duyệt qua ${item.ip}');
                          }
                        } catch (e) {
                          if (mounted) {
                            AppToast.error(context, 'Lỗi mở trình duyệt: $e');
                          }
                        } finally {
                          if (mounted) {
                            setState(() {
                              _openingIps.remove(item.ip);
                            });
                          }
                        }
                      },
                icon: isOpening
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 1.5, color: Color(0xFF070B14)),
                      )
                    : const Icon(Icons.open_in_browser_rounded, size: 16),
                label: Text(
                  isOpening ? 'Đang mở trình duyệt...' : 'Mở trình duyệt',
                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: const Color(0xFF070B14),
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 9),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
              );
            }(),
          ),
        ],
      ),
    );
  }
}

class _ContactIpItem {
  final String ip;
  final bool isMain;
  final ServerModel server;
  final bool isCurrentServer;

  _ContactIpItem({
    required this.ip,
    required this.isMain,
    required this.server,
    required this.isCurrentServer,
  });
}
