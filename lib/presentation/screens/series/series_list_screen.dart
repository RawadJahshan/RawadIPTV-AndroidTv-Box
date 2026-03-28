import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../data/datasources/remote/xtream_api.dart';
import '../../../data/services/favorites_service.dart';
import '../../../data/services/watch_progress_service.dart';
import '../player/movie_player_screen.dart';
import 'series_detail_screen.dart';

class SeriesListScreen extends StatefulWidget {
  final XtreamApi xtreamApi;
  final int categoryId;
  final String categoryName;

  const SeriesListScreen({
    super.key,
    required this.xtreamApi,
    required this.categoryId,
    required this.categoryName,
  });

  @override
  State<SeriesListScreen> createState() => _SeriesListScreenState();
}

class _SeriesListScreenState extends State<SeriesListScreen> {
  static const int _pageSize = 50;
  final TextEditingController _searchController = TextEditingController();

  bool _isLoading = true;
  String? _errorMessage;
  String _searchQuery = '';
  List<_SeriesCardItem> _series = <_SeriesCardItem>[];
  int _currentPage = 0;
  bool _hasMore = true;

  bool get _isContinueWatching => widget.categoryId == -2;
  bool get _isFavorites => widget.categoryId == -3;

  @override
  void initState() {
    super.initState();
    _loadSeries();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadSeries() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    if (_isContinueWatching) {
      await _loadContinueWatchingSeries();
      return;
    }
    if (_isFavorites) {
      await _loadFavoriteSeries();
      return;
    }

    try {
      final List<Map<String, dynamic>> rawSeries;
      if (widget.categoryId == -1) {
        rawSeries = await widget.xtreamApi.getSeries();
      } else {
        rawSeries = await widget.xtreamApi.getSeries(categoryId: widget.categoryId);
      }

      if (!mounted) return;

      setState(() {
        _series = rawSeries.map(_SeriesCardItem.fromApiJson).toList();
        _currentPage = 0;
        _hasMore = _series.length > _pageSize;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Failed to load series. Please try again.';
        _isLoading = false;
      });
    }
  }

  Future<void> _loadFavoriteSeries() async {
    try {
      final entries = await FavoritesService.getAll(FavoriteType.series);
      if (!mounted) return;
      setState(() {
        _series = entries
            .map(
              (entry) => _SeriesCardItem(
                seriesId: entry.id,
                streamId: entry.id,
                title: entry.name,
                posterUrl: entry.poster ?? '',
                rating: '',
              ),
            )
            .toList();
        _currentPage = 0;
        _hasMore = _series.length > _pageSize;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Failed to load favorite series.';
        _isLoading = false;
        _series = <_SeriesCardItem>[];
      });
    }
  }

  Future<void> _loadContinueWatchingSeries() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final entries = await WatchProgressService.getAllProgress();
      final latestBySeries = <int, _SeriesCardItem>{};

      for (final progress in entries) {
        final json = prefs.getString('series_episode_meta_${progress.streamId}');
        if (json == null || json.isEmpty) {
          continue;
        }

        try {
          final metaMap = jsonDecode(json);
          if (metaMap is! Map) {
            continue;
          }

          final seriesId = int.tryParse(metaMap['seriesId']?.toString() ?? '');
          if (seriesId == null || seriesId <= 0) {
            continue;
          }

          final item = _SeriesCardItem.fromContinueWatchingMeta(
            meta: Map<String, dynamic>.from(metaMap),
            progress: progress,
          );

          final existing = latestBySeries[seriesId];
          if (existing == null ||
              (item.lastWatched ?? DateTime.fromMillisecondsSinceEpoch(0))
                  .isAfter(existing.lastWatched ?? DateTime.fromMillisecondsSinceEpoch(0))) {
            latestBySeries[seriesId] = item;
          }
        } catch (_) {
          // Ignore malformed metadata entries.
        }
      }

