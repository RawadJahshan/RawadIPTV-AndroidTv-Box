import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class WatchProgressEntry {
  final int streamId;
  final String title;
  final String? poster;
  final int positionMs;
  final int durationMs;
  final DateTime lastWatched;

  WatchProgressEntry({
    required this.streamId,
    required this.title,
    this.poster,
    required this.positionMs,
    required this.durationMs,
    required this.lastWatched,
  });

  double get progressPercent => durationMs > 0 ? positionMs / durationMs : 0.0;

  bool get isFinished => progressPercent > 0.9;

  Duration get position => Duration(milliseconds: positionMs);

  Map<String, dynamic> toJson() => {
        'streamId': streamId,
        'title': title,
        'poster': poster,
        'positionMs': positionMs,
        'durationMs': durationMs,
        'lastWatched': lastWatched.toIso8601String(),
      };

  factory WatchProgressEntry.fromJson(Map<String, dynamic> json) => WatchProgressEntry(
        streamId: json['streamId'],
        title: json['title'],
        poster: json['poster'],
        positionMs: json['positionMs'],
        durationMs: json['durationMs'],
        lastWatched: DateTime.parse(json['lastWatched']),
      );
}

class WatchProgressService {
  static const String _prefix = 'watch_progress_';
  static const String _listKey = 'watch_progress_list';

  static Future<void> saveProgress({
    required int streamId,
    required String title,
    String? poster,
    required int positionMs,
    required int durationMs,
  }) async {
    if (durationMs <= 0) return;

    final prefs = await SharedPreferences.getInstance();
    final entry = WatchProgressEntry(
      streamId: streamId,
      title: title,
      poster: poster,
      positionMs: positionMs,
      durationMs: durationMs,
      lastWatched: DateTime.now(),
    );

    await prefs.setString(
      '$_prefix$streamId',
      jsonEncode(entry.toJson()),
    );

    final list = prefs.getStringList(_listKey) ?? <String>[];
    final idStr = streamId.toString();
    if (!list.contains(idStr)) {
      list.add(idStr);
    }
    await prefs.setStringList(_listKey, list);
  }

  static Future<WatchProgressEntry?> getProgress(int streamId) async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString('$_prefix$streamId');
    if (json == null) return null;

    try {
      return WatchProgressEntry.fromJson(jsonDecode(json));
    } catch (_) {
      return null;
    }
  }

  static Future<List<WatchProgressEntry>> getAllProgress() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_listKey) ?? <String>[];
    final entries = <WatchProgressEntry>[];

    for (final idStr in list) {
      final json = prefs.getString('$_prefix$idStr');
      if (json != null) {
        try {
          final entry = WatchProgressEntry.fromJson(jsonDecode(json));
          if (!entry.isFinished) {
            entries.add(entry);
          }
        } catch (_) {
          // Ignore malformed progress payloads.
        }
      }
    }

    entries.sort((a, b) => b.lastWatched.compareTo(a.lastWatched));
    return entries;
  }

  static Future<void> removeProgress(int streamId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_prefix$streamId');

    final list = prefs.getStringList(_listKey) ?? <String>[];
    list.remove(streamId.toString());
    await prefs.setStringList(_listKey, list);
  }
}
