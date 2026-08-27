import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class TaduDialog extends StatelessWidget {
  final Widget title;
  final Widget content;
  final List<Widget>? actions;
  final double minWidth;
  final double maxWidth;
  final double? maxHeight;
  final VoidCallback? onClose;

  const TaduDialog({
    super.key,
    required this.title,
    required this.content,
    this.actions,
    this.minWidth = 500,
    this.maxWidth = 620,
    this.maxHeight,
    this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.cardBg,
      elevation: 20,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(4),
        side: const BorderSide(color: AppColors.borderDark, width: 1),
      ),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minWidth: minWidth,
          maxWidth: maxWidth,
          maxHeight: maxHeight ?? MediaQuery.of(context).size.height * 0.85,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 1. MODAL HEADER (Border Bottom Separator)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              decoration: const BoxDecoration(
                color: AppColors.cardBg,
                border: Border(
                  bottom: BorderSide(color: AppColors.borderDark, width: 1),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  DefaultTextStyle(
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textWhite,
                    ),
                    child: title,
                  ),
                  IconButton(
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                    icon: const Icon(Icons.close_rounded, size: 18, color: AppColors.textDim),
                    tooltip: 'Đóng',
                    onPressed: onClose ?? () => Navigator.pop(context),
                  ),
                ],
              ),
            ),

            // 2. MODAL BODY (Scrollable if needed)
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: content,
              ),
            ),

            // 3. MODAL FOOTER (Border Top Separator)
            if (actions != null && actions!.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                decoration: const BoxDecoration(
                  color: AppColors.sidebarBg,
                  border: Border(
                    top: BorderSide(color: AppColors.borderDark, width: 1),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    for (int i = 0; i < actions!.length; i++) ...[
                      if (i > 0) const SizedBox(width: 10),
                      actions![i],
                    ],
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
