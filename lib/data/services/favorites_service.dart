import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

enum FavoriteType { movie, series }

class FavoriteEntry {
  final int id;
  final String name;
  final String? poster;
  final FavoriteType type;
  final DateTime addedAt;

  FavoriteEntry({
    required this.id,
    required this.name,
    this.poster,
    required this.type,
    required this.addedAt,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'poster': poster,
    'type': type.name,
    'addedAt': addedAt.toIso8601String(),
  };

  factory FavoriteEntry.fromJson(Map<String, dynamic> json) =>
    FavoriteEntry(
      id: json['id'],
      name: json['name'],
      poster: json['poster'],
      type: FavoriteType.values.byName(json['type']),
      addedAt: DateTime.parse(json['addedAt']),
    );
}

class FavoritesService {
  static const String _moviesKey = 'favorites_movies_v2';
  static const String _seriesKey = 'favorites_series_v2';

  static String _keyForType(FavoriteType type) =>
    type == FavoriteType.movie ? _moviesKey : _seriesKey;

  static Future<void> add(FavoriteEntry entry) async {
    final prefs = await SharedPreferences.getInstance();
    final key = _keyForType(entry.type);
    final list = await _getList(prefs, key);
    list.removeWhere((e) => e.id == entry.id);
    list.insert(0, entry);
    await prefs.setStringList(
      key,
      list.map((e) => jsonEncode(e.toJson())).toList(),
    );
  }

  static Future<void> remove(int id, FavoriteType type) async {
    final prefs = await SharedPreferences.getInstance();
    final key = _keyForType(type);
    final list = await _getList(prefs, key);
    list.removeWhere((e) => e.id == id);
    await prefs.setStringList(
      key,
      list.map((e) => jsonEncode(e.toJson())).toList(),
    );
  }

  static Future<bool> isFavorite(int id, FavoriteType type) async {
    final prefs = await SharedPreferences.getInstance();
    final key = _keyForType(type);
    final list = await _getList(prefs, key);
    return list.any((e) => e.id == id);
  }

  static Future<List<FavoriteEntry>> getAll(FavoriteType type) async {
    final prefs = await SharedPreferences.getInstance();
    final key = _keyForType(type);
    return _getList(prefs, key);
  }

  static Future<List<FavoriteEntry>> _getList(
      SharedPreferences prefs, String key) async {
    try {
      final list = prefs.getStringList(key) ?? [];
      return list.map((e) {
        try {
          return FavoriteEntry.fromJson(
            jsonDecode(e) as Map<String, dynamic>);
        } catch (_) {
          return null;
        }
      }).whereType<FavoriteEntry>().toList();
    } catch (_) {
      return [];
    }
  }
}
