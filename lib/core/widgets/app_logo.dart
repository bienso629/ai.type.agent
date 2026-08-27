import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../theme/app_theme.dart';

class AppLogo extends StatelessWidget {
  final double size;
  final double borderRadius;
  final BoxFit fit;

  const AppLogo({
    super.key,
    this.size = 36,
    this.borderRadius = 6,
    this.fit = BoxFit.contain,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: SvgPicture.asset(
        'assets/logo.svg',
        width: size,
        height: size,
        fit: fit,
        placeholderBuilder: (context) => Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(borderRadius),
          ),
          child: Icon(
            Icons.smart_toy_rounded,
            color: AppColors.primaryLight,
            size: size * 0.6,
          ),
        ),
      ),
    );
  }
}
