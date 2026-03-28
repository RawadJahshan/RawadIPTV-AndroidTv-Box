import 'package:shared_preferences/shared_preferences.dart';

class FavoritesManager {
  static const String _liveKey = 'favorites_live';

  static Future<bool> isFavoriteLive(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_liveKey) ?? [];
    return list.contains(id);
  }

  static Future<void> addFavoriteLive(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_liveKey) ?? [];
    if (!list.contains(id)) {
      list.add(id);
      await prefs.setStringList(_liveKey, list);
    }
  }

  static Future<void> removeFavoriteLive(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_liveKey) ?? [];
    list.remove(id);
    await prefs.setStringList(_liveKey, list);
  }

  static Future<List<String>> getFavoriteLiveIds() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_liveKey) ?? [];
  }

  static Future<bool> isFavorite(String id) => isFavoriteLive(id);
  static Future<void> addFavorite(String id) => addFavoriteLive(id);
  static Future<void> removeFavorite(String id) => removeFavoriteLive(id);
  static Future<List<String>> getFavoriteIds() => getFavoriteLiveIds();
}
