import 'dart:convert';
import 'package:http/http.dart' as http;

class SmsCountry {
  final int id;
  final String name;
  final String shortName;
  final String cc;

  const SmsCountry({
    required this.id,
    required this.name,
    required this.shortName,
    required this.cc,
  });
}

class SmsPoolService {
  static final SmsPoolService _instance = SmsPoolService._internal();
  factory SmsPoolService() => _instance;
  SmsPoolService._internal();

  static const String defaultApiKey = 'RJ66sICar3YC0ubDbaoKbLl7zyxUVqIy';
  static const String baseUrl = 'https://api.smspool.net';

  /// Danh sách các quốc gia phổ biến hỗ trợ thuê số SMSPool
  static const List<SmsCountry> popularCountries = [
    SmsCountry(id: 11, name: 'Việt Nam', shortName: 'VN', cc: '84'),
    SmsCountry(id: 1, name: 'Mỹ (United States)', shortName: 'US', cc: '1'),
    SmsCountry(id: 2, name: 'Anh (United Kingdom)', shortName: 'GB', cc: '44'),
    SmsCountry(id: 9, name: 'Indonesia', shortName: 'ID', cc: '62'),
    SmsCountry(id: 52, name: 'Thái Lan', shortName: 'TH', cc: '66'),
    SmsCountry(id: 12, name: 'Philippines', shortName: 'PH', cc: '63'),
    SmsCountry(id: 20, name: 'Malaysia', shortName: 'MY', cc: '60'),
    SmsCountry(id: 15, name: 'Ấn Độ', shortName: 'IN', cc: '91'),
    SmsCountry(id: 141, name: 'Singapore', shortName: 'SG', cc: '65'),
    SmsCountry(id: 157, name: 'Nhật Bản', shortName: 'JP', cc: '81'),
  ];

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
  Future<Map<String, dynamic>> cancelOrder({
    String apiKey = defaultApiKey,
    required String orderId,
  }) async {
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/sms/cancel'),
        body: {
          'key': apiKey,
          'orderid': orderId.trim(),
        },
      ).timeout(const Duration(seconds: 12));

      String bodyStr = utf8.decode(res.bodyBytes);
      dynamic data;
      try {
        data = jsonDecode(bodyStr);
      } catch (_) {}

      if (data is Map<String, dynamic>) {
        final successVal = data['success'];
        final isSuccess = successVal == 1 || successVal == true;
        String msg = data['message']?.toString() ?? '';
        if (msg.isEmpty && data['errors'] is List && (data['errors'] as List).isNotEmpty) {
          final firstErr = (data['errors'] as List).first;
          if (firstErr is Map && firstErr['message'] != null) {
            msg = firstErr['message'].toString();
          }
        }
        return {
          'success': isSuccess ? 1 : 0,
          'message': msg.isNotEmpty ? msg : (isSuccess ? 'Hủy đơn thành công.' : 'Không thể hủy đơn.'),
        };
      }

      if (res.statusCode >= 200 && res.statusCode < 300) {
        return {'success': 1, 'message': 'Hủy đơn thành công.'};
      }
      return {'success': 0, 'message': 'Mã lỗi máy chủ SMSPool: ${res.statusCode}'};
    } catch (e) {
      return {'success': 0, 'message': 'Lỗi kết nối tới SMSPool: $e'};
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
