import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../core/services/persona_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_toast.dart';
import '../../core/widgets/tadu_dialog.dart';
import '../../models/persona_profile_model.dart';
import '../../models/schedule_task_model.dart';
import '../../providers/schedule_provider.dart';
import '../../providers/server_provider.dart';

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  DateTime _currentMonth = DateTime(DateTime.now().year, DateTime.now().month, 1);
  final PersonaService _personaService = PersonaService();
  Map<String, PersonaProfile> _personasMap = {};

  @override
  void initState() {
    super.initState();
    _loadPersonas();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ScheduleProvider>().loadTasks();
    });
  }

  Future<void> _loadPersonas() async {
    final list = await _personaService.loadSavedPersonas();
    if (mounted) {
      setState(() {
        _personasMap = list;
      });
    }
  }

  void _prevMonth() {
    setState(() {
      _currentMonth = DateTime(_currentMonth.year, _currentMonth.month - 1, 1);
    });
  }

  void _nextMonth() {
    setState(() {
      _currentMonth = DateTime(_currentMonth.year, _currentMonth.month + 1, 1);
    });
  }

  void _goToToday() {
    final now = DateTime.now();
    setState(() {
      _currentMonth = DateTime(now.year, now.month, 1);
    });
    context.read<ScheduleProvider>().setSelectedDate(DateTime(now.year, now.month, now.day));
  }

  void _showCreateTaskDialog(BuildContext context, {DateTime? initialDate}) {
    final scheduleProvider = context.read<ScheduleProvider>();
    final targetDate = initialDate ?? scheduleProvider.selectedDate;

    final titleCtrl = TextEditingController();
    final urlCtrl = TextEditingController();
    final commentCtrl = TextEditingController();
    String taskType = 'like';
    TimeOfDay selectedTime = TimeOfDay.now();
    DateTime chosenDate = targetDate;
    final selectedIps = <String>{};

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (dialogCtx, setDialogState) {
          final allPersonas = _personasMap.values.toList();

          return TaduDialog(
            minWidth: 540,
            maxWidth: 620,
            title: const Row(
              children: [
                Icon(Icons.add_task_rounded, color: AppColors.primaryLight, size: 22),
                SizedBox(width: 8),
                Text('Lên Kế Hoạch Tác Vụ Cho Nhân Vật'),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Tiêu đề
                  const Text('Tiêu đề kế hoạch:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.textWhite)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: titleCtrl,
                    style: const TextStyle(fontSize: 13),
                    decoration: const InputDecoration(
                      hintText: 'Ví dụ: Tương tác clip review sản phẩm mới',
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Loại tác vụ
                  const Text('Loại hành động tự động:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.textWhite)),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    children: [
                      _buildTypeRadio('like', 'Bấm Like / Tim', Icons.favorite_rounded, taskType, (v) => setDialogState(() => taskType = v)),
                      _buildTypeRadio('comment', 'Bình luận kịch bản', Icons.mode_comment_rounded, taskType, (v) => setDialogState(() => taskType = v)),
                      _buildTypeRadio('livestream', 'Xem Livestream', Icons.live_tv_rounded, taskType, (v) => setDialogState(() => taskType = v)),
                      _buildTypeRadio('post', 'Đăng bài viết', Icons.post_add_rounded, taskType, (v) => setDialogState(() => taskType = v)),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // Đường link mục tiêu
                  const Text('Đường dẫn bài viết / video / livestream:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.textWhite)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: urlCtrl,
                    style: const TextStyle(fontSize: 13, fontFamily: 'monospace'),
                    decoration: const InputDecoration(
                      hintText: 'https://www.tiktok.com/@user/video/... hoặc Facebook/Youtube',
                      prefixIcon: Icon(Icons.link_rounded, size: 18),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Nội dung comment nếu chọn comment
                  if (taskType == 'comment') ...[
                    const Text('Nội dung comment (hoặc gợi ý cho AI tự sinh):', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.textWhite)),
                    const SizedBox(height: 6),
                    TextField(
                      controller: commentCtrl,
                      maxLines: 2,
                      style: const TextStyle(fontSize: 13),
                      decoration: const InputDecoration(
                        hintText: 'Nhập nội dung mẫu hoặc chỉ định phong cách bình luận...',
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 14),
                  ],

                  // Thời gian thực thi
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Ngày thực hiện:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.textWhite)),
                            const SizedBox(height: 6),
                            InkWell(
                              onTap: () async {
                                final picked = await showDatePicker(
                                  context: dialogCtx,
                                  initialDate: chosenDate,
                                  firstDate: DateTime.now().subtract(const Duration(days: 30)),
                                  lastDate: DateTime.now().add(const Duration(days: 365)),
                                );
                                if (picked != null) {
                                  setDialogState(() => chosenDate = picked);
                                }
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                decoration: BoxDecoration(
                                  color: AppColors.inputBg,
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(color: AppColors.borderDark),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(Icons.calendar_month_rounded, size: 16, color: AppColors.primaryLight),
                                    const SizedBox(width: 8),
                                    Text(DateFormat('dd/MM/yyyy').format(chosenDate), style: const TextStyle(fontSize: 13)),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Khung giờ bắt đầu:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.textWhite)),
                            const SizedBox(height: 6),
                            InkWell(
                              onTap: () async {
                                final picked = await showTimePicker(
                                  context: dialogCtx,
                                  initialTime: selectedTime,
                                );
                                if (picked != null) {
                                  setDialogState(() => selectedTime = picked);
                                }
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                decoration: BoxDecoration(
                                  color: AppColors.inputBg,
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(color: AppColors.borderDark),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(Icons.schedule_rounded, size: 16, color: AppColors.primaryLight),
                                    const SizedBox(width: 8),
                                    Text(
                                      '${selectedTime.hour.toString().padLeft(2, '0')}:${selectedTime.minute.toString().padLeft(2, '0')}',
                                      style: const TextStyle(fontSize: 13),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // Chọn nhân vật thực hiện
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Phân bổ nhân vật thực hiện (${selectedIps.length}/${allPersonas.length}):',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.textWhite),
                      ),
                      TextButton(
                        onPressed: () {
                          setDialogState(() {
                            if (selectedIps.length == allPersonas.length) {
                              selectedIps.clear();
                            } else {
                              selectedIps.addAll(allPersonas.map((p) => p.ip));
                            }
                          });
                        },
                        child: Text(
                          selectedIps.length == allPersonas.length ? 'Bỏ chọn hết' : 'Chọn tất cả',
                          style: const TextStyle(fontSize: 11, color: AppColors.accentCyan),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Container(
                    constraints: const BoxConstraints(maxHeight: 140),
                    decoration: BoxDecoration(
                      color: AppColors.inputBg,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: AppColors.borderDark),
                    ),
                    child: allPersonas.isEmpty
                        ? const Center(
                            child: Padding(
                              padding: EdgeInsets.all(16),
                              child: Text('Chưa có nhân vật nào trong hệ thống', style: TextStyle(color: AppColors.textDim, fontSize: 12)),
                            ),
                          )
                        : ListView.separated(
                            shrinkWrap: true,
                            itemCount: allPersonas.length,
                            separatorBuilder: (context, index) => const Divider(height: 1, color: AppColors.borderDark),
                            itemBuilder: (context, idx) {
                              final p = allPersonas[idx];
                              final isSelected = selectedIps.contains(p.ip);
                              return InkWell(
                                onTap: () {
                                  setDialogState(() {
                                    if (isSelected) {
                                      selectedIps.remove(p.ip);
                                    } else {
                                      selectedIps.add(p.ip);
                                    }
                                  });
                                },
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                  child: Row(
                                    children: [
                                      Icon(
                                        isSelected ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded,
                                        size: 16,
                                        color: isSelected ? AppColors.primaryLight : AppColors.textDim,
                                      ),
                                      const SizedBox(width: 8),
                                      CircleAvatar(
                                        radius: 9,
                                        backgroundColor: p.gender.toLowerCase() == 'nữ'
                                            ? Colors.pinkAccent.withValues(alpha: 0.3)
                                            : AppColors.accentCyan.withValues(alpha: 0.3),
                                        child: Text(
                                          p.name.isNotEmpty ? p.name[0].toUpperCase() : '?',
                                          style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          p.name,
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                            color: isSelected ? AppColors.textWhite : AppColors.textBody,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogCtx),
                child: const Text('Hủy', style: TextStyle(color: AppColors.textMuted)),
              ),
              ElevatedButton.icon(
                onPressed: () async {
                  final title = titleCtrl.text.trim();
                  final url = urlCtrl.text.trim();
                  if (title.isEmpty) {
                    AppToast.warning(dialogCtx, 'Vui lòng nhập tiêu đề kế hoạch');
                    return;
                  }
                  if (url.isEmpty) {
                    AppToast.warning(dialogCtx, 'Vui lòng nhập link bài viết / video');
                    return;
                  }
                  if (selectedIps.isEmpty) {
                    AppToast.warning(dialogCtx, 'Vui lòng chọn ít nhất 1 nhân vật');
                    return;
                  }

                  final scheduledDateTime = DateTime(
                    chosenDate.year,
                    chosenDate.month,
                    chosenDate.day,
                    selectedTime.hour,
                    selectedTime.minute,
                  );

                  final ok = await scheduleProvider.createTask(
                    title: title,
                    taskType: taskType,
                    targetUrl: url,
                    commentContent: commentCtrl.text.trim(),
                    personaIps: selectedIps.toList(),
                    scheduledTime: scheduledDateTime,
                  );

                  if (dialogCtx.mounted) {
                    Navigator.pop(dialogCtx);
                    if (ok) {
                      setState(() {
                        _currentMonth = DateTime(chosenDate.year, chosenDate.month, 1);
                      });
                      scheduleProvider.setSelectedDate(DateTime(chosenDate.year, chosenDate.month, chosenDate.day));
                      AppToast.success(context, 'Đã lên lịch thành công cho ${selectedIps.length} nhân vật');
                    } else {
                      AppToast.error(context, 'Không thể lưu lịch trình');
                    }
                  }
                },
                icon: const Icon(Icons.check_rounded, size: 16),
                label: const Text('Lưu Kế Hoạch', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildTypeRadio(String type, String label, IconData icon, String currentType, Function(String) onSelect) {
    final isSelected = currentType == type;
    return InkWell(
      onTap: () => onSelect(type),
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary.withValues(alpha: 0.15) : AppColors.cardBg,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: isSelected ? AppColors.primaryLight : AppColors.borderDark,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: isSelected ? AppColors.primaryLight : AppColors.textMuted),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: isSelected ? AppColors.primaryLight : AppColors.textBody,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheduleProvider = context.watch<ScheduleProvider>();
    final serverProvider = context.watch<ServerProvider>();

    return Scaffold(
      backgroundColor: AppColors.bgDark,
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Bên trái: Calendar Grid & Điều hướng tháng
          Expanded(
            flex: 6,
            child: Container(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header Lịch
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.calendar_month_rounded, color: AppColors.primaryLight, size: 22),
                          const SizedBox(width: 8),
                          Text(
                            'Lịch Lên Kế Hoạch MXH (Tháng ${DateFormat('MM/yyyy').format(_currentMonth)})',
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textWhite),
                          ),
                        ],
                      ),
                      Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.chevron_left_rounded, color: AppColors.textBody),
                            onPressed: _prevMonth,
                            tooltip: 'Tháng trước',
                          ),
                          OutlinedButton(
                            onPressed: _goToToday,
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: AppColors.borderDark),
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            ),
                            child: const Text('Hôm nay', style: TextStyle(fontSize: 12, color: AppColors.textWhite)),
                          ),
                          IconButton(
                            icon: const Icon(Icons.chevron_right_rounded, color: AppColors.textBody),
                            onPressed: _nextMonth,
                            tooltip: 'Tháng sau',
                          ),
                          const SizedBox(width: 12),
                          ElevatedButton.icon(
                            onPressed: () => _showCreateTaskDialog(context),
                            icon: const Icon(Icons.add_rounded, size: 16),
                            label: const Text('Tạo Kế Hoạch Mới', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5)),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Bảng ngày trong tuần (T2 - CN)
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      color: AppColors.cardBg,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: AppColors.borderDark),
                    ),
                    child: Row(
                      children: ['Thứ 2', 'Thứ 3', 'Thứ 4', 'Thứ 5', 'Thứ 6', 'Thứ 7', 'Chủ Nhật'].map((dayName) {
                        return Expanded(
                          child: Center(
                            child: Text(
                              dayName,
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.textMuted),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                  const SizedBox(height: 8),

                  // Lưới ngày (Month Days Grid)
                  Expanded(
                    child: _buildMonthCalendarGrid(scheduleProvider),
                  ),
                ],
              ),
            ),
          ),

          // Đường phân cách
          Container(width: 1, color: AppColors.borderDark),

          // Bên phải: Danh sách công việc chi tiết của ngày đang chọn
          Expanded(
            flex: 4,
            child: Container(
              color: AppColors.sidebarBg,
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Tiêu đề ngày chọn
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Kế hoạch ngày ${DateFormat('dd/MM/yyyy').format(scheduleProvider.selectedDate)}',
                            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.textWhite),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${scheduleProvider.tasksForSelectedDate.length} tác vụ được lên lịch',
                            style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
                          ),
                        ],
                      ),
                      IconButton(
                        onPressed: () => _showCreateTaskDialog(context, initialDate: scheduleProvider.selectedDate),
                        icon: const Icon(Icons.add_circle_outline_rounded, color: AppColors.primaryLight, size: 22),
                        tooltip: 'Thêm tác vụ vào ngày này',
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // Bộ lọc nhanh
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _buildFilterChip('all', 'Tất cả', scheduleProvider.filterType, (v) => scheduleProvider.setFilterType(v)),
                        const SizedBox(width: 6),
                        _buildFilterChip('like', 'Like/Tim', scheduleProvider.filterType, (v) => scheduleProvider.setFilterType(v)),
                        const SizedBox(width: 6),
                        _buildFilterChip('comment', 'Bình luận', scheduleProvider.filterType, (v) => scheduleProvider.setFilterType(v)),
                        const SizedBox(width: 6),
                        _buildFilterChip('livestream', 'Livestream', scheduleProvider.filterType, (v) => scheduleProvider.setFilterType(v)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Danh sách các thẻ công việc
                  Expanded(
                    child: scheduleProvider.tasksForSelectedDate.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.event_available_rounded, size: 42, color: AppColors.textDim),
                                const SizedBox(height: 12),
                                const Text('Chưa có lịch trình cho ngày này', style: TextStyle(fontSize: 13, color: AppColors.textMuted)),
                                const SizedBox(height: 8),
                                OutlinedButton.icon(
                                  onPressed: () => _showCreateTaskDialog(context, initialDate: scheduleProvider.selectedDate),
                                  icon: const Icon(Icons.add_rounded, size: 14),
                                  label: const Text('Tạo lịch ngay', style: TextStyle(fontSize: 12)),
                                ),
                              ],
                            ),
                          )
                        : ListView.separated(
                            itemCount: scheduleProvider.tasksForSelectedDate.length,
                            separatorBuilder: (context, index) => const SizedBox(height: 10),
                            itemBuilder: (context, idx) {
                              final task = scheduleProvider.tasksForSelectedDate[idx];
                              return _buildTaskCard(context, task, scheduleProvider, serverProvider);
                            },
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

  Widget _buildMonthCalendarGrid(ScheduleProvider provider) {
    final firstDayOfMonth = DateTime(_currentMonth.year, _currentMonth.month, 1);
    final daysInMonth = DateTime(_currentMonth.year, _currentMonth.month + 1, 0).day;
    // Thứ trong tuần: DateTime.weekday (1: Monday ... 7: Sunday)
    final startingWeekday = firstDayOfMonth.weekday; // 1 = T2, 7 = CN

    final totalSlots = 42; // 6 hàng x 7 ngày
    final today = DateTime.now();

    return GridView.builder(
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 7,
        crossAxisSpacing: 6,
        mainAxisSpacing: 6,
        childAspectRatio: 1.3,
      ),
      itemCount: totalSlots,
      itemBuilder: (context, index) {
        final dayOffset = index - (startingWeekday - 1);
        if (dayOffset < 0 || dayOffset >= daysInMonth) {
          return Container(
            decoration: BoxDecoration(
              color: AppColors.cardBg.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(4),
            ),
          );
        }

        final dayNumber = dayOffset + 1;
        final cellDate = DateTime(_currentMonth.year, _currentMonth.month, dayNumber);
        final isToday = cellDate.year == today.year && cellDate.month == today.month && cellDate.day == today.day;
        final isSelected = cellDate.year == provider.selectedDate.year &&
            cellDate.month == provider.selectedDate.month &&
            cellDate.day == provider.selectedDate.day;

        // Đếm số tác vụ trong ngày này
        final dayTasks = provider.tasks.where((t) {
          return t.scheduledTime.year == cellDate.year &&
              t.scheduledTime.month == cellDate.month &&
              t.scheduledTime.day == cellDate.day;
        }).toList();

        return InkWell(
          onTap: () => provider.setSelectedDate(cellDate),
          borderRadius: BorderRadius.circular(4),
          child: Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: isSelected
                  ? AppColors.primary.withValues(alpha: 0.15)
                  : (isToday ? AppColors.primaryLight.withValues(alpha: 0.05) : AppColors.cardBg),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: isSelected
                    ? AppColors.primary
                    : (isToday ? AppColors.primaryLight.withValues(alpha: 0.4) : AppColors.borderDark),
                width: isSelected ? 1.5 : 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '$dayNumber',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: (isSelected || isToday) ? FontWeight.bold : FontWeight.w500,
                        color: isSelected
                            ? AppColors.primaryLight
                            : (isToday ? AppColors.primaryLight : AppColors.textWhite),
                      ),
                    ),
                    if (dayTasks.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '${dayTasks.length}',
                          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.primaryLight),
                        ),
                      ),
                  ],
                ),
                const Spacer(),
                if (dayTasks.isNotEmpty) ...[
                  Wrap(
                    spacing: 3,
                    children: dayTasks.take(3).map((t) {
                      Color dotColor = AppColors.primaryLight;
                      if (t.taskType == 'comment') dotColor = AppColors.accentCyan;
                      if (t.taskType == 'livestream') dotColor = Colors.purpleAccent;
                      if (t.taskType == 'post') dotColor = AppColors.accent;

                      return Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
                      );
                    }).toList(),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildFilterChip(String type, String label, String currentType, Function(String) onSelect) {
    final isSelected = currentType == type;
    return InkWell(
      onTap: () => onSelect(type),
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary.withValues(alpha: 0.15) : AppColors.cardBg,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: isSelected ? AppColors.primaryLight : AppColors.borderDark),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            color: isSelected ? AppColors.primaryLight : AppColors.textMuted,
          ),
        ),
      ),
    );
  }

  Widget _buildTaskCard(
    BuildContext context,
    ScheduleTaskModel task,
    ScheduleProvider scheduleProvider,
    ServerProvider serverProvider,
  ) {
    Color typeColor = AppColors.primaryLight;
    IconData typeIcon = Icons.favorite_rounded;
    String typeLabel = 'Like / Tim';

    if (task.taskType == 'comment') {
      typeColor = AppColors.accentCyan;
      typeIcon = Icons.mode_comment_rounded;
      typeLabel = 'Bình luận';
    } else if (task.taskType == 'livestream') {
      typeColor = Colors.purpleAccent;
      typeIcon = Icons.live_tv_rounded;
      typeLabel = 'Xem Livestream';
    } else if (task.taskType == 'post') {
      typeColor = AppColors.accent;
      typeIcon = Icons.post_add_rounded;
      typeLabel = 'Đăng bài';
    }

    final isCompleted = task.status == 'completed';
    final isRunning = task.status == 'running';

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: isRunning ? AppColors.primary : AppColors.borderDark,
          width: isRunning ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: typeColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: typeColor.withValues(alpha: 0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(typeIcon, size: 12, color: typeColor),
                    const SizedBox(width: 4),
                    Text(typeLabel, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: typeColor)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                DateFormat('HH:mm').format(task.scheduledTime),
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, fontFamily: 'monospace', color: AppColors.textWhite),
              ),
              const Spacer(),
              _buildStatusBadge(task.status),
            ],
          ),
          const SizedBox(height: 8),

          Text(
            task.title,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.textWhite),
          ),
          const SizedBox(height: 4),

          Text(
            task.targetUrl,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11, fontFamily: 'monospace', color: AppColors.textMuted),
          ),

          if (task.commentContent != null && task.commentContent!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.bgDark,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                'Nội dung: ${task.commentContent}',
                style: const TextStyle(fontSize: 11, color: AppColors.textBody, fontStyle: FontStyle.italic),
              ),
            ),
          ],

          const SizedBox(height: 10),
          // Danh sách avatar nhân vật thực hiện
          Row(
            children: [
              Text(
                '${task.personaIps.length} nhân vật: ',
                style: const TextStyle(fontSize: 11, color: AppColors.textDim),
              ),
              Expanded(
                child: SizedBox(
                  height: 22,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: task.personaIps.length,
                    separatorBuilder: (context, index) => const SizedBox(width: 4),
                    itemBuilder: (context, pIdx) {
                      final ip = task.personaIps[pIdx];
                      final p = _personasMap[ip];
                      final initial = (p != null && p.name.isNotEmpty) ? p.name[0].toUpperCase() : '?';
                      return Tooltip(
                        message: p != null ? p.name : ip,
                        child: CircleAvatar(
                          radius: 11,
                          backgroundColor: AppColors.bgDark,
                          child: Text(initial, style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: AppColors.primaryLight)),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ],
          ),

          if (task.resultNote != null && task.resultNote!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              task.resultNote!,
              style: TextStyle(
                fontSize: 11,
                color: isCompleted ? AppColors.accent : AppColors.warning,
              ),
            ),
          ],

          const SizedBox(height: 10),
          const Divider(height: 1, color: AppColors.borderDark),
          const SizedBox(height: 8),

          // Action Buttons
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              IconButton(
                icon: const Icon(Icons.delete_outline_rounded, size: 16, color: AppColors.danger),
                onPressed: () async {
                  if (task.id != null) {
                    await scheduleProvider.deleteTask(task.id!);
                    if (context.mounted) {
                      AppToast.info(context, 'Đã xóa tác vụ lịch trình');
                    }
                  }
                },
                tooltip: 'Xóa tác vụ',
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: isRunning
                    ? null
                    : () async {
                        AppToast.info(context, 'Bắt đầu kích hoạt tác vụ cho các nhân vật...');
                        await scheduleProvider.executeTaskNow(
                          task,
                          defaultServer: serverProvider.selectedServer,
                        );
                        if (context.mounted) {
                          AppToast.success(context, 'Tác vụ đã hoàn tất thực thi');
                        }
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor: isCompleted ? AppColors.cardBg : AppColors.primary,
                  foregroundColor: isCompleted ? AppColors.textWhite : const Color(0xFF070B14),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(4),
                    side: isCompleted ? const BorderSide(color: AppColors.borderDark) : BorderSide.none,
                  ),
                ),
                icon: isRunning
                    ? const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 1.5))
                    : Icon(isCompleted ? Icons.replay_rounded : Icons.play_arrow_rounded, size: 15),
                label: Text(
                  isRunning ? 'Đang chạy...' : (isCompleted ? 'Chạy lại' : 'Kích hoạt ngay'),
                  style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBadge(String status) {
    Color bg = AppColors.bgDark;
    Color fg = AppColors.textMuted;
    String label = 'Đang chờ';

    if (status == 'running') {
      bg = AppColors.primary.withValues(alpha: 0.2);
      fg = AppColors.primaryLight;
      label = 'Đang chạy';
    } else if (status == 'completed') {
      bg = AppColors.accent.withValues(alpha: 0.15);
      fg = AppColors.accent;
      label = 'Hoàn tất';
    } else if (status == 'failed') {
      bg = AppColors.danger.withValues(alpha: 0.15);
      fg = AppColors.danger;
      label = 'Thất bại';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: fg.withValues(alpha: 0.3)),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: fg),
      ),
    );
  }
}
