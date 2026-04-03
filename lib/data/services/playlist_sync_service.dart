import 'package:flutter/foundation.dart';

import '../datasources/remote/xtream_api.dart';
import 'catalog_cache_service.dart';

class PlaylistSyncProgress {
  final String title;
  final String status;
  final int step;
  final int totalSteps;

  const PlaylistSyncProgress({
    required this.title,
    required this.status,
    required this.step,
    required this.totalSteps,
  });

  double get progress => totalSteps == 0 ? 0 : step / totalSteps;
}

/// Lightweight catalog warmup.
///
/// Only fetches the three category lists (live / VOD / series).
/// Heavy content (channels, movies, series items) is NOT prefetched here —
/// it is loaded lazily when the user opens a category, then cached with a
/// 2-hour TTL by each screen.
///
/// Steps: 1 = fetch categories (parallel)  2 = save  3 = done
class PlaylistSyncService {
  static const int _totalSteps = 3;

  static Future<void> syncXtreamCatalog({
    required XtreamApi xtreamApi,
    required String profileId,
    required ValueChanged<PlaylistSyncProgress> onProgress,
  }) async {
    // Clear stale in-memory cache so re-fetched data is fresh.
    XtreamApi.clearAllInMemoryCaches();
    // Clear all on-disk cached data for this profile so every category and
    // item screen will refetch from the API on next visit.
    await CatalogCacheService.clearAllForProfile(profileId);

    onProgress(
      const PlaylistSyncProgress(
        title: 'Refreshing Playlist',
        status: 'Fetching categories...',
        step: 1,
        totalSteps: _totalSteps,
      ),
    );

    // Fetch all three category lists in parallel — fast lightweight calls.
    final results = await Future.wait([
      xtreamApi.getLiveCategories(),
      xtreamApi.getVodCategories(),
      xtreamApi.getSeriesCategories(),
    ]);

    onProgress(
      const PlaylistSyncProgress(
        title: 'Refreshing Playlist',
        status: 'Saving categories...',
        step: 2,
        totalSteps: _totalSteps,
      ),
    );

    await CatalogCacheService.saveLiveCategories(profileId, results[0]);
    await CatalogCacheService.saveVodCategories(profileId, results[1]);
    await CatalogCacheService.saveSeriesCategories(profileId, results[2]);

    onProgress(
      const PlaylistSyncProgress(
        title: 'Refreshing Playlist',
        status: 'Done',
        step: 3,
        totalSteps: _totalSteps,
      ),
    );
  }
}
