import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;

/// Production cloud backend (Render).
class ApiConfig {
  static const String productionBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://myresult-zu6v.onrender.com',
  );

  static String get baseUrl => productionBaseUrl.replaceAll(RegExp(r'/$'), '');

  static const Duration timeout = Duration(seconds: 45);
  static const Duration restoreTimeout = Duration(seconds: 60);

  static Future<void> init() async {
    debugPrint('API base URL: $baseUrl');
    try {
      await http
          .get(Uri.parse('$baseUrl/health'))
          .timeout(const Duration(seconds: 60));
    } catch (_) {}
  }
}