      if (!mounted) return;
      setState(() {
        _series = latestBySeries.values.toList()
          ..sort((a, b) => (b.lastWatched ?? DateTime.fromMillisecondsSinceEpoch(0))
              .compareTo(a.lastWatched ?? DateTime.fromMillisecondsSinceEpoch(0)));
        _currentPage = 0;
        _hasMore = _series.length > _pageSize;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Failed to load continue watching series.';
        _isLoading = false;
        _series = <_SeriesCardItem>[];
      });
    }
  }

  Future<void> _openContinueWatchingEpisode(_SeriesCardItem item) async {
    if (item.seriesId <= 0 || item.streamId <= 0) {
      return;
    }

    final progress = await WatchProgressService.getProgress(item.streamId);
    final seriesInfo = await widget.xtreamApi.getSeriesInfo(item.seriesId);
    final episodesBySeason = _extractEpisodesBySeason(seriesInfo['episodes']);

    Map<String, dynamic>? matchedEpisode;
    String matchedSeason = '';
    for (final entry in episodesBySeason.entries) {
      for (final episode in entry.value) {
        final id = int.tryParse(episode['id']?.toString() ?? '') ?? 0;
        if (id == item.streamId) {
          matchedEpisode = episode;
          matchedSeason = entry.key;
          break;
        }
      }
      if (matchedEpisode != null) break;
    }

    if (!mounted || matchedEpisode == null) {
      return;
    }

    final episodeNum = matchedEpisode['episode_num']?.toString() ?? '';
    final episodeTitle = matchedEpisode['title']?.toString() ?? item.episodeTitle;
    final extension = (matchedEpisode['container_extension']?.toString() ?? 'mp4').trim();
    final safeExtension = extension.isEmpty ? 'mp4' : extension;

    final streamUrl =
        '${widget.xtreamApi.serverUrl}/series/${widget.xtreamApi.username}/${widget.xtreamApi.password}/${item.streamId}.$safeExtension';
    final playbackTitle =
        '${item.title} S$matchedSeason${episodeNum.isEmpty ? '' : 'E$episodeNum'} - $episodeTitle';

    Duration? startAt;
    if (progress != null && progress.positionMs > 10000 && !progress.isFinished) {
      final resume = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Resume Playback'),
          content: Text('Continue from ${_formatDuration(progress.position)}?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Start Over'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Resume'),
            ),
          ],
        ),
      );
      if (resume == null || !mounted) {
        return;
      }
      startAt = resume ? progress.position : null;
    }

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MoviePlayerScreen(
          streamUrl: streamUrl,
          title: playbackTitle,
          streamId: item.streamId,
          poster: item.posterUrl,
          startAt: startAt,
          seriesId: item.seriesId,
          seriesName: item.title,
        ),
      ),
    );
  }

  Map<String, List<Map<String, dynamic>>> _extractEpisodesBySeason(dynamic episodesRaw) {
    if (episodesRaw is! Map) {
      return <String, List<Map<String, dynamic>>>{};
    }
    final result = <String, List<Map<String, dynamic>>>{};
    for (final entry in episodesRaw.entries) {
      final list = entry.value;
      if (list is List) {
        result[entry.key.toString()] = list
            .whereType<Map>()
            .map((episode) => Map<String, dynamic>.from(episode))
            .toList();
      }
    }
    return result;
  }

  List<_SeriesCardItem> get _filteredSeries {
    if (_searchQuery.isEmpty) {
      return _series;
    }
    final lowerQuery = _searchQuery.toLowerCase();
    return _series.where((series) => series.title.toLowerCase().contains(lowerQuery)).toList();
  }

  int _getCrossAxisCount(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    if (width >= 1200) return 6;
    if (width >= 900) return 5;
    if (width >= 700) return 4;
    return 3;
  }

  double _getFontSize(BuildContext context, double base) {
    final width = MediaQuery.of(context).size.width;
    if (width >= 900) return base;
    return base * 0.85;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: true,
      child: Scaffold(
        backgroundColor: const Color(0xFF1E1E1E),
        appBar: AppBar(
          title: Text(widget.categoryName),
          backgroundColor: const Color(0xFF0F0F1A),
          elevation: 0,
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: TextField(
                controller: _searchController,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'Search series...',
                  hintStyle: const TextStyle(color: Colors.white38),
                  prefixIcon: const Icon(Icons.search, color: Colors.white38),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, color: Colors.white38),
                          onPressed: () {
                            _searchController.clear();
                            setState(() {
                              _searchQuery = '';
                              _currentPage = 0;
                              _hasMore = _series.length > _pageSize;
                            });
                          },
                        )
                      : null,
                  filled: true,
                  fillColor: const Color(0xFF0F0F1A),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Colors.blue, width: 2),
                  ),
                ),
                onChanged: (value) => setState(() {
                  _searchQuery = value;
                  _currentPage = 0;
                  _hasMore = _filteredSeries.length > _pageSize;
                }),
              ),
            ),
            Expanded(child: _buildBody(context)),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _errorMessage!,
              style: TextStyle(color: Colors.white70, fontSize: _getFontSize(context, 14)),
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: _loadSeries,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    final filteredSeries = _filteredSeries;

    if (filteredSeries.isEmpty) {
      if (_isFavorites) {
        return Center(
          child: Text(
            'No favorite series yet',
            style: TextStyle(color: Colors.white54, fontSize: _getFontSize(context, 16)),
          ),
        );
      }
      if (_isContinueWatching) {
        return Center(
          child: Text(
            'No series in Continue Watching yet',
            style: TextStyle(color: Colors.white54, fontSize: _getFontSize(context, 16)),
          ),
        );
      }

      return Center(
        child: Text(
          'No series found',
          style: TextStyle(color: Colors.white54, fontSize: _getFontSize(context, 16)),
        ),
      );
    }

    final end = ((_currentPage + 1) * _pageSize).clamp(0, filteredSeries.length);
    final paginatedSeries = filteredSeries.take(end).toList();
    _hasMore = end < filteredSeries.length;

    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          sliver: SliverGrid(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: _getCrossAxisCount(context),
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
              childAspectRatio: 0.72,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final item = paginatedSeries[index];
                return _SeriesCard(
                  series: item,
                  onTap: () {
                    if (_isContinueWatching) {
                      _openContinueWatchingEpisode(item);
                      return;
                    }
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => SeriesDetailScreen(
                          xtreamApi: widget.xtreamApi,
                          seriesId: item.seriesId,
                          seriesName: item.title,
                          posterUrl: item.posterUrl,
                        ),
                      ),
                    );
                  },
                );
              },
              childCount: paginatedSeries.length,
            ),
          ),
        ),
        if (_hasMore && filteredSeries.length > _pageSize)
          SliverToBoxAdapter(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: TextButton(
                  onPressed: () {
                    setState(() => _currentPage++);
                  },
                  child: const Text('Load More'),
                ),
              ),
            ),
          ),
      ],
    );
  }

  String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '${d.inMinutes}:$s';
  }
}

