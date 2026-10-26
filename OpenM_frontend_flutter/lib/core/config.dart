import 'backend_settings.dart';

class AppConfig {
  // Single source of truth for backend connection values.
  static String get apiBaseUrl => BackendSettings.baseUrl;

  static Duration get connectTimeout =>
      const Duration(milliseconds: BackendSettings.connectTimeoutMs);

  static Duration get receiveTimeout =>
      const Duration(milliseconds: BackendSettings.receiveTimeoutMs);

  static Duration get sendTimeout =>
      const Duration(milliseconds: BackendSettings.sendTimeoutMs);
}
