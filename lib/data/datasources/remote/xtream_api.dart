import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import '../../../core/constants/app_constants.dart';

class XtreamApi {
  late final Dio _dio;
  static final Set<XtreamApi> _instances = <XtreamApi>{};
  final Map<String, dynamic> _memoryResponseCache = <String, dynamic>{};

  late String _serverUrl;
  late String _username;
  late String _password;

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
        validateStatus: (status) => status != null && status >= 200 && status < 500,
        responseType: ResponseType.json,
      ),
    );

    _dio.interceptors.add(
      InterceptorsWrapper(
        onError: (error, handler) {
          if (error.response?.statusCode == 403) {
            debugPrint('[API] 403 Forbidden — check credentials or User-Agent');
          }
          debugPrint('API Error: ${error.message}');
          handler.next(error);
        },
      ),
    );

    _dio.options.headers = {
      'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
          'AppleWebKit/537.36 (KHTML, like Gecko) '
          'Chrome/120.0.0.0 Safari/537.36',
      'Accept': '*/*',
      'Accept-Language': 'en-US,en;q=0.9',
      'Connection': 'keep-alive',
    };
    _dio.options.connectTimeout = const Duration(seconds: 15);
    _dio.options.receiveTimeout = const Duration(seconds: 30);
  }

  void setCredentials({
    required String serverUrl,
    required String username,
    required String password,
  }) {
    _serverUrl = AppConstants.serverUrl;
    _username = username;
    _password = password;
  }

  String get serverUrl => _serverUrl;
  String get username => _username;
  String get password => _password;

  String get _baseUrl => '$_serverUrl/player_api.php?username=$_username&password=$_password';

  static void clearAllInMemoryCaches() {
    for (final instance in _instances) {
      instance._memoryResponseCache.clear();
    }
    debugPrint('XtreamApi: Cleared in-memory metadata/list caches for ${_instances.length} instance(s)');
  }

  Future<Map<String, dynamic>> authenticate(
    String serverUrl,
    String username,
    String password,
  ) async {
    try {
      final url = '${AppConstants.apiBase}?username=$username&password=$password&action=get_live_categories';
      final response = await _dio.get(url);
      if (response.statusCode == 200) {
        return {'success': true, 'data': response.data};
      }
      return {'success': false, 'message': 'Invalid username or password'};
    } on DioException catch (e) {
      debugPrint('Auth error: ${e.message}');
      return {'success': false, 'message': 'Invalid username or password'};
    } catch (e) {
      return {'success': false, 'message': 'Invalid username or password'};
    }
  }

  Future<List<Map<String, dynamic>>> getLiveCategories() async {
    try {
      return await _getListWithCache('$_baseUrl&action=get_live_categories');
    } catch (e) {
      debugPrint('getLiveCategories error: $e');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> getLiveStreams({int? categoryId}) async {
    try {
      var url = '$_baseUrl&action=get_live_streams';
      if (categoryId != null) url += '&category_id=$categoryId';
      return await _getListWithCache(
        url,
        options: Options(receiveTimeout: const Duration(seconds: 60)),
      );
    } catch (e) {
      debugPrint('getLiveStreams error: $e');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> getVodCategories() async {
    try {
      return await _getListWithCache('$_baseUrl&action=get_vod_categories');
    } catch (e) {
      debugPrint('getVodCategories error: $e');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> getVodStreams({int? categoryId}) async {
    try {
      var url = '$_baseUrl&action=get_vod_streams';
      if (categoryId != null) {
        url += '&category_id=$categoryId';
      }
      return await _getListWithCache(
        url,
        options: Options(receiveTimeout: const Duration(seconds: 60)),
      );
    } catch (e) {
      debugPrint('getVodStreams error: $e');
      return [];
    }
  }


  Future<List<Map<String, dynamic>>> getVodStreamsStrict({int? categoryId}) async {
    var url = '$_baseUrl&action=get_vod_streams';
    if (categoryId != null) {
      url += '&category_id=$categoryId';
    }
    return _getListWithCache(
      url,
      options: Options(receiveTimeout: const Duration(seconds: 60)),
    );
  }


  Future<List<Map<String, dynamic>>> getSeriesCategories() async {
    try {
      return await _getListWithCache('$_baseUrl&action=get_series_categories');
    } catch (e) {
      debugPrint('getSeriesCategories error: $e');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> getSeries({int? categoryId}) async {
    try {
      var url = '$_baseUrl&action=get_series';
      if (categoryId != null) {
        url += '&category_id=$categoryId';
      }
      return await _getListWithCache(
        url,
        options: Options(receiveTimeout: const Duration(seconds: 60)),
      );
    } catch (e) {
      debugPrint('getSeries error: $e');
      return [];
    }
  }

  Future<Map<String, dynamic>> getSeriesInfo(int seriesId) async {
    final url = '$_baseUrl&action=get_series_info&series_id=$seriesId';
    try {
      final response = await _dio.get(url);
      if (response.data is Map) {
        return Map<String, dynamic>.from(response.data as Map);
      }
      return <String, dynamic>{};
    } catch (e) {
      debugPrint('getSeriesInfo error: $e');
      return <String, dynamic>{};
    }
  }

  Future<Map<String, dynamic>> getVodInfo(int vodId) async {
    final url = '$_baseUrl&action=get_vod_info&vod_id=$vodId';
    try {
      final response = await _dio.get(url);
      if (response.data is Map) {
        return Map<String, dynamic>.from(response.data as Map);
      }
      return <String, dynamic>{};
    } catch (e) {
      debugPrint('getVodInfo error: $e');
      return <String, dynamic>{};
    }
  }

  List<Map<String, dynamic>> _parseList(dynamic data) {
    if (data == null) return [];
    if (data is List) {
      return data.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
    }
    if (data is Map) {
      return data.values.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
    }
    return [];
  }

  Future<List<Map<String, dynamic>>> _getListWithCache(
    String url, {
    Options? options,
  }) async {
    final cached = _memoryResponseCache[url];
    if (cached is List<Map<String, dynamic>>) {
      return cached.map((item) => Map<String, dynamic>.from(item)).toList();
    }

    final response = await _dio.get(url, options: options);
    final parsed = _parseList(response.data);
    _memoryResponseCache[url] = parsed.map((item) => Map<String, dynamic>.from(item)).toList();
    return parsed;
  }
}
