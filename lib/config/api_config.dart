import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:http/http.dart' as http;

/// Production cloud backend (Render).
class ApiConfig {
  static const String productionBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://myresult-zu6v.onrender.com',
  );

  /// Web app served from API host uses same origin; local `flutter run -d chrome` uses cloud API.
  static String get baseUrl {
    const envUrl = String.fromEnvironment('API_BASE_URL', defaultValue: '');
    if (envUrl.isNotEmpty) {
      return envUrl.replaceAll(RegExp(r'/$'), '');
    }
    if (kIsWeb) {
      final host = Uri.base.host;
      if (host != 'localhost' && host != '127.0.0.1' && Uri.base.hasScheme) {
        return Uri.base.origin;
      }
    }
    return productionBaseUrl.replaceAll(RegExp(r'/$'), '');
  }

  static const Duration timeout = Duration(seconds: 45);
  static const Duration loginTimeout = Duration(seconds: 20);
  static const Duration restoreTimeout = Duration(seconds: 60);

  static Future<void> init() async {
    debugPrint('API base URL: $baseUrl');
    try {
      await http
          .get(Uri.parse('$baseUrl/health'))
          .timeout(const Duration(seconds: 4));
    } catch (_) {}
  }
}
