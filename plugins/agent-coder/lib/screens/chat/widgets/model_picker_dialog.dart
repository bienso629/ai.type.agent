import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../core/widgets/tadu_dialog.dart';
import '../../../providers/server_provider.dart';

class ModelPickerDialog extends StatefulWidget {
  final ServerProvider serverProvider;
  const ModelPickerDialog({super.key, required this.serverProvider});

  static void show(BuildContext context, ServerProvider serverProvider) {
    showDialog(
      context: context,
      builder: (ctx) => ModelPickerDialog(serverProvider: serverProvider),
    );
  }

  static void showCustomModelDialog(BuildContext context, ServerProvider serverProvider) {
    final ctrl = TextEditingController(text: serverProvider.currentAiModel);
    showDialog(
      context: context,
      builder: (ctx) => TaduDialog(
        minWidth: 380,
        maxWidth: 440,
        title: const Row(
          children: [
            Icon(Icons.tune_rounded, size: 20, color: AppColors.primaryLight),
            SizedBox(width: 8),
            Text('Nhập AI Model / CLI Agent'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Nhập tên Model API hoặc lệnh CLI đã cài trên máy:',
              style: TextStyle(fontSize: 12, color: AppColors.textMuted),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: ctrl,
              autofocus: true,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 13, color: AppColors.textWhite),
              decoration: const InputDecoration(
                hintText: 'Ví dụ: antigravity-cli, claude-cli, ollama:llama3...',
                hintStyle: TextStyle(fontSize: 11.5, color: AppColors.textDim),
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

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final serverProvider = widget.serverProvider;
    final currentModel = serverProvider.currentAiModel;

    // Filter CLI agents
    final q = _searchQuery.toLowerCase();
    final filteredCliAgents = serverProvider.installedCliAgents.where((a) {
      if (q.isEmpty) return true;
      return a.id.toLowerCase().contains(q) || a.label.toLowerCase().contains(q);
    }).toList();

    // Filter Cloud models
    final allCloudModels = serverProvider.remoteModels.isNotEmpty
        ? serverProvider.remoteModels
        : ['glm-5.3', 'gpt-4o', 'deepseek-chat', 'claude-3-7-sonnet'];

    final filteredCloudModels = allCloudModels.where((m) {
      if (q.isEmpty) return true;
      return m.toLowerCase().contains(q);
    }).toList();

    return Dialog(
      backgroundColor: AppColors.cardBg,
      elevation: 24,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(4),
        side: const BorderSide(color: AppColors.borderDark, width: 1),
      ),
      child: Container(
        width: 560,
        height: 620,
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
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Chọn AI Agent & Model',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.textWhite),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Chuyển đổi giữa Local CLI Agents và Cloud API Models',
                        style: TextStyle(fontSize: 11, color: AppColors.textMuted),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 18, color: AppColors.textMuted),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // 2. Search Box
            Container(
              height: 38,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: AppColors.inputBg,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: AppColors.borderDark),
              ),
              child: Row(
                children: [
                  const Icon(Icons.search_rounded, size: 16, color: AppColors.textMuted),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _searchCtrl,
                      onChanged: (val) => setState(() => _searchQuery = val.trim()),
                      style: const TextStyle(fontSize: 12.5, color: AppColors.textWhite),
                      decoration: const InputDecoration(
                        hintText: 'Tìm kiếm Agent CLI hoặc Model AI...',
                        hintStyle: TextStyle(fontSize: 12, color: AppColors.textMuted),
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        isCollapsed: true,
                      ),
                    ),
                  ),
                  if (_searchQuery.isNotEmpty)
                    InkWell(
                      onTap: () => setState(() {
                        _searchCtrl.clear();
                        _searchQuery = '';
                      }),
                      child: const Padding(
                        padding: EdgeInsets.all(4),
                        child: Icon(Icons.clear_rounded, size: 14, color: AppColors.textDim),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // 3. Model Sections (Scrollable)
            Expanded(
              child: ListView(
                children: [
                  // --- SECTION 1: INSTALLED CLI AGENTS ---
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.terminal_rounded, size: 14, color: AppColors.accent),
                          SizedBox(width: 6),
                          Text(
                            'LOCAL CLI AGENTS (HỆ THỐNG)',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.5,
                              color: AppColors.accent,
                            ),
                          ),
                        ],
                      ),
                      if (serverProvider.installedCliAgents.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.accent.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '${serverProvider.installedCliAgents.length} đã cài đặt',
                            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.accent),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  if (serverProvider.isScanningCliAgents)
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: Center(
                        child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accent),
                        ),
                      ),
                    )
                  else if (filteredCliAgents.isNotEmpty)
                    ...filteredCliAgents.map((agent) {
                      final isSel = currentModel == agent.id;
                      final verStr = agent.version != null ? ' • v${agent.version}' : '';
                      return _buildModelCard(
                        title: agent.label,
                        subtitle: '${agent.path}$verStr',
                        icon: Icons.terminal_rounded,
                        isSelected: isSel,
                        onTap: () {
                          serverProvider.setActiveAgent(agent.id);
                          Navigator.pop(context);
                          AppToast.success(context, 'Đã kích hoạt CLI Agent: ${agent.label}');
                        },
                      );
                    })
                  else ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.inputBg,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: AppColors.borderDark),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.info_outline_rounded, size: 16, color: AppColors.textMuted),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Không tìm thấy Local CLI agent nào phù hợp.',
                              style: TextStyle(fontSize: 11.5, color: AppColors.textMuted),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  const SizedBox(height: 18),

                  // --- SECTION 2: CLOUD API MODELS ---
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.cloud_queue_rounded, size: 14, color: AppColors.primaryLight),
                            SizedBox(width: 6),
                            Text(
                              'CLOUD API MODELS',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.5,
                                color: AppColors.primaryLight,
                              ),
                            ),
                          ],
                        ),
                        IconButton(
                          icon: const Icon(Icons.refresh_rounded, size: 14, color: AppColors.textDim),
                          tooltip: 'Làm mới danh sách models từ Server',
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
                          onPressed: () {
                            serverProvider.fetchModels(forceRefresh: true);
                          },
                        ),
                      ],
                    ),
                  ),

                  if (serverProvider.isLoadingModels)
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: Center(
                        child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primaryLight),
                        ),
                      ),
                    )
                  else if (filteredCloudModels.isNotEmpty)
                    ...filteredCloudModels.map((m) {
                      final isSel = currentModel == m;
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
                      } else if (m.contains('qwen')) {
                        icon = Icons.hub_rounded;
                      }

                      return _buildModelCard(
                        title: m,
                        subtitle: 'Cloud API Model',
                        icon: icon,
                        isSelected: isSel,
                        onTap: () {
                          serverProvider.setActiveAgent(m);
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
        color: isSelected ? AppColors.primary.withValues(alpha: 0.12) : AppColors.inputBg,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: isSelected ? AppColors.primaryLight : AppColors.borderDark,
          width: isSelected ? 1.2 : 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(4),
          onTap: onTap,
          hoverColor: AppColors.primary.withValues(alpha: 0.08),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            child: Row(
              children: [
                Icon(icon, size: 16, color: isSelected ? AppColors.accent : AppColors.textMuted),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                          color: isSelected ? AppColors.accent : AppColors.textWhite,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 10, color: AppColors.textMuted),
                      ),
                    ],
                  ),
                ),
                if (isSelected) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.accent.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: AppColors.accent, width: 0.8),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.check_rounded, size: 12, color: AppColors.accent),
                        SizedBox(width: 4),
                        Text(
                          'ĐANG CHỌN',
                          style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: AppColors.accent),
                        ),
                      ],
                    ),
                  ),
                ] else ...[
                  const Icon(Icons.chevron_right_rounded, size: 16, color: AppColors.textDim),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
