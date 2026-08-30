import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../../models/server_model.dart';

/// Avatar hiển thị bên cạnh bong bóng chat hoặc tiêu đề tương ứng với máy chủ.
/// - Agent (Local Machine): Icon laptop/máy tính cá nhân màu xanh lá emerald (AppColors.accent).
/// - Agent (Remote VPS): Icon server/dns màu xanh ngọc teal/cyan (AppColors.primaryLight).
/// - User: Chữ cái đầu từ tên người dùng trên nền gradient.
class ChatAvatar extends StatelessWidget {
  final bool isUser;
  final String? userName;
  final String? serverName;
  final ServerModel? server;
  final bool? isLocal;
  final double size;

  const ChatAvatar({
    super.key,
    this.isUser = false,
    this.userName,
    this.serverName,
    this.server,
    this.isLocal,
    this.size = 30,
  });

  bool get _isLocalServer {
    if (isLocal != null) return isLocal!;
    if (server != null) {
      return server!.id == 'local' ||
          server!.serverIp == '127.0.0.1' ||
          server!.serverIp == 'localhost' ||
          server!.serverIp.isEmpty;
    }
    if (serverName != null && serverName!.isNotEmpty) {
      final s = serverName!.toLowerCase().trim();
      return s == 'local machine' ||
          s == 'local' ||
          s == 'localhost' ||
          s == '127.0.0.1' ||
          s.contains('local');
    }
    return true; // Mặc định là Local Machine nếu không có máy chủ từ xa
  }

  @override
  Widget build(BuildContext context) {
    if (isUser) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF0EA5E9), Color(0xFF6366F1)],
          ),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF6366F1).withValues(alpha: 0.25),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        alignment: Alignment.center,
        child: Text(
          _initials(userName ?? 'Bạn'),
          style: TextStyle(
            fontSize: size * 0.4,
            fontWeight: FontWeight.bold,
            color: Colors.white,
            height: 1.0,
          ),
        ),
      );
    }

    final local = _isLocalServer;
    final iconColor = local ? AppColors.accent : AppColors.primaryLight;
    final bgColor = local
        ? AppColors.accent.withValues(alpha: 0.15)
        : AppColors.primary.withValues(alpha: 0.15);
    final borderColor = local
        ? AppColors.accent.withValues(alpha: 0.4)
        : AppColors.primary.withValues(alpha: 0.4);
    final shadowColor = local
        ? AppColors.accent.withValues(alpha: 0.2)
        : AppColors.primary.withValues(alpha: 0.2);
    final iconData = local ? Icons.laptop_chromebook_rounded : Icons.dns_rounded;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: borderColor),
        boxShadow: [
          BoxShadow(
            color: shadowColor,
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      alignment: Alignment.center,
      child: Icon(
        iconData,
        size: size * 0.58,
        color: iconColor,
      ),
    );
  }

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return 'U';
    if (parts.length == 1) {
      return parts.first.substring(0, 1).toUpperCase();
    }
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1)).toUpperCase();
  }
}

