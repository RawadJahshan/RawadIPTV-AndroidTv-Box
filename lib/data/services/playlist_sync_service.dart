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

class PlaylistSyncService {
  static const int _totalSteps = 6;

  static Future<void> syncXtreamCatalog({
    required XtreamApi xtreamApi,
    required String profileId,
    required ValueChanged<PlaylistSyncProgress> onProgress,
  }) async {
    onProgress(
      const PlaylistSyncProgress(
        title: 'Adding Playlist Content',
        status: 'Fetching categories...',
        step: 1,
        totalSteps: _totalSteps,
      ),
    );

    final liveCategories = await xtreamApi.getLiveCategories();
    final vodCategories = await xtreamApi.getVodCategories();
    final seriesCategories = await xtreamApi.getSeriesCategories();

    onProgress(
      const PlaylistSyncProgress(
        title: 'Adding Playlist Content',
        status: 'Loading Live TV...',
        step: 2,
        totalSteps: _totalSteps,
      ),
    );
    final liveStreams = await xtreamApi.getLiveStreams();

    onProgress(
      const PlaylistSyncProgress(
        title: 'Adding Playlist Content',
        status: 'Loading Movies...',
        step: 3,
        totalSteps: _totalSteps,
      ),
    );
    final vodStreams = await xtreamApi.getVodStreamsStrict();

    onProgress(
      const PlaylistSyncProgress(
        title: 'Adding Playlist Content',
        status: 'Loading Series...',
        step: 4,
        totalSteps: _totalSteps,
      ),
    );
    final series = await xtreamApi.getSeries();

    onProgress(
      const PlaylistSyncProgress(
        title: 'Adding Playlist Content',
        status: 'Saving content...',
        step: 5,
        totalSteps: _totalSteps,
      ),
    );

    await CatalogCacheService.saveLiveCategories(profileId, liveCategories);
    await CatalogCacheService.saveVodCategories(profileId, vodCategories);
    await CatalogCacheService.saveSeriesCategories(profileId, seriesCategories);
    await CatalogCacheService.saveLiveStreams(profileId, liveStreams);
    await CatalogCacheService.saveVodStreams(profileId, vodStreams);
    await CatalogCacheService.saveSeries(profileId, series);

    onProgress(
      const PlaylistSyncProgress(
        title: 'Adding Playlist Content',
        status: 'Completed',
        step: 6,
        totalSteps: _totalSteps,
      ),
    );
  }
}
