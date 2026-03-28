class SafeParsing {
  static Map<String, dynamic> asMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) {
      return value.map((key, val) => MapEntry(key.toString(), val));
    }
    return <String, dynamic>{};
  }

  static List<dynamic> asList(dynamic value) {
    if (value is List) return value;
    return const <dynamic>[];
  }

  static List<dynamic> asListFlexible(dynamic value) {
    if (value is List) return value;
    if (value is Map) return value.values.toList();
    return const <dynamic>[];
  }

  static int asInt(dynamic value, {int fallback = 0}) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value.trim()) ?? fallback;
    return fallback;
  }

  static String asString(dynamic value, {String fallback = ''}) {
    if (value == null) return fallback;
    final text = value.toString().trim();
    return text.isEmpty ? fallback : text;
  }

  static String? normalizeBackdropUrl(dynamic rawValue) {
    if (rawValue == null) return null;

    if (rawValue is List) {
      for (final item in rawValue) {
        final normalized = normalizeBackdropUrl(item);
        if (normalized != null) return normalized;
      }
      return null;
    }

    var text = rawValue.toString().trim();
    if (text.isEmpty) return null;

    if (text.startsWith('[') && text.endsWith(']')) {
      text = text.substring(1, text.length - 1).trim();
    }

    if ((text.startsWith('"') && text.endsWith('"')) ||
        (text.startsWith("'") && text.endsWith("'"))) {
      text = text.substring(1, text.length - 1).trim();
    }

    if (text.isEmpty) return null;

    if (text.contains(',')) {
      for (final piece in text.split(',')) {
        final normalized = normalizeBackdropUrl(piece.trim());
        if (normalized != null) return normalized;
      }
      return null;
    }

    final uri = Uri.tryParse(text);
    final hasValidScheme = uri != null && (uri.scheme == 'http' || uri.scheme == 'https');
    if (!hasValidScheme || !(uri?.hasAuthority ?? false)) {
      return null;
    }

    return text;
  }
}
