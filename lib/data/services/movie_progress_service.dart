import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/movie_watch_progress.dart';

class MovieProgressService {
  static const String _key = 'movie_watch_progress_v1';

  static Future<Map<int, MovieWatchProgress>> loadProgressMap() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return <int, MovieWatchProgress>{};

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return <int, MovieWatchProgress>{};

      final map = <int, MovieWatchProgress>{};
      for (final item in decoded) {
        if (item is Map) {
          final progress = MovieWatchProgress.fromJson(Map<String, dynamic>.from(item));
          map[progress.streamId] = progress;
        }
      }
      return map;
    } catch (_) {
      return <int, MovieWatchProgress>{};
    }
  }

  static Future<void> saveProgress(MovieWatchProgress progress) async {
    final map = await loadProgressMap();

    if (progress.durationMs > 0 && progress.positionMs >= progress.durationMs - 5000) {
      map.remove(progress.streamId);
    } else {
      map[progress.streamId] = progress;
    }

    await _persist(map);
  }

  static Future<MovieWatchProgress?> getProgress(int streamId) async {
    final map = await loadProgressMap();
    return map[streamId];
  }

  static Future<List<MovieWatchProgress>> getContinueWatching() async {
    final map = await loadProgressMap();
    final list = map.values.toList();
    list.sort((a, b) => b.positionMs.compareTo(a.positionMs));
    return list;
  }

  static Future<void> _persist(Map<int, MovieWatchProgress> map) async {
    final prefs = await SharedPreferences.getInstance();
    final payload = map.values.map((e) => e.toJson()).toList();
    await prefs.setString(_key, jsonEncode(payload));
  }
}
