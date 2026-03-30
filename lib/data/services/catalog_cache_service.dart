import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class CatalogCacheService {
  static String _key(String profileId, String segment) =>
      'catalog_${profileId}_$segment';

  static Future<void> saveLiveCategories(
    String profileId,
    List<Map<String, dynamic>> categories,
  ) async {
    await _saveList(_key(profileId, 'live_categories'), categories);
  }

  static Future<void> saveVodCategories(
    String profileId,
    List<Map<String, dynamic>> categories,
  ) async {
    await _saveList(_key(profileId, 'vod_categories'), categories);
  }

  static Future<void> saveSeriesCategories(
    String profileId,
    List<Map<String, dynamic>> categories,
  ) async {
    await _saveList(_key(profileId, 'series_categories'), categories);
  }

  static Future<void> saveLiveStreams(
    String profileId,
    List<Map<String, dynamic>> streams,
  ) async {
    await _saveList(_key(profileId, 'live_streams'), streams);
  }

  static Future<void> saveVodStreams(
    String profileId,
    List<Map<String, dynamic>> streams,
  ) async {
    await _saveList(_key(profileId, 'vod_streams'), streams);
  }

  static Future<void> saveSeries(String profileId, List<Map<String, dynamic>> series) async {
    await _saveList(_key(profileId, 'series'), series);
  }

  static Future<List<Map<String, dynamic>>> getLiveCategories(String profileId) async {
    return _readList(_key(profileId, 'live_categories'));
  }

  static Future<List<Map<String, dynamic>>> getVodCategories(String profileId) async {
    return _readList(_key(profileId, 'vod_categories'));
  }

  static Future<List<Map<String, dynamic>>> getSeriesCategories(String profileId) async {
    return _readList(_key(profileId, 'series_categories'));
  }

  static Future<List<Map<String, dynamic>>> getLiveStreams(String profileId, {int? categoryId}) async {
    final all = await _readList(_key(profileId, 'live_streams'));
    if (categoryId == null) {
      return all;
    }
    return all.where((item) => _parseInt(item['category_id']) == categoryId).toList();
  }

  static Future<List<Map<String, dynamic>>> getVodStreams(String profileId, {int? categoryId}) async {
    final all = await _readList(_key(profileId, 'vod_streams'));
    if (categoryId == null) {
      return all;
    }
    return all.where((item) => _parseInt(item['category_id']) == categoryId).toList();
  }

  static Future<List<Map<String, dynamic>>> getSeries(String profileId, {int? categoryId}) async {
    final all = await _readList(_key(profileId, 'series'));
    if (categoryId == null) {
      return all;
    }
    return all.where((item) => _parseInt(item['category_id']) == categoryId).toList();
  }

  static Future<void> _saveList(String key, List<Map<String, dynamic>> data) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, jsonEncode(data));
  }

  static Future<List<Map<String, dynamic>>> _readList(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString(key);
    if (jsonString == null || jsonString.isEmpty) {
      return <Map<String, dynamic>>[];
    }

    final decoded = jsonDecode(jsonString);
    if (decoded is! List) {
      return <Map<String, dynamic>>[];
    }

    return decoded
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  static int _parseInt(dynamic value) => int.tryParse(value?.toString() ?? '') ?? 0;
}
