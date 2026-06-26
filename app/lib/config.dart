library;

class AppConfig {
  /// All cloud routes are versioned under /api/v1.
  static const String apiPrefix = '/api/v1';

  /// Derives the API base from the current page origin at runtime so no
  /// dart-define or rebuild is needed when the deployment URL changes.
  /// Falls back to localhost for local dev.
  static String get apiBase {
    final origin = Uri.base.origin;
    if (origin.isEmpty || origin == 'null') return 'http://localhost:8800';
    return origin;
  }

  static Uri uri(String path, [Map<String, dynamic>? query]) {
    final q = query?.map((k, v) => MapEntry(k, '$v'));
    return Uri.parse('$apiBase$apiPrefix$path').replace(queryParameters: q);
  }
}
