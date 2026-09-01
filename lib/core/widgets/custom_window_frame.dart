import 'dart:io';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import '../theme/app_theme.dart';

class CustomWindowFrame extends StatefulWidget {
  final Widget child;
  final String title;

  const CustomWindowFrame({
    super.key,
    required this.child,
    this.title = 'AI Type Agent',
  });

  @override
  State<CustomWindowFrame> createState() => _CustomWindowFrameState();
}

class _CustomWindowFrameState extends State<CustomWindowFrame> with WindowListener {
  bool _isMaximized = false;
  bool _isDesktop = false;

  @override
  void initState() {
    super.initState();
    _isDesktop = Platform.isLinux || Platform.isWindows || Platform.isMacOS;
    if (_isDesktop) {
      windowManager.addListener(this);
      _checkMaximized();
    }
  }

  Future<void> _checkMaximized() async {
    try {
      final max = await windowManager.isMaximized();
      if (mounted) {
        setState(() {
          _isMaximized = max;
        });
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    if (_isDesktop) {
      windowManager.removeListener(this);
    }
    super.dispose();
  }

  @override
  void onWindowMaximize() {
    if (mounted) setState(() => _isMaximized = true);
  }

  @override
  void onWindowUnmaximize() {
    if (mounted) setState(() => _isMaximized = false);
  }

  @override
  Widget build(BuildContext context) {
    if (!_isDesktop) {
      return widget.child;
    }

    // Border radius xl (12.0px) theo chuẩn thiết kế Tailwind/AppTheme khi không phóng to tối đa
    final borderRadius = _isMaximized ? BorderRadius.zero : BorderRadius.circular(12.0);

    return Material(
      type: MaterialType.transparency,
      color: Colors.transparent,
      child: Container(
        color: Colors.transparent,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.transparent,
            borderRadius: borderRadius,
            border: _isMaximized
                ? null
                : Border.all(
                    color: const Color(0xFF000000), // Border màu đen hoàn toàn
                    width: 1.2,
                  ),
          ),
          child: ClipRRect(
            borderRadius: borderRadius,
            clipBehavior: Clip.antiAliasWithSaveLayer,
            child: Container(
              color: AppColors.bgDark,
              child: Column(
                children: [
                  // Custom Window Titlebar with 3 Control Buttons
                  Container(
                    height: 34,
                    decoration: const BoxDecoration(
                      color: AppColors.sidebarBg,
                      border: Border(
                        bottom: BorderSide(color: Color(0xFF000000), width: 0.8), // Viền ngăn cách màu đen
                      ),
                    ),
                    child: Row(
                      children: [
                        // Draggable Area & App Title
                        Expanded(
                          child: DragToMoveArea(
                            child: Container(
                              height: double.infinity,
                              color: Colors.transparent,
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              alignment: Alignment.centerLeft,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    width: 7,
                                    height: 7,
                                    decoration: const BoxDecoration(
                                      color: AppColors.accent,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    widget.title,
                                    style: const TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.textWhite,
                                      letterSpacing: 0.3,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),

                        // 3 Window Control Buttons (Minimize, Maximize/Restore, Close)
                        _WindowButton(
                          icon: Icons.remove_rounded,
                          tooltip: 'Thu nhỏ',
                          onPressed: () => windowManager.minimize(),
                        ),
                        _WindowButton(
                          icon: _isMaximized ? Icons.filter_none_rounded : Icons.crop_square_rounded,
                          tooltip: _isMaximized ? 'Khôi phục kích thước' : 'Phóng to tối đa',
                          size: _isMaximized ? 11.5 : 13,
                          onPressed: () async {
                            if (await windowManager.isMaximized()) {
                              windowManager.unmaximize();
                            } else {
                              windowManager.maximize();
                            }
                          },
                        ),
                        _WindowButton(
                          icon: Icons.close_rounded,
                          tooltip: 'Đóng',
                          isClose: true,
                          onPressed: () => windowManager.close(),
                        ),
                      ],
                    ),
                  ),

                  // Main App Content
                  Expanded(
                    child: ClipRRect(
                      borderRadius: _isMaximized
                          ? BorderRadius.zero
                          : const BorderRadius.only(
                              bottomLeft: Radius.circular(12.0),
                              bottomRight: Radius.circular(12.0),
                            ),
                      clipBehavior: Clip.antiAliasWithSaveLayer,
                      child: widget.child,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _WindowButton extends StatefulWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final bool isClose;
  final double size;

  const _WindowButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.isClose = false,
    this.size = 13,
  });

  @override
  State<_WindowButton> createState() => _WindowButtonState();
}

class _WindowButtonState extends State<_WindowButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    Color bg = Colors.transparent;
    Color iconColor = AppColors.textDim;

    if (_isHovered) {
      bg = widget.isClose ? const Color(0xFFE11D48) : AppColors.cardBg;
      iconColor = widget.isClose ? Colors.white : AppColors.textWhite;
    }

    return Tooltip(
      message: widget.tooltip,
      waitDuration: const Duration(milliseconds: 600),
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: GestureDetector(
          onTap: widget.onPressed,
          child: Container(
            width: 44,
            height: 34,
            alignment: Alignment.center,
            color: bg,
            child: Icon(
              widget.icon,
              size: widget.size,
              color: iconColor,
            ),
          ),
        ),
      ),
    );
  }
}
