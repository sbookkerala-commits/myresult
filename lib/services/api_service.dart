import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';

class ApiService {
  static String? _token;

  static String? get token => _token;

  static Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (_token != null) 'Authorization': 'Bearer $_token',
      };

  static void setToken(String? token) => _token = token;

  static Future<Map<String, dynamic>> login({
    required String username,
    required String password,
  }) async {
    final res = await http
        .post(
          Uri.parse('${ApiConfig.baseUrl}/api/auth/login'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'username': username, 'password': password}),
        )
        .timeout(ApiConfig.timeout);

    final body = jsonDecode(res.body) as Map<String, dynamic>;
    if (res.statusCode != 200) {
      throw ApiException(body['error']?.toString() ?? 'Login failed');
    }
    _token = body['token']?.toString();
    return body;
  }

  static Future<Map<String, dynamic>> restore() async {
    final res = await http
        .get(
          Uri.parse('${ApiConfig.baseUrl}/api/sync/restore'),
          headers: _headers,
        )
        .timeout(ApiConfig.restoreTimeout);
    if (res.statusCode != 200) {
      throw ApiException('Restore failed (${res.statusCode})');
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  static Future<List<Map<String, dynamic>>> getBookings() async {
    final res = await http
        .get(
          Uri.parse('${ApiConfig.baseUrl}/api/bookings'),
          headers: _headers,
        )
        .timeout(ApiConfig.restoreTimeout);
    if (res.statusCode != 200) {
      throw ApiException('Fetch bookings failed (${res.statusCode})');
    }
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final items = data['items'];
    if (items is! List) return [];
    return items
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  static Future<int> postBooking(Map<String, dynamic> payload) async {
    final res = await http
        .post(
          Uri.parse('${ApiConfig.baseUrl}/api/bookings'),
          headers: _headers,
          body: jsonEncode(payload),
        )
        .timeout(ApiConfig.timeout);
    if (res.statusCode >= 400) {
      final decoded = jsonDecode(res.body);
      final msg = decoded is Map ? decoded['error']?.toString() : null;
      throw ApiException(msg ?? 'Booking save failed (${res.statusCode})');
    }
    return res.statusCode;
  }

  static Future<void> deleteBooking(int billNo) async {
    final res = await http
        .delete(
          Uri.parse('${ApiConfig.baseUrl}/api/bookings/$billNo'),
          headers: _headers,
        )
        .timeout(ApiConfig.timeout);
    if (res.statusCode >= 400) {
      throw ApiException('Delete booking failed');
    }
  }

  static Future<void> postSale(Map<String, dynamic> payload) async {
    await _post('/api/sales', payload);
  }

  static Future<void> postResult(Map<String, dynamic> payload) async {
    await _post('/api/results', payload);
  }

  static Future<void> postSettings({
    required String key,
    required dynamic value,
  }) async {
    await _post('/api/settings', {'key': key, 'value': value});
  }

  static Future<void> syncUsers(List<Map<String, dynamic>> users) async {
    await _post('/api/settings', {'users': users});
  }

  static Future<List<Map<String, dynamic>>> getChartArchive() async {
    final res = await http
        .get(
          Uri.parse('${ApiConfig.baseUrl}/api/chart-archive'),
          headers: _headers,
        )
        .timeout(ApiConfig.timeout);
    if (res.statusCode != 200) return [];
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final items = data['items'];
    if (items is! List) return [];
    return items.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  static Future<bool> healthCheck() async {
    try {
      final res = await http
          .get(Uri.parse('${ApiConfig.baseUrl}/health'))
          .timeout(const Duration(seconds: 15));
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  static Future<void> _post(String path, Map<String, dynamic> body) async {
    final res = await http
        .post(
          Uri.parse('${ApiConfig.baseUrl}$path'),
          headers: _headers,
          body: jsonEncode(body),
        )
        .timeout(ApiConfig.timeout);
    if (res.statusCode >= 400) {
      final decoded = jsonDecode(res.body);
      final msg = decoded is Map ? decoded['error']?.toString() : null;
      throw ApiException(msg ?? 'Request failed (${res.statusCode})');
    }
  }
}

class ApiException implements Exception {
  final String message;
  ApiException(this.message);
  @override
  String toString() => message;
}