class _SeriesCard extends StatefulWidget {
  final _SeriesCardItem series;
  final VoidCallback onTap;

  const _SeriesCard({required this.series, required this.onTap});

  @override
  State<_SeriesCard> createState() => _SeriesCardState();
}

class _SeriesCardState extends State<_SeriesCard> {
  bool _isHovering = false;

  @override
  Widget build(BuildContext context) {
    final enableHover = kIsWeb ||
        defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.linux;

    return MouseRegion(
      onEnter: (_) {
        if (enableHover) {
          setState(() => _isHovering = true);
        }
      },
      onExit: (_) {
        if (enableHover) {
          setState(() => _isHovering = false);
        }
      },
      child: AnimatedScale(
        duration: const Duration(milliseconds: 180),
        scale: _isHovering ? 1.02 : 1,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _isHovering ? const Color(0xFF00C6FF).withValues(alpha: 0.6) : Colors.transparent,
              width: 1.2,
            ),
            boxShadow: [
              if (_isHovering)
                BoxShadow(
                  color: const Color(0xFF00C6FF).withValues(alpha: 0.28),
                  blurRadius: 14,
                  spreadRadius: 1,
                ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: widget.onTap,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          ColorFiltered(
                            colorFilter: ColorFilter.mode(
                              Colors.white.withValues(alpha: _isHovering ? 0.12 : 0),
                              BlendMode.screen,
                            ),
                            child: Image.network(
                              widget.series.posterUrl,
                              cacheWidth: 400,
                              cacheHeight: 450,
                              filterQuality: FilterQuality.low,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Container(
                                color: Colors.white10,
                                child: const Icon(Icons.tv, color: Colors.white38, size: 30),
                              ),
                            ),
                          ),
                          Positioned(
                            top: 6,
                            left: 6,
                            child: FutureBuilder<bool>(
                              future: FavoritesService.isFavorite(
                                widget.series.seriesId,
                                FavoriteType.series,
                              ),
                              builder: (context, snapshot) {
                                if (snapshot.data != true) {
                                  return const SizedBox.shrink();
                                }
                                return Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.7),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Icon(
                                    Icons.favorite,
                                    color: Colors.red,
                                    size: 14,
                                  ),
                                );
                              },
                            ),
                          ),
                          Positioned(
                            top: 6,
                            right: 6,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.7),
                                borderRadius: BorderRadius.circular(9),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.star, color: Colors.amber, size: 11),
                                  const SizedBox(width: 2),
                                  Text(
                                    widget.series.rating.isEmpty ? '-' : widget.series.rating,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      color: const Color(0xFF101420),
                      padding: const EdgeInsets.fromLTRB(7, 6, 7, 7),
                      child: Text(
                        widget.series.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 11,
                          height: 1.2,
                        ),
                      ),
                    ),
                    if (widget.series.progressPercent != null)
                      SizedBox(
                        height: 4,
                        child: LinearProgressIndicator(
                          value: widget.series.progressPercent!.clamp(0.0, 1.0),
                          backgroundColor: Colors.white12,
                          valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF00C6FF)),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SeriesCardItem {
  final int seriesId;
  final int streamId;
  final String title;
  final String posterUrl;
  final String rating;
  final String episodeTitle;
  final DateTime? lastWatched;
  final double? progressPercent;

  const _SeriesCardItem({
    required this.seriesId,
    required this.streamId,
    required this.title,
    required this.posterUrl,
    required this.rating,
    this.episodeTitle = '',
    this.lastWatched,
    this.progressPercent,
  });

  factory _SeriesCardItem.fromApiJson(Map<String, dynamic> json) {
    return _SeriesCardItem(
      seriesId: int.tryParse(json['series_id']?.toString() ?? '') ?? 0,
      streamId: int.tryParse(json['series_id']?.toString() ?? '') ?? 0,
      title: json['name']?.toString() ?? 'Unknown',
      posterUrl: (json['cover'] ?? json['stream_icon'] ?? '').toString(),
      rating: json['rating']?.toString() ?? '',
    );
  }

  factory _SeriesCardItem.fromContinueWatchingMeta({
    required Map<String, dynamic> meta,
    required WatchProgressEntry progress,
  }) {
    return _SeriesCardItem(
      seriesId: int.tryParse(meta['seriesId']?.toString() ?? '') ?? 0,
      streamId: progress.streamId,
      title: meta['seriesName']?.toString() ?? 'Unknown Series',
      posterUrl: meta['poster']?.toString() ?? progress.poster ?? '',
      rating: '',
      episodeTitle: meta['episodeTitle']?.toString() ?? progress.title,
      lastWatched: progress.lastWatched,
      progressPercent: progress.progressPercent,
    );
  }
}
