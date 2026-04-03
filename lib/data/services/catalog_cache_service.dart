import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// TTL-backed catalog cache.
///
/// Each entry is stored as `{"ts": <epoch_ms>, "data": [...]}`.
/// Reads return [] when the entry is missing or older than the TTL,
/// which triggers the caller to re-fetch from the API.
///
/// TTL values:
///   • Categories (live/vod/series): 6 hours
///     Category lists change rarely; 6 h balances freshness vs. startup speed.
///   • Per-category item lists (channels/movies/series): 2 hours
///     Content is added/removed more often; 2 h keeps things reasonably fresh
///     without hitting the API on every single screen open.
///
/// Manual refresh calls [clearAllForProfile] to wipe all cached data for a
/// profile, then re-fetches only lightweight category metadata.  Item lists
/// are then refetched lazily as the user browses into each category.
class CatalogCacheService {
  static const Duration _categoriesTtl = Duration(hours: 6);
  static const Duration _itemsTtl = Duration(hours: 2);

  static String _key(String profileId, String segment) =>
      'catalog_${profileId}_$segment';

  // ── Category cache (lightweight warmup data) ──────────────────────────────

  static Future<void> saveLiveCategories(
    String profileId,
    List<Map<String, dynamic>> categories,
  ) async {
    await _saveWithTs(_key(profileId, 'live_categories'), categories);
  }

  static Future<void> saveVodCategories(
    String profileId,
    List<Map<String, dynamic>> categories,
  ) async {
    await _saveWithTs(_key(profileId, 'vod_categories'), categories);
  }

  static Future<void> saveSeriesCategories(
    String profileId,
    List<Map<String, dynamic>> categories,
  ) async {
    await _saveWithTs(_key(profileId, 'series_categories'), categories);
  }

  static Future<List<Map<String, dynamic>>> getLiveCategories(
      String profileId) async {
    return _readIfFresh(_key(profileId, 'live_categories'), _categoriesTtl);
  }

  static Future<List<Map<String, dynamic>>> getVodCategories(
      String profileId) async {
    return _readIfFresh(_key(profileId, 'vod_categories'), _categoriesTtl);
  }

  static Future<List<Map<String, dynamic>>> getSeriesCategories(
      String profileId) async {
    return _readIfFresh(_key(profileId, 'series_categories'), _categoriesTtl);
  }

  // ── Per-category item cache (lazy-loaded when user opens a category) ───────

  static Future<void> saveLiveStreamsByCategory(
    String profileId,
    int categoryId,
    List<Map<String, dynamic>> streams,
  ) async {
    await _saveWithTs(_key(profileId, 'live_cat_$categoryId'), streams);
  }

  static Future<List<Map<String, dynamic>>> getLiveStreamsByCategory(
    String profileId,
    int categoryId,
  ) async {
    return _readIfFresh(_key(profileId, 'live_cat_$categoryId'), _itemsTtl);
  }

  static Future<void> saveVodStreamsByCategory(
    String profileId,
    int categoryId,
    List<Map<String, dynamic>> streams,
  ) async {
    await _saveWithTs(_key(profileId, 'vod_cat_$categoryId'), streams);
  }

  static Future<List<Map<String, dynamic>>> getVodStreamsByCategory(
    String profileId,
    int categoryId,
  ) async {
    return _readIfFresh(_key(profileId, 'vod_cat_$categoryId'), _itemsTtl);
  }

  static Future<void> saveSeriesByCategory(
    String profileId,
    int categoryId,
    List<Map<String, dynamic>> series,
  ) async {
    await _saveWithTs(_key(profileId, 'series_cat_$categoryId'), series);
  }

  static Future<List<Map<String, dynamic>>> getSeriesByCategory(
    String profileId,
    int categoryId,
  ) async {
    return _readIfFresh(_key(profileId, 'series_cat_$categoryId'), _itemsTtl);
  }

  // ── Profile-level cache clear (called before manual refresh) ─────────────

  /// Removes every cache key that belongs to [profileId].
  /// After this call the in-memory XtreamApi cache should also be cleared
  /// (done inside PlaylistSyncService).
  static Future<void> clearAllForProfile(String profileId) async {
    final prefs = await SharedPreferences.getInstance();
    final prefix = 'catalog_${profileId}_';
    final keysToRemove =
        prefs.getKeys().where((k) => k.startsWith(prefix)).toList();
    for (final k in keysToRemove) {
      await prefs.remove(k);
    }
  }

  // ── Internal helpers ──────────────────────────────────────────────────────

  static Future<void> _saveWithTs(
    String key,
    List<Map<String, dynamic>> data,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final wrapper = <String, dynamic>{
      'ts': DateTime.now().millisecondsSinceEpoch,
      'data': data,
    };
    await prefs.setString(key, jsonEncode(wrapper));
  }

  static Future<List<Map<String, dynamic>>> _readIfFresh(
    String key,
    Duration ttl,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(key);
    if (raw == null || raw.isEmpty) return [];

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return [];

      final ts = decoded['ts'];
      if (ts is! int) return [];

      final ageMs = DateTime.now().millisecondsSinceEpoch - ts;
      if (ageMs > ttl.inMilliseconds) return []; // expired

      final data = decoded['data'];
      if (data is! List) return [];

      return data
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    } catch (_) {
      return [];
    }
  }
}
