import 'package:flutter/painting.dart';

import '../datasources/remote/xtream_api.dart';

class CacheMaintenanceService {
  static Future<void> clearAppCaches() async {
    XtreamApi.clearAllInMemoryCaches();

    final imageCache = PaintingBinding.instance.imageCache;
    imageCache.clear();
    imageCache.clearLiveImages();
  }
}
