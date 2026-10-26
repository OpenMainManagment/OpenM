class BackendSettings {
  // Change these values if backend host/port changes.
  static const String protocol = 'http';
  static const String host = '127.0.0.1';
  static const int port = 8002;
  static const String apiPathPrefix = '';

  // HTTP client timeout settings.
  static const int connectTimeoutMs = 15000;
  static const int receiveTimeoutMs = 30000;
  static const int sendTimeoutMs = 30000;

  // Set at build time for server deployments, e.g.
  // --dart-define=API_BASE_URL=/api (same origin, behind a reverse proxy).
  static const String _configuredBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
  );

  static String get baseUrl {
    if (_configuredBaseUrl.isNotEmpty) {
      return _configuredBaseUrl.endsWith('/')
          ? _configuredBaseUrl.substring(0, _configuredBaseUrl.length - 1)
          : _configuredBaseUrl;
    }
    final prefix = apiPathPrefix.trim();
    final normalizedPrefix = prefix.isEmpty
        ? ''
        : prefix.startsWith('/')
        ? prefix
        : '/$prefix';
    return '$protocol://$host:$port$normalizedPrefix';
  }
}
