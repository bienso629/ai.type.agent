import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_toast.dart';
import '../../core/widgets/tadu_dialog.dart';
import '../../models/profile_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/profile_provider.dart';

class ProfilesScreen extends StatefulWidget {
  const ProfilesScreen({super.key});

  @override
  State<ProfilesScreen> createState() => _ProfilesScreenState();
}

class _ProfilesScreenState extends State<ProfilesScreen> {
  final TextEditingController _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final auth = context.read<AuthProvider>();
      final pProvider = context.read<ProfileProvider>();
      pProvider.init(auth.userName);
      pProvider.addMockProfileIfEmpty();
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _showAddProfileDialog() {
    final nameCtrl = TextEditingController(text: 'Profile${DateTime.now().millisecondsSinceEpoch.toString().substring(8)}');
    final noteCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => TaduDialog(
        minWidth: 460,
        maxWidth: 520,
        title: const Row(
          children: [
            Icon(Icons.person_add_alt_1_rounded, color: AppColors.primaryLight, size: 20),
            SizedBox(width: 8),
            Text('Tạo Profile Trình Duyệt Mới'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Tên Profile Định Danh',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.textDim),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(
                hintText: 'Ví dụ: Profile003...',
                prefixIcon: Icon(Icons.badge_outlined, size: 18),
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              'Ghi Chú / Vai Trò Nhân Cách',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.textDim),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: noteCtrl,
              decoration: const InputDecoration(
                hintText: 'Mô tả vai trò, nhiệm vụ nuôi nick...',
                prefixIcon: Icon(Icons.description_outlined, size: 18),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Hủy'),
          ),
          ElevatedButton(
            onPressed: () {
              final name = nameCtrl.text.trim();
              if (name.isEmpty) return;
              final pProvider = context.read<ProfileProvider>();
              pProvider.profiles.add(
                ProfileItem(
                  profile: name,
                  running: false,
                  note: noteCtrl.text.trim().isNotEmpty ? noteCtrl.text.trim() : null,
                  accounts: [
                    ProfileAccount(alias: name, platform: 'tiktok', active: true),
                  ],
                ),
              );
              pProvider.notifyListeners();
              Navigator.pop(ctx);
              AppToast.success(context, 'Đã tạo $name thành công!');
            },
            child: const Text('Tạo Profile'),
          ),
        ],
      ),
    );
  }

