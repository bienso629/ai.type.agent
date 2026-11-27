import 'package:flutter/material.dart';
import 'package:qr/qr.dart';

/// Widget vẽ mã QR ghép nối trực tiếp bằng `CustomPaint` (thuần Dart/Flutter,
/// chạy mượt trên Linux, Windows, macOS, Android và iOS không cần thư viện native).
class PairingQrWidget extends StatelessWidget {
  final String data;
  final double size;
  final Color foregroundColor;
  final Color backgroundColor;

  const PairingQrWidget({
    super.key,
    required this.data,
    this.size = 164,
    this.foregroundColor = const Color(0xFF0B0F19),
    this.backgroundColor = Colors.white,
  });

  @override
  Widget build(BuildContext context) {
    final trimmed = data.trim();
    if (trimmed.isEmpty) {
      return SizedBox(width: size, height: size);
    }

    QrImage? qrImage;
    try {
      final qrCode = QrCode.fromData(
        data: trimmed,
        errorCorrectLevel: QrErrorCorrectLevel.M,
      );
      qrImage = QrImage(qrCode);
    } catch (_) {
      qrImage = null;
    }

    if (qrImage == null) {
      return Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(6),
        ),
        child: const Text(
          'Không tạo được QR',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 11, color: Colors.black54),
        ),
      );
    }

    return Container(
      width: size,
      height: size,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(6),
      ),
      child: CustomPaint(
        painter: _QrPainter(
          qrImage: qrImage,
          foregroundColor: foregroundColor,
        ),
      ),
    );
  }
}

class _QrPainter extends CustomPainter {
  final QrImage qrImage;
  final Color foregroundColor;

  _QrPainter({
    required this.qrImage,
    required this.foregroundColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final count = qrImage.moduleCount;
    if (count <= 0) return;

    final paint = Paint()
      ..color = foregroundColor
      ..style = PaintingStyle.fill
      ..isAntiAlias = false;

    final moduleSize = size.width / count;
    // Bổ sung 0.35px chồng khít giữa các ô vuông liền kề để tránh đường kẻ trắng mảnh khi phóng to/thu nhỏ
    final drawSize = moduleSize + 0.35;

    for (var row = 0; row < count; row++) {
      for (var col = 0; col < count; col++) {
        if (qrImage.isDark(row, col)) {
          canvas.drawRect(
            Rect.fromLTWH(
              col * moduleSize,
              row * moduleSize,
              drawSize,
              drawSize,
            ),
            paint,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _QrPainter oldDelegate) =>
      oldDelegate.qrImage != qrImage || oldDelegate.foregroundColor != foregroundColor;
}
