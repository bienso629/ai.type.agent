import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/server_provider.dart';
import '../theme/app_theme.dart';

class AppLogoWidget extends StatelessWidget {
  final double width;
  final double height;
  final double borderRadius;
  final BoxFit fit;
  final Widget? fallback;

  const AppLogoWidget({
    super.key,
    this.width = 36,
    this.height = 36,
    this.borderRadius = 6,
    this.fit = BoxFit.cover,
    this.fallback,
  });

  @override
  Widget build(BuildContext context) {
    final serverProvider = context.watch<ServerProvider>();
    final customPath = serverProvider.customLogoPath;

    Widget defaultFallback() {
      return fallback ??
          Container(
            width: width,
            height: height,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(borderRadius),
              border: Border.all(color: AppColors.primary.withValues(alpha: 0.4)),
            ),
            child: Icon(Icons.cloud_sync_rounded, color: AppColors.primaryLight, size: width * 0.55),
          );
    }

    Widget imageContent;

    if (customPath != null && customPath.trim().isNotEmpty && !kIsWeb) {
      final trimmed = customPath.trim();
      final file = File(trimmed);
      if (file.existsSync()) {
        imageContent = Image.file(
          file,
          width: width,
          height: height,
          fit: fit,
          errorBuilder: (context, error, stackTrace) => Image.asset(
            'assets/icon.png',
            width: width,
            height: height,
            fit: fit,
            errorBuilder: (ctx, err, st) => defaultFallback(),
          ),
        );
      } else {
        imageContent = Image.asset(
          'assets/icon.png',
          width: width,
          height: height,
          fit: fit,
          errorBuilder: (ctx, err, st) => defaultFallback(),
        );
      }
    } else {
      imageContent = Image.asset(
        'assets/icon.png',
        width: width,
        height: height,
        fit: fit,
        errorBuilder: (ctx, err, st) => defaultFallback(),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: imageContent,
    );
  }
}
