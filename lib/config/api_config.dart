import 'package:flutter/foundation.dart' show debugPrint;

/// Production cloud backend (Render).
class ApiConfig {
  static const String productionBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://myresult-api.onrender.com',
  );

  static String get baseUrl => productionBaseUrl.replaceAll(RegExp(r'/$'), '');

  static const Duration timeout = Duration(seconds: 25);

  static Future<void> init() async {
    debugPrint('API base URL: $baseUrl');
  }
}
