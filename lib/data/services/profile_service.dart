import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/profile.dart';

class ProfileService {
  static const String _profilesKey = 'profiles';
  static const String _activeProfileKey = 'active_profile_id';

  // Get all saved profiles
  static Future<List<Profile>> getProfiles() async {
    final prefs = await SharedPreferences.getInstance();
    final profilesJson = prefs.getStringList(_profilesKey) ?? [];
    return profilesJson
        .map((json) => Profile.fromJson(jsonDecode(json)))
        .toList();
  }

  // Save a new profile
  static Future<void> saveProfile(Profile profile) async {
    final prefs = await SharedPreferences.getInstance();
    final profiles = await getProfiles();

    // Check if profile with same id exists and update it
    final existingIndex = profiles.indexWhere((p) => p.id == profile.id);
    if (existingIndex != -1) {
      profiles[existingIndex] = profile;
    } else {
      profiles.add(profile);
    }

    await prefs.setStringList(
      _profilesKey,
      profiles.map((p) => jsonEncode(p.toJson())).toList(),
    );
  }

  // Delete a profile
  static Future<void> deleteProfile(String profileId) async {
    final prefs = await SharedPreferences.getInstance();
    final profiles = await getProfiles();
    profiles.removeWhere((p) => p.id == profileId);
    await prefs.setStringList(
      _profilesKey,
      profiles.map((p) => jsonEncode(p.toJson())).toList(),
    );
  }

  // Set active profile
  static Future<void> setActiveProfile(String profileId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_activeProfileKey, profileId);
  }

  // Get active profile
  static Future<Profile?> getActiveProfile() async {
    final prefs = await SharedPreferences.getInstance();
    final activeId = prefs.getString(_activeProfileKey);
    if (activeId == null) return null;
    final profiles = await getProfiles();
    try {
      return profiles.firstWhere((p) => p.id == activeId);
    } catch (_) {
      return null;
    }
  }

  // Clear active profile
  static Future<void> clearActiveProfile() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_activeProfileKey);
  }
}