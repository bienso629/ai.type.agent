import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../../models/attachment_item.dart';

/// Widget bao bọc tệp đính kèm để hiển thị popup preview ảnh khi hover chuột.
class AttachmentHoverPreview extends StatefulWidget {
  final AttachmentItem item;
  final Widget child;

  const AttachmentHoverPreview({
    super.key,
    required this.item,
    required this.child,
  });

  @override
  State<AttachmentHoverPreview> createState() => _AttachmentHoverPreviewState();
}

class _AttachmentHoverPreviewState extends State<AttachmentHoverPreview> {
  OverlayEntry? _overlayEntry;
  final LayerLink _layerLink = LayerLink();

  @override
  void dispose() {
    _removeOverlay();
    super.dispose();
  }

  void _showOverlay() {
    if (!widget.item.isImage) return;
    if (_overlayEntry != null) return;

    final imageWidget = _buildImageWidget();
    if (imageWidget == null) return;

    final overlay = Overlay.of(context, rootOverlay: true);
    _overlayEntry = OverlayEntry(
      builder: (context) {
        return Positioned(
          width: 260,
          child: CompositedTransformFollower(
            link: _layerLink,
            showWhenUnlinked: false,
            offset: const Offset(0, -8),
            targetAnchor: Alignment.topCenter,
            followerAnchor: Alignment.bottomCenter,
            child: IgnorePointer(
              child: Material(
                color: Colors.transparent,
                child: Container(
                  decoration: BoxDecoration(
                    color: AppColors.cardBg,
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                    border: Border.all(
                      color: AppColors.accentCyan.withValues(alpha: 0.6),
                      width: 1.2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.6),
                        blurRadius: 18,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Header hiển thị tên ảnh và kích thước
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        color: AppColors.surfaceDark,
                        child: Row(
                          children: [
                            const Icon(
                              Icons.image_rounded,
                              size: 13,
                              color: AppColors.accentCyan,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                widget.item.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textWhite,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              widget.item.formattedSize,
                              style: const TextStyle(
                                fontSize: 10,
                                color: AppColors.textMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Khung hiển thị ảnh Preview
                      ConstrainedBox(
                        constraints: const BoxConstraints(
                          maxHeight: 220,
                          minHeight: 80,
                        ),
                        child: Container(
                          color: AppColors.bgDark,
                          alignment: Alignment.center,
                          child: imageWidget,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );

    overlay.insert(_overlayEntry!);
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  Widget? _buildImageWidget() {
    final att = widget.item;

    // 1. Dữ liệu Uint8List trong bộ nhớ
    if (att.rawBytes != null && att.rawBytes!.isNotEmpty) {
      return Image.memory(
        att.rawBytes!,
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) => _buildErrorPlaceholder(),
      );
    }

    // 2. Đường dẫn tệp cục bộ trên máy
    if (att.path != null && att.path!.isNotEmpty) {
      final file = File(att.path!);
      if (file.existsSync()) {
        return Image.file(
          file,
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) => _buildErrorPlaceholder(),
        );
      }
    }

    // 3. Chuỗi Base64 Data URI trong content
    if (att.content.isNotEmpty) {
      try {
        final commaIdx = att.content.indexOf(',');
        final base64Str = commaIdx != -1 ? att.content.substring(commaIdx + 1) : att.content;
        final decodedBytes = base64Decode(base64Str);
        return Image.memory(
          decodedBytes,
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) => _buildErrorPlaceholder(),
        );
      } catch (_) {}
    }

    return null;
  }

  Widget _buildErrorPlaceholder() {
    return const Padding(
      padding: EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.broken_image_rounded, size: 28, color: AppColors.textDim),
          SizedBox(height: 6),
          Text(
            'Không tải được ảnh xem trước',
            style: TextStyle(fontSize: 11, color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.item.isImage) {
      return widget.child;
    }

    return CompositedTransformTarget(
      link: _layerLink,
      child: MouseRegion(
        onEnter: (_) => _showOverlay(),
        onExit: (_) => _removeOverlay(),
        child: widget.child,
      ),
    );
  }
}
