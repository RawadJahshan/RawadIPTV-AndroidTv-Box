import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import '../../services/domain_manager.dart';

class _MemoryCacheEntry {
  final List<Map<String, dynamic>> data;
  final DateTime cachedAt;
  final Duration ttl;

  const _MemoryCacheEntry({
    required this.data,
    required this.cachedAt,
    required this.ttl,
  });

  bool get isExpired => DateTime.now().difference(cachedAt) > ttl;
}

class XtreamApi {
  late final Dio _dio;
  static final Set<XtreamApi> _instances = <XtreamApi>{};
  final Map<String, _MemoryCacheEntry> _memoryResponseCache = {};

  late String _serverUrl;
  late String _username;
  late String _password;

  static const Duration _categoriesTtl = Duration(minutes: 20);
  static const Duration _categoryItemsTtl = Duration(minutes: 10);
  static const Duration _accountInfoTtl = Duration(minutes: 30);

  XtreamApi() {
    _instances.add(this);
    _dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 30),
        sendTimeout: const Duration(seconds: 10),
        headers: {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
              'AppleWebKit/537.36 (KHTML, like Gecko) '
              'Chrome/120.0.0.0 Safari/537.36',
          'Accept': '*/*',
          'Accept-Language': 'en-US,en;q=0.9',
          'Connection': 'keep-alive',
        },
        // Allow all statuses through — failover logic inspects them.
        validateStatus: (_) => true,
        responseType: ResponseType.json,
      ),
    );

    _dio.interceptors.add(
      InterceptorsWrapper(
        onError: (error, handler) {
          final status = error.response?.statusCode;
          if (status != null) {
            debugPrint('[XtreamApi] HTTP $status — ${_statusDescription(status)}');
          }
          debugPrint('[XtreamApi] Error: ${error.message}');
          handler.next(error);
        },
      ),
    );
  }

  // ─── Credentials ──────────────────────────────────────────────────────────

  void setCredentials({
    required String serverUrl,
    required String username,
    required String password,
  }) {
    // Use the DomainManager's active domain (not the passed serverUrl, which
    // may be stale). The DomainManager is the single source of truth.
    _serverUrl = DomainManager.instance.activeDomain;
    _username = username;
    _password = password;
  }

  String get serverUrl => _serverUrl;
  String get username => _username;
  String get password => _password;

  // Builds the base URL for the current active domain.
  String _buildBaseUrl([String? domain]) =>
      '${domain ?? _serverUrl}/player_api.php?username=$_username&password=$_password';

  // ─── Cache helpers ─────────────────────────────────────────────────────────

  void clearInMemoryCache() => _memoryResponseCache.clear();

  static void clearAllInMemoryCaches() {
    for (final instance in _instances) {
      instance._memoryResponseCache.clear();
    }
    debugPrint(
      '[XtreamApi] Cleared in-memory caches for ${_instances.length} instance(s)',
    );
  }

  // ─── Warm-up ───────────────────────────────────────────────────────────────

  Future<void> warmupLightweightContent({bool forceRefresh = false}) async {
    if (forceRefresh) clearInMemoryCache();
    await Future.wait<void>([
      getAccountInfo(forceRefresh: forceRefresh),
      getLiveCategories(forceRefresh: forceRefresh),
      getVodCategories(forceRefresh: forceRefresh),
      getSeriesCategories(forceRefresh: forceRefresh),
    ]);
  }

  // ─── Authentication ────────────────────────────────────────────────────────

  /// Authenticates against all configured domains in priority order and returns
  /// the result from the first domain that responds successfully.
  Future<Map<String, dynamic>> authenticate(
    String serverUrl,
    String username,
    String password,
  ) async {
    for (final domain in DomainManager.domains) {
      try {
        final url =
            '$domain/player_api.php?username=$username&password=$password'
            '&action=get_account_info';
        debugPrint('[XtreamApi] authenticate => $domain');
        final response = await _dio.get(url);
        final status = response.statusCode ?? 0;

        if (status == 200 && response.data is Map) {
          // Persist the working domain so subsequent calls use it.
          await DomainManager.instance.setActiveDomain(domain);
          _serverUrl = domain;
          return {'success': true, 'data': response.data};
        }

        debugPrint(
          '[XtreamApi] authenticate: $domain returned HTTP $status — '
          '${_statusDescription(status)}',
        );
      } on DioException catch (e) {
        debugPrint('[XtreamApi] authenticate: $domain error: ${e.message}');
      } catch (e) {
        debugPrint('[XtreamApi] authenticate: $domain unexpected error: $e');
      }
    }

    return {
      'success': false,
      'message': 'All servers are unreachable. Please check your connection.',
    };
  }

  // ─── API methods ───────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> getAccountInfo({bool forceRefresh = false}) async {
    final list = await _getListWithCache(
      action: 'get_account_info',
      ttl: _accountInfoTtl,
      forceRefresh: forceRefresh,
    );
    return list.isNotEmpty ? list.first : <String, dynamic>{};
  }

  Future<List<Map<String, dynamic>>> getLiveCategories({bool forceRefresh = false}) async {
    try {
      return await _getListWithCache(
        action: 'get_live_categories',
        ttl: _categoriesTtl,
        forceRefresh: forceRefresh,
      );
    } catch (e) {
      debugPrint('[XtreamApi] getLiveCategories error: $e');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> getLiveStreams({
    int? categoryId,
    bool forceRefresh = false,
  }) async {
    try {
      return await _getListWithCache(
        action: 'get_live_streams',
        categoryId: categoryId,
        options: Options(receiveTimeout: const Duration(seconds: 60)),
        ttl: _categoryItemsTtl,
        forceRefresh: forceRefresh,
      );
    } catch (e) {
      debugPrint('[XtreamApi] getLiveStreams error: $e');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> getVodCategories({bool forceRefresh = false}) async {
    try {
      return await _getListWithCache(
        action: 'get_vod_categories',
        ttl: _categoriesTtl,
        forceRefresh: forceRefresh,
      );
    } catch (e) {
      debugPrint('[XtreamApi] getVodCategories error: $e');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> getVodStreams({
    int? categoryId,
    bool forceRefresh = false,
  }) async {
    try {
      return await _getListWithCache(
        action: 'get_vod_streams',
        categoryId: categoryId,
        options: Options(receiveTimeout: const Duration(seconds: 60)),
        ttl: _categoryItemsTtl,
        forceRefresh: forceRefresh,
      );
    } catch (e) {
      debugPrint('[XtreamApi] getVodStreams error: $e');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> getVodStreamsStrict({
    int? categoryId,
    bool forceRefresh = false,
  }) {
    return _getListWithCache(
      action: 'get_vod_streams',
      categoryId: categoryId,
      options: Options(receiveTimeout: const Duration(seconds: 60)),
      ttl: _categoryItemsTtl,
      forceRefresh: forceRefresh,
    );
  }

  Future<List<Map<String, dynamic>>> getSeriesCategories({bool forceRefresh = false}) async {
    try {
      return await _getListWithCache(
        action: 'get_series_categories',
        ttl: _categoriesTtl,
        forceRefresh: forceRefresh,
      );
    } catch (e) {
      debugPrint('[XtreamApi] getSeriesCategories error: $e');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> getSeries({
    int? categoryId,
    bool forceRefresh = false,
  }) async {
    try {
      return await _getListWithCache(
        action: 'get_series',
        categoryId: categoryId,
        options: Options(receiveTimeout: const Duration(seconds: 60)),
        ttl: _categoryItemsTtl,
        forceRefresh: forceRefresh,
      );
    } catch (e) {
      debugPrint('[XtreamApi] getSeries error: $e');
      return [];
    }
  }

  Future<Map<String, dynamic>> getSeriesInfo(int seriesId) async {
    try {
      final response = await DomainManager.instance.executeWithFailover(
        (domain) => _dio.get(
          '${_buildBaseUrl(domain)}&action=get_series_info&series_id=$seriesId',
        ),
      );
      _updateServerUrlFromResponse(response);
      if (response.data is Map) {
        return Map<String, dynamic>.from(response.data as Map);
      }
      return {};
    } catch (e) {
      debugPrint('[XtreamApi] getSeriesInfo error: $e');
      return {};
    }
  }

  Future<Map<String, dynamic>> getVodInfo(int vodId) async {
    try {
      final response = await DomainManager.instance.executeWithFailover(
        (domain) => _dio.get(
          '${_buildBaseUrl(domain)}&action=get_vod_info&vod_id=$vodId',
        ),
      );
      _updateServerUrlFromResponse(response);
      if (response.data is Map) {
        return Map<String, dynamic>.from(response.data as Map);
      }
      return {};
    } catch (e) {
      debugPrint('[XtreamApi] getVodInfo error: $e');
      return {};
    }
  }

  // ─── Core fetch with cache + failover ─────────────────────────────────────

  Future<List<Map<String, dynamic>>> _getListWithCache({
    required String action,
    int? categoryId,
    Options? options,
    Duration ttl = _categoryItemsTtl,
    bool forceRefresh = false,
  }) async {
    final cacheKey = _buildCacheKey(action, categoryId);

    final cached = _memoryResponseCache[cacheKey];
    if (!forceRefresh && cached != null && !cached.isExpired) {
      return cached.data.map((e) => Map<String, dynamic>.from(e)).toList();
    }

    final response = await DomainManager.instance.executeWithFailover(
      (domain) {
        var url = '${_buildBaseUrl(domain)}&action=$action';
        if (categoryId != null) url += '&category_id=$categoryId';
        return _dio.get(url, options: options);
      },
    );

    // If the domain manager switched to a fallback, keep our _serverUrl in sync.
    _updateServerUrlFromResponse(response);

    final parsed = _parseList(response.data);
    _memoryResponseCache[cacheKey] = _MemoryCacheEntry(
      data: parsed.map((e) => Map<String, dynamic>.from(e)).toList(),
      cachedAt: DateTime.now(),
      ttl: ttl,
    );
    return parsed;
  }

  String _buildCacheKey(String action, int? categoryId) {
    // Use action + optional categoryId as key (domain-agnostic so a cache hit
    // from a previous domain is still valid after a failover switch).
    return categoryId != null ? '$action:$categoryId' : action;
  }

  /// If a failover switched the active domain, update our local _serverUrl.
  void _updateServerUrlFromResponse(Response<dynamic> response) {
    final activeDomain = DomainManager.instance.activeDomain;
    if (_serverUrl != activeDomain) {
      debugPrint(
        '[XtreamApi] Domain switched: $_serverUrl => $activeDomain',
      );
      _serverUrl = activeDomain;
    }
  }

  // ─── Parsing ───────────────────────────────────────────────────────────────

  List<Map<String, dynamic>> _parseList(dynamic data) {
    if (data == null) return [];
    if (data is List) {
      return data.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
    }
    if (data is Map) {
      final asMap = Map<String, dynamic>.from(data);
      if (asMap.values.every((v) => v is! Map)) {
        return [asMap];
      }
      return asMap.values.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
    }
    return [];
  }

  // ─── Status descriptions ───────────────────────────────────────────────────

  static String _statusDescription(int code) {
    switch (code) {
      case 200:
        return 'OK';
      case 403:
        return 'Forbidden (blocked or invalid credentials)';
      case 455:
        return 'IP Not Allowed';
      case 458:
        return 'User already connected with different IP';
      case 464:
        return 'DNS Locked';
      case 511:
      case 512:
        return 'Authentication does not exist';
      default:
        return 'HTTP $code';
    }
  }
}
