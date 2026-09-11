import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme/app_theme.dart';
import 'app_toast.dart';
import '../../providers/auth_provider.dart';
import '../../providers/server_provider.dart';

class ModelPickerDialog extends StatefulWidget {
  final ServerProvider serverProvider;
  final bool isAdmin;
  final int initialTab; // 0: Cloud API, 1: Local CLI

  const ModelPickerDialog({
    super.key,
    required this.serverProvider,
    required this.isAdmin,
    this.initialTab = 0,
  });

  static void show(BuildContext context, {int initialTab = 0}) {
    final serverProvider = context.read<ServerProvider>();
    final auth = context.read<AuthProvider>();
    showDialog(
      context: context,
      builder: (ctx) => ModelPickerDialog(
        serverProvider: serverProvider,
        isAdmin: auth.isAdmin,
        initialTab: initialTab,
      ),
    );
  }

  static void showCustomModelDialog(BuildContext context, ServerProvider serverProvider) {
    final ctrl = TextEditingController(text: serverProvider.currentAiModel);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.cardBg,
        title: const Text('Nhập AI Model tùy biến', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.textWhite)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Nhập tên model (VD: glm-5.3, gpt-4o, claude-cli, ollama...)',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Hủy', style: TextStyle(color: AppColors.textMuted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
            onPressed: () {
              final val = ctrl.text.trim();
              if (val.isNotEmpty) {
                serverProvider.setActiveAgent(val);
                Navigator.pop(ctx);
                AppToast.success(context, 'Đã cập nhật AI Model: $val');
              }
            },
            child: const Text('Lưu chọn'),
          ),
        ],
      ),
    );
  }

  @override
  State<ModelPickerDialog> createState() => _ModelPickerDialogState();
}

class _ModelPickerDialogState extends State<ModelPickerDialog> {
  final TextEditingController _searchCtrl = TextEditingController();
  String _searchQuery = '';
  late int _selectedTab; // 0: Cloud API, 1: Local CLI

