import 'dart:io';
import 'package:flutter/services.dart';

class BankListenerStatus {
  final bool isAndroid;
  final bool permissionGranted;
  final bool enabled;
  final String webhookUrl;
  final bool hasSecret;
  final String allowedSenders;
  final bool listenSmsApps;
  final int sdkInt;
  final List<Map<String, dynamic>> logs;

  const BankListenerStatus({
    required this.isAndroid,
    required this.permissionGranted,
    required this.enabled,
    required this.webhookUrl,
    required this.hasSecret,
    required this.allowedSenders,
    required this.listenSmsApps,
    required this.sdkInt,
    required this.logs,
  });

  factory BankListenerStatus.unsupported() => const BankListenerStatus(
        isAndroid: false,
        permissionGranted: false,
        enabled: false,
        webhookUrl: 'https://apiv3.type.vn/v1/payment/bank-sms',
        hasSecret: false,
        allowedSenders: 'Vietcombank,VCB,VCB Digibank',
        listenSmsApps: true,
        sdkInt: 0,
        logs: [],
      );

  factory BankListenerStatus.fromMap(Map<dynamic, dynamic> map) {
    final rawLogs = (map['logs'] as List<dynamic>?) ?? const [];
    final parsedLogs = rawLogs
        .whereType<Map>()
        .map((e) => e.map((k, v) => MapEntry(k.toString(), v)))
        .toList();

    return BankListenerStatus(
      isAndroid: map['isAndroid'] == true,
      permissionGranted: map['permissionGranted'] == true,
      enabled: map['enabled'] == true,
      webhookUrl: (map['webhookUrl'] ?? 'https://apiv3.type.vn/v1/payment/bank-sms').toString(),
      hasSecret: map['hasSecret'] == true,
      allowedSenders: (map['allowedSenders'] ?? 'Vietcombank,VCB,VCB Digibank').toString(),
      listenSmsApps: map['listenSmsApps'] != false,
      sdkInt: (map['sdkInt'] as num?)?.toInt() ?? 0,
      logs: parsedLogs,
    );
  }
}

class BankNotificationBridge {
  static const MethodChannel _channel = MethodChannel('ai_type_agent/bank_listener');

  static bool get isSupported => Platform.isAndroid;

  static Future<BankListenerStatus> getStatus() async {
    if (!isSupported) return BankListenerStatus.unsupported();
    try {
      final res = await _channel.invokeMethod<Map<dynamic, dynamic>>('getStatus');
      if (res == null) return BankListenerStatus.unsupported();
      return BankListenerStatus.fromMap(res);
    } catch (_) {
      return BankListenerStatus.unsupported();
    }
  }

  static Future<bool> openNotificationSettings() async {
    if (!isSupported) return false;
    try {
      return await _channel.invokeMethod<bool>('openNotificationSettings') ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> openAppDetailsSettings() async {
    if (!isSupported) return false;
    try {
      return await _channel.invokeMethod<bool>('openAppDetailsSettings') ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<BankListenerStatus> saveConfig({
    required bool enabled,
    required String webhookUrl,
    String? webhookSecret,
    required String allowedSenders,
    required bool listenSmsApps,
  }) async {
    if (!isSupported) return BankListenerStatus.unsupported();
    final res = await _channel.invokeMethod<Map<dynamic, dynamic>>('saveConfig', {
      'enabled': enabled,
      'webhookUrl': webhookUrl,
      if (webhookSecret != null && webhookSecret.trim().isNotEmpty)
        'webhookSecret': webhookSecret.trim(),
      'allowedSenders': allowedSenders,
      'listenSmsApps': listenSmsApps,
    });
    if (res == null) return BankListenerStatus.unsupported();
    return BankListenerStatus.fromMap(res);
  }

  static Future<void> clearLogs() async {
    if (!isSupported) return;
    try {
      await _channel.invokeMethod<bool>('clearLogs');
    } catch (_) {}
  }

  static Future<Map<String, dynamic>> sendTestForward({
    required String sender,
    required String message,
  }) async {
    if (!isSupported) {
      return {'ok': false, 'httpCode': 0, 'response': 'Chỉ hỗ trợ trên Android'};
    }
    final res = await _channel.invokeMethod<Map<dynamic, dynamic>>('sendTestForward', {
      'sender': sender,
      'message': message,
    });
    if (res == null) {
      return {'ok': false, 'httpCode': 0, 'response': 'Không nhận được phản hồi'};
    }
    return res.map((k, v) => MapEntry(k.toString(), v));
  }
}
