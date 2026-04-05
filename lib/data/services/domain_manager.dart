import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Result of a speed test for a single domain.
class DomainResult {
  final String domain;
  final int? responseTimeMs; // null = failed/unreachable
  final int? statusCode;
  final String? errorMessage;

  const DomainResult({
    required this.domain,
    this.responseTimeMs,
    this.statusCode,
    this.errorMessage,
  });

  bool get isReachable => responseTimeMs != null && statusCode == 200;

  String get displayName {
    final uri = Uri.tryParse(domain);
    return uri?.host ?? domain;
  }

  String get statusLabel {
    if (responseTimeMs == null) return errorMessage ?? 'Unreachable';
    if (statusCode != null && statusCode != 200) {
      return _xtreamErrorLabel(statusCode!);
    }
    return '${responseTimeMs}ms';
  }

  static String _xtreamErrorLabel(int code) {
    switch (code) {
      case 403:
        return '403 Forbidden';
      case 455:
        return '455 IP Not Allowed';
      case 458:
        return '458 Already Connected';
      case 464:
        return '464 DNS Locked';
      case 511:
      case 512:
        return '$code Auth Missing';
      default:
        return 'HTTP $code';
    }
  }
}

/// Singleton that manages domain selection, speed testing, and failover.
class DomainManager {
  DomainManager._();
  static final DomainManager instance = DomainManager._();

  // Domains in priority order (index 0 = highest priority).
  static const List<String> domains = [
    'http://cf.business-cloud-neo.ru',
    'http://cf.rawadiptv.online',
    'http://rawadiptv.online',
  ];

  static const String _prefKey = 'active_domain';

  String _activeDomain = domains[0];

  String get activeDomain => _activeDomain;

  /// Load the last-known-working domain from SharedPreferences.
  Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_prefKey);
      if (saved != null && domains.contains(saved)) {
        _activeDomain = saved;
        debugPrint('[DomainManager] Restored domain: $_activeDomain');
      } else {
        _activeDomain = domains[0];
        debugPrint('[DomainManager] Using default domain: $_activeDomain');
      }
    } catch (e) {
      debugPrint('[DomainManager] init error: $e');
    }
  }

  /// Persist the active domain to SharedPreferences.
  Future<void> setActiveDomain(String domain) async {
    _activeDomain = domain;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefKey, domain);
      debugPrint('[DomainManager] Active domain set to: $domain');
    } catch (e) {
      debugPrint('[DomainManager] setActiveDomain error: $e');
    }
  }

  /// Returns the next domain in the priority list after [current], or null if
  /// [current] is the last domain.
  String? nextDomain(String current) {
    final idx = domains.indexOf(current);
    if (idx >= 0 && idx < domains.length - 1) {
      return domains[idx + 1];
    }
    return null;
  }

  /// Speed-tests all domains concurrently using [username]/[password] to
  /// authenticate against `player_api.php`.
  Future<List<DomainResult>> testAllDomains({
    required String username,
    required String password,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    debugPrint('[DomainManager] Testing ${domains.length} domains…');
    final futures = domains.map(
      (d) => _testDomain(d, username, password, timeout),
    );
    return Future.wait(futures);
  }

  Future<DomainResult> _testDomain(
    String domain,
    String username,
    String password,
    Duration timeout,
  ) async {
    final url =
        '$domain/player_api.php?username=$username&password=$password&action=get_account_info';
    final stopwatch = Stopwatch()..start();
    try {
      final dio = Dio(
        BaseOptions(
          connectTimeout: timeout,
          receiveTimeout: timeout,
          validateStatus: (_) => true,
          headers: {
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
                'AppleWebKit/537.36 (KHTML, like Gecko) '
                'Chrome/120.0.0.0 Safari/537.36',
          },
        ),
      );
      final response = await dio.get(url);
      stopwatch.stop();
      debugPrint(
        '[DomainManager] $domain => ${response.statusCode} '
        'in ${stopwatch.elapsedMilliseconds}ms',
      );
      return DomainResult(
        domain: domain,
        responseTimeMs: stopwatch.elapsedMilliseconds,
        statusCode: response.statusCode,
      );
    } catch (e) {
      stopwatch.stop();
      debugPrint('[DomainManager] $domain => ERROR: $e');
      return DomainResult(
        domain: domain,
        responseTimeMs: null,
        errorMessage: _simplifyError(e),
      );
    }
  }

  /// Tests all domains and sets the fastest reachable (HTTP 200) one as active.
  /// Falls back to [domains[0]] if none work.
  Future<String> selectFastestDomain({
    required String username,
    required String password,
  }) async {
    final results = await testAllDomains(
      username: username,
      password: password,
    );

    final working = results.where((r) => r.isReachable).toList()
      ..sort((a, b) => a.responseTimeMs!.compareTo(b.responseTimeMs!));

    final best = working.isNotEmpty ? working.first.domain : domains[0];
    await setActiveDomain(best);
    debugPrint('[DomainManager] Fastest domain selected: $best');
    return best;
  }

  /// Executes [request] with the active domain. On failure (403, connection
  /// error, timeout) automatically retries with the next domain in the list.
  /// Updates [_activeDomain] when a fallback succeeds.
  ///
  /// [request] receives the domain URL (no trailing slash) to use.
  Future<Response<dynamic>> executeWithFailover(
    Future<Response<dynamic>> Function(String domain) request,
  ) async {
    var domain = _activeDomain;

    while (true) {
      try {
        final response = await request(domain);
        final status = response.statusCode ?? 0;

        // Treat these status codes as hard failures requiring failover.
        if (_isFailoverStatus(status)) {
          debugPrint(
            '[DomainManager] $domain returned HTTP $status — trying next domain',
          );
          final next = nextDomain(domain);
          if (next == null) {
            // No more domains; return the bad response so callers can handle it.
            return response;
          }
          domain = next;
          continue;
        }

        // Success — if we switched domains, persist the working one.
        if (domain != _activeDomain) {
          await setActiveDomain(domain);
        }
        return response;
      } on DioException catch (e) {
        final isNetworkError = e.type == DioExceptionType.connectionTimeout ||
            e.type == DioExceptionType.receiveTimeout ||
            e.type == DioExceptionType.sendTimeout ||
            e.type == DioExceptionType.connectionError;

        final statusCode = e.response?.statusCode ?? 0;

        if (isNetworkError || _isFailoverStatus(statusCode)) {
          debugPrint(
            '[DomainManager] $domain failed (${e.type} / HTTP $statusCode) '
            '— trying next domain',
          );
          final next = nextDomain(domain);
          if (next == null) rethrow; // All domains exhausted.
          domain = next;
        } else {
          rethrow;
        }
      }
    }
  }

  static bool _isFailoverStatus(int status) =>
      status == 403 ||
      status == 455 ||
      status == 458 ||
      status == 464 ||
      status == 511 ||
      status == 512;

  static String _simplifyError(Object e) {
    final s = e.toString();
    if (s.contains('SocketException') || s.contains('connection')) {
      return 'Connection failed';
    }
    if (s.contains('timeout') || s.contains('Timeout')) return 'Timeout';
    return 'Unreachable';
  }
}
