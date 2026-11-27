import 'dart:io';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/services/storage_service.dart';
import '../../core/theme/app_theme.dart';

/// Màn hình quét mã QR từ camera để ghép nối App Phụ với App Chính trong 1 chạm.
class QrScannerScreen extends StatefulWidget {
  const QrScannerScreen({super.key});

  static bool get isCameraScanSupported => Platform.isAndroid || Platform.isIOS;

  @override
  State<QrScannerScreen> createState() => _QrScannerScreenState();
}

class _QrScannerScreenState extends State<QrScannerScreen> {
  final MobileScannerController _controller = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
    detectionSpeed: DetectionSpeed.normal,
  );
  bool _handled = false;
  bool _torchOn = false;
  String? _statusHint;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onBarcodeDetected(BarcodeCapture capture) {
    if (_handled) return;
    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue?.trim() ?? '';
      if (raw.isEmpty) continue;
      final parsed = StorageService.parsePairingString(raw);
      if (parsed.url.isNotEmpty) {
        _handled = true;
        _controller.stop();
        Navigator.of(context).pop<String>(raw);
        return;
      } else {
        setState(() {
          _statusHint = 'Mã QR này không phải mã ghép nối của AI Type Agent.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!QrScannerScreen.isCameraScanSupported) {
      return Scaffold(
        backgroundColor: AppColors.bgDark,
        appBar: AppBar(
          title: const Text('Quét mã QR ghép nối'),
          backgroundColor: AppColors.sidebarBg,
        ),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Quét camera trực tiếp hỗ trợ trên điện thoại Android / iOS. Trên máy tính, hãy dùng nút "Tìm máy tính gần đây" hoặc dán chuỗi ghép nối.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textMuted, fontSize: 13),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            controller: _controller,
            tapToFocus: true,
            onDetect: _onBarcodeDetected,
            errorBuilder: (ctx, error) {
              return Container(
                color: AppColors.bgDark,
                padding: const EdgeInsets.all(24),
                alignment: Alignment.center,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.no_photography_rounded, size: 42, color: AppColors.warning),
                    const SizedBox(height: 12),
                    Text(
                      'Không thể mở camera: ${error.errorDetails?.message ?? error.errorCode.name}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: AppColors.textWhite, fontSize: 13),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Hãy cấp quyền Camera cho AI Type Agent trong cài đặt điện thoại rồi thử lại.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.textMuted, fontSize: 12),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Quay lại'),
                    ),
                  ],
                ),
              );
            },
          ),
          // Lớp phủ tối xung quanh khung ngắm QR
          IgnorePointer(
            child: Center(
              child: Container(
                width: 248,
                height: 248,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.primaryLight, width: 2.5),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primary.withValues(alpha: 0.28),
                      blurRadius: 18,
                      spreadRadius: 2,
                    ),
                  ],
                ),
              ),
            ),
          ),
          // Thanh tiêu đề trên cùng
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Row(
                    children: [
                      IconButton(
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.black.withValues(alpha: 0.55),
                        ),
                        icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text(
                          'Quét mã QR trên App Chính',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            shadows: [Shadow(color: Colors.black, blurRadius: 6)],
                          ),
                        ),
                      ),
                      IconButton(
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.black.withValues(alpha: 0.55),
                        ),
                        icon: Icon(
                          _torchOn ? Icons.flash_on_rounded : Icons.flash_off_rounded,
                          color: _torchOn ? AppColors.warning : Colors.white,
                        ),
                        onPressed: () async {
                          await _controller.toggleTorch();
                          if (mounted) {
                            setState(() => _torchOn = !_torchOn);
                          }
                        },
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                Container(
                  margin: const EdgeInsets.fromLTRB(20, 0, 20, 28),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.72),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: AppColors.borderLight.withValues(alpha: 0.6)),
                  ),
                  child: Text(
                    _statusHint ??
                        'Hướng camera vào mã QR đang hiển thị ở mục Cấu hình trên máy tính (App Chính) để kết nối tự động.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: _statusHint != null ? AppColors.warning : AppColors.textWhite,
                      fontSize: 12,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