  @override
  void initState() {
    super.initState();
    // Mặc định hiển thị Tất cả (-1) để nhìn thấy cả CLI và Cloud cùng lúc, hoặc theo initialTab nếu được truyền vào
    _selectedTab = widget.initialTab != 0 ? widget.initialTab : -1;
    // Luôn chủ động quét lại Local CLI Agents và tải danh sách Models từ mitom.ai
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.serverProvider.scanCliAgents(forceRefresh: true);
      widget.serverProvider.fetchMitomModels();
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ServerProvider>(
      builder: (context, serverProvider, child) {
        final q = _searchQuery.toLowerCase();

        // CLI Agents: Luôn hiển thị đầy đủ các local agents đã quét được
        final filteredCliAgents = serverProvider.installedCliAgents.where((a) {
          if (q.isEmpty) return true;
          return a.id.toLowerCase().contains(q) || a.label.toLowerCase().contains(q);
        }).toList();

        // Cloud Models: Lấy từ API https://api-vn-sg.mitom.ai/v1/models (fallback nếu chưa tải xong)
        final cloudModelsSource = serverProvider.mitomModels.isNotEmpty
            ? serverProvider.mitomModels
            : const ['glm-5.3', 'gpt-4o', 'deepseek-chat', 'claude-3-7-sonnet'];
        final filteredCloudModels = cloudModelsSource.where((m) {
          if (q.isEmpty) return true;
          return m.toLowerCase().contains(q);
        }).toList();

        return Dialog(
          backgroundColor: AppColors.cardBg,
          elevation: 24,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(6),
            side: const BorderSide(color: AppColors.borderDark, width: 1),
          ),
          child: Container(
            width: 560,
            height: 640,
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
            // 1. Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Icon(Icons.smart_toy_rounded, size: 20, color: AppColors.primaryLight),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Text(
                            'Chọn AI Agent & Model',
                            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.textWhite),
                          ),
                          if (widget.isAdmin) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppColors.accentCyan.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: AppColors.accentCyan.withValues(alpha: 0.4)),
                              ),
                              child: const Text(
                                'ADMIN ACCESS',
                                style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: AppColors.accentCyan),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Lựa chọn model AI tự động',
                        style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.refresh_rounded, size: 18, color: AppColors.accentCyan),
                  tooltip: 'Tải lại Models mitom.ai & quét Local CLI',
                  onPressed: () {
                    serverProvider.scanCliAgents(forceRefresh: true);
                    serverProvider.fetchMitomModels(forceRefresh: true);
                    AppToast.info(context, 'Đang làm mới danh sách Models & CLI Agents...');
                  },
                ),
                const SizedBox(width: 4),
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 18, color: AppColors.textDim),
                  tooltip: 'Đóng',
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),

            const SizedBox(height: 12),

            // Tab Filter: Tất cả, Local CLI Agent, Cloud API
            Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: AppColors.sidebarBg,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: AppColors.borderDark),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(4),
                      onTap: () => setState(() => _selectedTab = -1),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        decoration: BoxDecoration(
                          color: _selectedTab == -1
                              ? AppColors.primary.withValues(alpha: 0.25)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: _selectedTab == -1
                                ? AppColors.primaryLight
                                : Colors.transparent,
                          ),
                        ),
                        child: Center(
                          child: Text(
                            'Tất cả',
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: _selectedTab == -1 ? FontWeight.bold : FontWeight.normal,
                              color: _selectedTab == -1 ? AppColors.primaryLight : AppColors.textMuted,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(4),
                      onTap: () => setState(() => _selectedTab = 1),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        decoration: BoxDecoration(
                          color: _selectedTab == 1
                              ? AppColors.accentCyan.withValues(alpha: 0.2)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: _selectedTab == 1
                                ? AppColors.accentCyan
                                : Colors.transparent,
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.terminal_rounded,
                              size: 13,
                              color: _selectedTab == 1 ? AppColors.accentCyan : AppColors.textDim,
                            ),
                            const SizedBox(width: 5),
                            Text(
                              'Local CLI Agent',
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: _selectedTab == 1 ? FontWeight.bold : FontWeight.normal,
                                color: _selectedTab == 1 ? AppColors.accentCyan : AppColors.textMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(4),
                      onTap: () => setState(() => _selectedTab = 0),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        decoration: BoxDecoration(
                          color: _selectedTab == 0
                              ? AppColors.primary.withValues(alpha: 0.25)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: _selectedTab == 0
                                ? AppColors.primaryLight
                                : Colors.transparent,
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.cloud_queue_rounded,
                              size: 13,
                              color: _selectedTab == 0 ? AppColors.primaryLight : AppColors.textDim,
                            ),
                            const SizedBox(width: 5),
                            Text(
                              'Cloud API',
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: _selectedTab == 0 ? FontWeight.bold : FontWeight.normal,
                                color: _selectedTab == 0 ? AppColors.primaryLight : AppColors.textMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),

            // 2. Search Input
            SizedBox(
              height: 38,
              child: TextField(
                controller: _searchCtrl,
                autofocus: false,
                textAlignVertical: TextAlignVertical.center,
                style: const TextStyle(fontSize: 12.5, color: AppColors.textWhite),
                onChanged: (val) => setState(() => _searchQuery = val.trim()),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'Tìm kiếm Agent CLI (agy, claude...) hoặc Cloud model...',
                  hintStyle: const TextStyle(fontSize: 12, color: AppColors.textMuted),
                  prefixIcon: const Icon(Icons.search_rounded, size: 16, color: AppColors.textMuted),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          padding: EdgeInsets.zero,
                          hoverColor: Colors.transparent,
                          splashColor: Colors.transparent,
                          icon: const Icon(Icons.clear_rounded, size: 16, color: AppColors.textDim),
                          onPressed: () {
                            _searchCtrl.clear();
                            setState(() => _searchQuery = '');
                          },
                        )
                      : null,
                  filled: true,
                  fillColor: AppColors.inputBg,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(4),
                    borderSide: const BorderSide(color: AppColors.borderDark),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(4),
                    borderSide: const BorderSide(color: AppColors.borderDark),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(4),
                    borderSide: const BorderSide(color: AppColors.primaryLight, width: 1),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 12),

            // 3. Scrollable List of Models & Agents
            Expanded(
              child: ListView(
                children: [
                  // --- SECTION 1: LOCAL CLI AGENTS ---
                  if (_selectedTab == -1 || _selectedTab == 1) ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        children: [
                          const Icon(Icons.terminal_rounded, size: 14, color: AppColors.accentCyan),
                          const SizedBox(width: 6),
                          const Text(
                            'LOCAL CLI AGENTS (CHẠY TRÊN MÁY LOCAL)',
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.accentCyan, letterSpacing: 0.5),
                          ),
                          const Spacer(),
                          if (filteredCliAgents.isNotEmpty)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppColors.accentCyan.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                '${filteredCliAgents.length} agents sẵn sàng',
                                style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.accentCyan),
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (serverProvider.isScanningCliAgents)
                      const Padding(
                        padding: EdgeInsets.all(12),
                        child: Center(
                          child: SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accentCyan),
                          ),
                        ),
                      )
                    else if (filteredCliAgents.isEmpty)
                      Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.sidebarBg,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: AppColors.borderDark),
                        ),
                        child: const Text(
                          'Chưa tìm thấy CLI Agent nào khớp trên máy tính.',
                          style: TextStyle(fontSize: 11, color: AppColors.textMuted),
                        ),
                      )
                    else
                      ...filteredCliAgents.map((agent) {
                        final isSel = serverProvider.isCliMode && serverProvider.activeCliAgent == agent.id;
                        final icon = agent.id.contains('antigravity') || agent.binary.contains('agy')
                            ? Icons.rocket_launch_rounded
                            : (agent.id.contains('claude') ? Icons.code_rounded : Icons.terminal_rounded);
                        final verStr = agent.version != null ? ' • v${agent.version}' : '';

                        return _buildModelCard(
                          title: agent.label,
                          subtitle: '${agent.id} (${agent.path}$verStr)',
                          icon: icon,
                          isSelected: isSel,
                          onTap: () {
                            serverProvider.setActiveCliAgent(agent.id);
                            Navigator.pop(context);
                            AppToast.success(context, 'Đã kích hoạt Local CLI Agent: ${agent.label}');
                          },
                        );
                      }),
                    const SizedBox(height: 14),
                  ],

                  // --- SECTION 2: CLOUD LLM MODELS ---
                  if (_selectedTab == -1 || _selectedTab == 0) ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        children: [
                          const Icon(Icons.cloud_queue_rounded, size: 14, color: AppColors.primaryLight),
                          const SizedBox(width: 6),
                          const Text(
                            'CLOUD LLM MODELS (API-VN-SG.MITOM.AI)',
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.primaryLight, letterSpacing: 0.5),
                          ),
                          const Spacer(),
                          if (serverProvider.isLoadingMitomModels) ...[
                            const SizedBox(
                              width: 12,
                              height: 12,
                              child: CircularProgressIndicator(strokeWidth: 1.5, color: AppColors.primaryLight),
                            ),
                            const SizedBox(width: 6),
                          ],
                          Text(
                            '${filteredCloudModels.length} models',
                            style: const TextStyle(fontSize: 10, color: AppColors.textDim),
                          ),
                        ],
                      ),
                    ),

                    if (serverProvider.isLoadingMitomModels && filteredCloudModels.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(16),
                        child: Center(
                          child: SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primaryLight),
                          ),
                        ),
                      )
                    else if (filteredCloudModels.isNotEmpty)
                      ...filteredCloudModels.map((m) {
                        final isSel = !serverProvider.isCliMode && serverProvider.cloudAiModel == m;
                        IconData icon = Icons.memory_rounded;
                        if (m.contains('glm')) {
                          icon = Icons.auto_awesome_rounded;
                        } else if (m.contains('gpt')) {
                          icon = Icons.psychology_rounded;
                        } else if (m.contains('claude')) {
                          icon = Icons.star_rounded;
                        } else if (m.contains('gemini')) {
                          icon = Icons.auto_awesome_rounded;
                        } else if (m.contains('deepseek')) {
                          icon = Icons.code_rounded;
                        }

                        return _buildModelCard(
                          title: m,
                          subtitle: 'Cloud API Model (mitom.ai)',
                          icon: icon,
                          isSelected: isSel,
                          onTap: () {
                            serverProvider.setCloudAiModel(m);
                            Navigator.pop(context);
                            AppToast.success(context, 'Đã chọn Cloud Model: $m');
                          },
                        );
                      })
                    else ...[
                      Container(
                        padding: const EdgeInsets.all(18),
                        alignment: Alignment.center,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.search_off_rounded, size: 28, color: AppColors.textDim),
                            const SizedBox(height: 8),
                            Text(
                              'Không tìm thấy model nào khớp với "$_searchQuery"',
                              style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
                            ),
                            if (_searchQuery.isNotEmpty) ...[
                              const SizedBox(height: 10),
                              OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  side: const BorderSide(color: AppColors.primaryLight),
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                ),
                                icon: const Icon(Icons.add_rounded, size: 14, color: AppColors.primaryLight),
                                label: Text('Chọn "$_searchQuery" làm model', style: const TextStyle(fontSize: 11.5, color: AppColors.primaryLight)),
                                onPressed: () {
                                  serverProvider.setActiveAgent(_searchQuery);
                                  Navigator.pop(context);
                                  AppToast.success(context, 'Đã thiết lập model: $_searchQuery');
                                },
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ],
                ],
              ),
            ),

            const SizedBox(height: 10),
            const Divider(color: AppColors.borderDark, height: 1),
            const SizedBox(height: 10),

            // 4. Footer Action
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                TextButton.icon(
                  icon: const Icon(Icons.edit_note_rounded, size: 16, color: AppColors.textDim),
                  label: const Text('Nhập model tùy biến khác...', style: TextStyle(fontSize: 12, color: AppColors.textDim)),
                  onPressed: () {
                    Navigator.pop(context);
                    ModelPickerDialog.showCustomModelDialog(context, serverProvider);
                  },
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Đóng', style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
      },
    );
  }

  Widget _buildModelCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: isSelected ? AppColors.primary.withValues(alpha: 0.15) : AppColors.cardBg,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: isSelected ? AppColors.primaryLight : AppColors.borderDark,
          width: isSelected ? 1.5 : 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(4),
        child: InkWell(
          borderRadius: BorderRadius.circular(4),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? AppColors.primary.withValues(alpha: 0.3)
                        : AppColors.inputBg,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Icon(
                    icon,
                    size: 16,
                    color: isSelected ? AppColors.primaryLight : AppColors.textMuted,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                color: isSelected ? AppColors.primaryLight : AppColors.textWhite,
                              ),
                            ),
                          ),
                          if (isSelected) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                              decoration: BoxDecoration(
                                color: AppColors.primary,
                                borderRadius: BorderRadius.circular(3),
                              ),
                              child: const Text(
                                'ĐANG DÙNG',
                                style: TextStyle(fontSize: 8.5, fontWeight: FontWeight.bold, color: Colors.white),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11, color: AppColors.textDim),
                      ),
                    ],
                  ),
                ),
                if (isSelected)
                  const Icon(Icons.check_circle_rounded, size: 18, color: AppColors.primaryLight)
                else
                  const Icon(Icons.chevron_right_rounded, size: 18, color: AppColors.textDim),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
