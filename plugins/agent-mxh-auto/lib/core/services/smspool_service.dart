import 'dart:convert';
import 'package:http/http.dart' as http;

class SmsPoolService {
  static final SmsPoolService _instance = SmsPoolService._internal();
  factory SmsPoolService() => _instance;
  SmsPoolService._internal();

  static const String defaultApiKey = 'RJ66sICar3YC0ubDbaoKbLl7zyxUVqIy';
  static const String baseUrl = 'https://api.smspool.net';

  /// Kiểm tra số dư tài khoản SMSPool
  Future<double> checkBalance({String apiKey = defaultApiKey}) async {
    try {
      final res = await http.get(Uri.parse('$baseUrl/request/balance?key=$apiKey')).timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data is Map && data['balance'] != null) {
          return double.tryParse(data['balance'].toString()) ?? 0.0;
        }
      }
    } catch (_) {}
    return 0.0;
  }

  /// Hàm tiện ích loại bỏ toàn bộ thẻ HTML và format khoảng trắng sạch sẽ
  static String stripHtml(String? text) {
    if (text == null) return '';
    return text
        .replaceAll(RegExp(r'<[^>]*>'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  /// Thuê số điện thoại SMSPool
  /// country: 11 (Việt Nam)
  /// service: 924 (TikTok), 329 (Facebook), 907 (Telegram), 1012 (WhatsApp), 1054 (Zalo)
  Future<Map<String, dynamic>> orderSmsNumber({
    String apiKey = defaultApiKey,
    int country = 11,
    int service = 924,
  }) async {
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/purchase/sms'),
        body: {
          'key': apiKey,
          'country': country.toString(),
          'service': service.toString(),
        },
      ).timeout(const Duration(seconds: 20));

      final data = jsonDecode(utf8.decode(res.bodyBytes));
      if (data is Map<String, dynamic>) {
        if (data['message'] != null) {
          data['message'] = stripHtml(data['message'].toString());
        }
        return data;
      }
    } catch (e) {
      return {'success': 0, 'message': 'Lỗi kết nối tới SMSPool: $e'};
    }
    return {'success': 0, 'message': 'Không nhận được dữ liệu từ SMSPool'};
  }

  /// Hủy đơn thuê số và hoàn tiền
  Future<bool> cancelOrder({
    String apiKey = defaultApiKey,
    required String orderId,
  }) async {
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/sms/cancel'),
        body: {
          'key': apiKey,
          'orderid': orderId,
        },
      ).timeout(const Duration(seconds: 10));
      final data = jsonDecode(res.body);
      return data['success'] == 1;
    } catch (_) {
      return false;
    }
  }

  /// Kiểm tra tin nhắn OTP cho đơn thuê
  Future<Map<String, dynamic>> checkSms({
    String apiKey = defaultApiKey,
    required String orderId,
  }) async {
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/sms/check'),
        body: {
          'key': apiKey,
          'orderid': orderId,
        },
      ).timeout(const Duration(seconds: 10));
      final data = jsonDecode(utf8.decode(res.bodyBytes));
      if (data is Map<String, dynamic>) {
        return data;
      }
    } catch (_) {}
    return {'status': 0};
  }
}