  void _confirmDeleteProfile(ProfileItem item) {
    showDialog(
      context: context,
      builder: (ctx) => TaduDialog(
        minWidth: 420,
        maxWidth: 480,
        title: const Row(
          children: [
            Icon(Icons.delete_forever_rounded, color: AppColors.danger, size: 20),
            SizedBox(width: 8),
            Text('Xóa Vĩnh Viễn Profile'),
          ],
        ),
        content: Text(
          'Bạn có chắc chắn muốn xóa hẳn profile "${item.profile}"? Hành động này sẽ hủy và dọn sạch session lưu trữ.',
          style: const TextStyle(fontSize: 13, color: AppColors.textBody),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Hủy'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () async {
              Navigator.pop(ctx);
              final success = await context.read<ProfileProvider>().deleteProfile(item);
              if (mounted) {
                if (success) {
                  AppToast.success(context, 'Đã xóa ${item.profile}');
                } else {
                  AppToast.error(context, 'Không thể xóa ${item.profile}');
                }
              }
            },
            child: const Text('Xóa vĩnh viễn'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ProfileProvider>();
    final profiles = provider.profiles;

    return Scaffold(
      backgroundColor: AppColors.bgDark,
      body: Column(
        children: [
          // 1. TOP HEADER & TOOLBAR
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
                          const Icon(Icons.people_alt_rounded, color: AppColors.primaryLight, size: 20),
                          const SizedBox(width: 8),
                          const Text(
                            'Quản Lý Profile Trình Duyệt',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textWhite),
                          ),
                          const SizedBox(width: 12),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
                            ),
                            child: Text(
                              '${provider.runningCount}/${provider.totalProfiles} đang chạy',
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: AppColors.primaryLight,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Quản lý cô lập môi trường vân tay trình duyệt, tài khoản mạng xã hội & auto-farm',
                        style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                      ),
                    ],
                  ),
                ),
                // Ô tìm kiếm
                SizedBox(
                  width: 220,
                  height: 36,
                  child: TextField(
                    controller: _searchCtrl,
                    onChanged: provider.setSearchQuery,
                    style: const TextStyle(fontSize: 12.5),
                    decoration: InputDecoration(
                      hintText: 'Tìm profile / alias...',
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10),
                      prefixIcon: const Icon(Icons.search_rounded, size: 16, color: AppColors.textDim),
                      suffixIcon: _searchCtrl.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 14),
                              onPressed: () {
                                _searchCtrl.clear();
                                provider.setSearchQuery('');
                              },
                            )
                          : null,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                // Nút Làm mới
                OutlinedButton.icon(
                  onPressed: () => provider.loadProfiles(),
                  icon: provider.isLoading
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primaryLight),
                        )
                      : const Icon(Icons.refresh_rounded, size: 16),
                  label: const Text('Làm mới'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.textWhite,
                    side: const BorderSide(color: AppColors.borderDark),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  ),
                ),
                const SizedBox(width: 8),
                // Nút Tạo Profile Mới
                ElevatedButton.icon(
                  onPressed: _showAddProfileDialog,
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('Tạo Profile'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  ),
                ),
              ],
            ),
          ),

          // 2. MAIN TABLE / LIST VIEW
          Expanded(
            child: profiles.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.web_stories_outlined, size: 54, color: AppColors.textDim.withValues(alpha: 0.5)),
                        const SizedBox(height: 14),
                        const Text(
                          'Chưa có Profile nào được cấu hình',
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textWhite),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Nhấp nút "Tạo Profile" phía trên để khởi tạo hồ sơ trình duyệt đầu tiên',
                          style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                        ),
                      ],
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: profiles.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, idx) {
                      final item = profiles[idx];
                      return _buildProfileCard(item, provider);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileCard(ProfileItem item, ProfileProvider provider) {
    final isMaster = item.profile == 'Profile000';
    final acc = item.accounts.isNotEmpty ? item.accounts.first : null;
    final aliasName = acc?.alias ?? item.profile;
    final platform = acc?.platform ?? 'tiktok';

    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: item.running ? AppColors.accent.withValues(alpha: 0.5) : AppColors.borderDark,
          width: item.running ? 1.2 : 1,
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          // Avatar
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: isMaster ? AppColors.primary.withValues(alpha: 0.25) : AppColors.sidebarBg,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: item.running ? AppColors.accent : (isMaster ? AppColors.primary : AppColors.borderDark),
                width: 1.5,
              ),
            ),
            child: Center(
              child: isMaster
                  ? const Icon(Icons.star_rounded, color: AppColors.primaryLight, size: 24)
                  : Text(
                      aliasName.isNotEmpty ? aliasName[0].toUpperCase() : 'P',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: item.running ? AppColors.accent : AppColors.primaryLight,
                      ),
                    ),
            ),
          ),
          const SizedBox(width: 14),

          // Thông tin chính
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Text(
                      item.profile,
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.textWhite),
                    ),
                    if (isMaster) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'MASTER',
                          style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: AppColors.primaryLight),
                        ),
                      ),
                    ],
                    const SizedBox(width: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: item.running
                            ? AppColors.accent.withValues(alpha: 0.15)
                            : AppColors.sidebarBg,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: item.running ? AppColors.accent.withValues(alpha: 0.4) : AppColors.borderDark,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: item.running ? AppColors.accent : AppColors.textDim,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 5),
                          Text(
                            item.running ? 'Đang chạy' : 'Đã dừng',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: item.running ? AppColors.accent : AppColors.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(
                      platform == 'tiktok' ? Icons.music_note_rounded : Icons.public_rounded,
                      size: 13,
                      color: AppColors.textDim,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      acc?.email ?? acc?.alias ?? 'Chưa liên kết tài khoản',
                      style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
                    ),
                    if (item.devtoolsPort != null) ...[
                      const SizedBox(width: 12),
                      Text(
                        'Port: ${item.devtoolsPort}',
                        style: const TextStyle(fontFamily: 'monospace', fontSize: 11, color: AppColors.primaryLight),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),

          // Ghi chú / Persona
          Expanded(
            flex: 2,
            child: Text(
              item.note ?? 'Chưa có vai trò nhân cách...',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11.5,
                color: item.note != null ? AppColors.textBody : AppColors.textDim,
                fontStyle: item.note != null ? FontStyle.normal : FontStyle.italic,
              ),
            ),
          ),

          const SizedBox(width: 14),

          // Action Buttons
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!item.running)
                ElevatedButton.icon(
                  onPressed: () async {
                    AppToast.info(context, 'Đang mở trình duyệt ${item.profile}...');
                    final ok = await provider.startProfile(item);
                    if (context.mounted && ok) {
                      AppToast.success(context, 'Đã mở ${item.profile}');
                    }
                  },
                  icon: const Icon(Icons.play_arrow_rounded, size: 16),
                  label: const Text('Mở'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                )
              else
                OutlinedButton.icon(
                  onPressed: () async {
                    AppToast.info(context, 'Đang tắt trình duyệt ${item.profile}...');
                    final ok = await provider.stopProfile(item);
                    if (context.mounted && ok) {
                      AppToast.warning(context, 'Đã đóng ${item.profile}');
                    }
                  },
                  icon: const Icon(Icons.stop_rounded, size: 16, color: AppColors.danger),
                  label: const Text('Đóng', style: TextStyle(color: AppColors.danger)),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppColors.danger),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                ),
              const SizedBox(width: 6),
              IconButton(
                icon: const Icon(Icons.delete_outline_rounded, size: 18, color: AppColors.textDim),
                tooltip: 'Xóa Profile',
                onPressed: () => _confirmDeleteProfile(item),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
