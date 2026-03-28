import 'package:flutter/foundation.dart';

class PerformanceLogger {
  static void log(String marker, Duration duration, {String? details}) {
    final suffix = details == null ? '' : ' | $details';
    debugPrint('[perf] $marker: ${duration.inMilliseconds}ms$suffix');
  }
}
