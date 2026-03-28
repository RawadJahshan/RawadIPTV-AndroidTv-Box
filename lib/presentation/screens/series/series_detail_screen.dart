import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../data/datasources/remote/xtream_api.dart';
import '../../../data/services/favorites_service.dart';
import '../../../data/services/watch_progress_service.dart';
import '../player/movie_player_screen.dart';

class SeriesDetailScreen extends StatefulWidget {
  final XtreamApi xtreamApi;
  final int seriesId;
  final String seriesName;
  final String posterUrl;

  const SeriesDetailScreen({
    super.key,
    required this.xtreamApi,
    required this.seriesId,
    required this.seriesName,
    required this.posterUrl,
  });

  @override
  State<SeriesDetailScreen> createState() => _SeriesDetailScreenState();
}

class _SeriesDetailScreenState extends State<SeriesDetailScreen> {
  bool _loading = true;
  bool _isPlotExpanded = false;
  bool _isFavorite = false;

  String _title = '';
  String _cover = '';
  String _plot = '';
  String _genre = '';
  String _director = '';
  String _cast = '';
  String _releaseDate = '';
  String _rating = '';
  String _trailerUrl = '';

  final Map<String, List<Map<String, dynamic>>> _episodesBySeason = <String, List<Map<String, dynamic>>>{};
  List<String> _seasons = <String>[];
  String _selectedSeason = '';

  @override
  void initState() {
    super.initState();
    _title = widget.seriesName;
    _cover = widget.posterUrl;
    _loadFavoriteStatus();
    _load();
  }

  Future<void> _loadFavoriteStatus() async {
    final fav = await FavoritesService.isFavorite(widget.seriesId, FavoriteType.series);
    if (mounted) {
      setState(() => _isFavorite = fav);
    }
  }

  Future<void> _load() async {
    try {
      final seriesInfo = await widget.xtreamApi.getSeriesInfo(widget.seriesId);
      final infoRaw = seriesInfo['info'];
      if (infoRaw is Map) {
        final info = Map<dynamic, dynamic>.from(infoRaw);
        _title = _pick(info, ['name', 'title'], fallback: _title);
        _cover = _pick(info, ['cover', 'stream_icon'], fallback: _cover);
        _plot = _pick(info, ['plot', 'description']);
        _cast = _pick(info, ['cast']);
        _director = _pick(info, ['director']);
        _genre = _pick(info, ['genre']);
        _releaseDate = _pick(info, ['releaseDate', 'release_date', 'releasedate']);
        _rating = _pick(info, ['rating', 'vote_average']);
        _trailerUrl = _pick(info, ['youtube_trailer', 'trailer_url']);
      }

      final episodes = _extractEpisodesBySeason(seriesInfo['episodes']);
      final seasonNumbers = episodes.keys.toList()
        ..sort((a, b) => _asInt(a).compareTo(_asInt(b)));

      _episodesBySeason
        ..clear()
        ..addAll(episodes);
      _seasons = seasonNumbers;
      if (_seasons.isNotEmpty) {
        _selectedSeason = _seasons.first;
      }
    } catch (_) {
      // Keep fallback values from listing endpoint.
    }

    if (!mounted) return;
    setState(() {
      _loading = false;
    });
  }

  int _asInt(String value) => int.tryParse(value) ?? 0;

  String _pick(Map<dynamic, dynamic> map, List<String> keys, {String fallback = ''}) {
    for (final key in keys) {
      final value = map[key];
      if (value == null) {
        continue;
      }
      final normalized = value.toString().trim();
      if (normalized.isNotEmpty) {
        return normalized;
      }
    }
    return fallback;
  }

  List<String> get _castMembers => _cast
      .split(RegExp(r'[,/|]'))
      .map((name) => name.trim())
      .where((name) => name.isNotEmpty)
      .toList();

  double get _ratingValue => double.tryParse(_rating) ?? 0;

  Map<String, List<Map<String, dynamic>>> _extractEpisodesBySeason(dynamic episodesRaw) {
    if (episodesRaw is! Map) {
      return <String, List<Map<String, dynamic>>>{};
    }

    final result = <String, List<Map<String, dynamic>>>{};
    for (final entry in episodesRaw.entries) {
      final seasonKey = entry.key.toString();
      final episodes = entry.value;
      if (episodes is List) {
        result[seasonKey] = episodes
            .whereType<Map>()
            .map((episode) => Map<String, dynamic>.from(episode))
            .toList();
      }
    }

    return result;
  }

  Future<void> _openTrailer() async {
    if (_trailerUrl.trim().isEmpty) {
      return;
    }

    final raw = _trailerUrl.trim();
    final normalized = raw.startsWith('http://') || raw.startsWith('https://') ? raw : 'https://www.youtube.com/watch?v=$raw';
    final uri = Uri.tryParse(normalized);
    if (uri == null) {
      return;
    }

    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _playEpisode(Map<String, dynamic> episode, String season) async {
    final episodeId = int.tryParse(episode['id']?.toString() ?? '') ?? 0;
    if (episodeId <= 0) {
      return;
    }

    final episodeNum = episode['episode_num']?.toString() ?? '';
    final episodeTitle = episode['title']?.toString() ?? 'Episode';
    final extRaw = episode['container_extension']?.toString() ?? 'mp4';
    final extension = extRaw.trim().isEmpty ? 'mp4' : extRaw.trim();

    final playbackTitle = '${_title.isEmpty ? widget.seriesName : _title} S$season${episodeNum.isEmpty ? '' : 'E$episodeNum'} - $episodeTitle';
    final streamUrl =
        '${widget.xtreamApi.serverUrl}/series/${widget.xtreamApi.username}/${widget.xtreamApi.password}/$episodeId.$extension';

    final progress = await WatchProgressService.getProgress(episodeId);
    if (!mounted) return;

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

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'series_episode_meta_$episodeId',
      jsonEncode({
        'seriesId': widget.seriesId,
        'seriesName': _title.isEmpty ? widget.seriesName : _title,
        'episodeTitle': playbackTitle,
        'poster': _cover,
        'streamId': episodeId,
      }),
    );

    if (!mounted) return;

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MoviePlayerScreen(
          streamUrl: streamUrl,
          title: playbackTitle,
          streamId: episodeId,
          poster: _cover,
          startAt: startAt,
          seriesId: widget.seriesId,
          seriesName: _title.isEmpty ? widget.seriesName : _title,
        ),
      ),
    );
  }

  String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '${d.inMinutes}:$s';
  }

  double _getFontSize(BuildContext context, double base) {
    final width = MediaQuery.of(context).size.width;
    if (width >= 900) return base;
    return base * 0.85;
  }

  @override
  Widget build(BuildContext context) {
    final episodes = _episodesBySeason[_selectedSeason] ?? <Map<String, dynamic>>[];

    return PopScope(
      canPop: true,
      child: Scaffold(
        backgroundColor: const Color(0xFF121212),
        appBar: AppBar(
          backgroundColor: const Color(0xFF0F0F1A),
          elevation: 0,
          leading: BackButton(color: Colors.white.withValues(alpha: 0.9)),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildHeroHeader(),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildInfoSection(),
                          const SizedBox(height: 18),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              FilledButton.icon(
                                icon: Icon(_isFavorite ? Icons.favorite : Icons.favorite_border),
                                label: Text(_isFavorite ? 'Remove from Favorites' : 'Add to Favorites'),
                                style: FilledButton.styleFrom(
                                  backgroundColor: _isFavorite ? Colors.red : null,
                                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
                                ),
                                onPressed: () async {
                                  if (_isFavorite) {
                                    await FavoritesService.remove(widget.seriesId, FavoriteType.series);
                                    if (mounted) {
                                      setState(() => _isFavorite = false);
                                    }
                                  } else {
                                    await FavoritesService.add(
                                      FavoriteEntry(
                                        id: widget.seriesId,
                                        name: _title.isEmpty ? widget.seriesName : _title,
                                        poster: _cover,
                                        type: FavoriteType.series,
                                        addedAt: DateTime.now(),
                                      ),
                                    );
                                    if (mounted) {
                                      setState(() => _isFavorite = true);
                                    }
                                  }
                                },
                              ),
                              if (_trailerUrl.trim().isNotEmpty)
                                ElevatedButton.icon(
                                  onPressed: _openTrailer,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF00A86B),
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
                                  ),
                                  icon: const Icon(Icons.ondemand_video, size: 18),
                                  label: const Text('Play Trailer'),
                                ),
                            ],
                          ),
                          const SizedBox(height: 18),
                          _buildSeasons(),
                          const SizedBox(height: 12),
                          if (episodes.isEmpty)
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 24),
                              child: Center(
                                child: Text(
                                  'No episodes found',
                                  style: TextStyle(color: Colors.white54),
                                ),
                              ),
                            )
                          else
                            _buildEpisodesList(episodes),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildHeroHeader() {
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.35,
      width: double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.network(
            _cover,
            cacheWidth: 300,
            cacheHeight: 450,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Container(
              color: const Color(0xFF171717),
              child: const Icon(Icons.tv, color: Colors.white30, size: 64),
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  Colors.black.withValues(alpha: 0.35),
                  Colors.black.withValues(alpha: 0.88),
                ],
                stops: const [0.38, 0.62, 1],
              ),
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 18,
            child: Text(
              _title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white,
                fontSize: _getFontSize(context, 30),
                fontWeight: FontWeight.w800,
                letterSpacing: 0.2,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 16,
          runSpacing: 8,
          children: [
            _buildMetaRow('Rating', _rating.isEmpty ? 'N/A' : _rating, withStars: true),
            _buildMetaRow('Release', _releaseDate.isEmpty ? 'N/A' : _releaseDate),
            _buildMetaRow('Genre', _genre.isEmpty ? 'N/A' : _genre),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          'Plot',
          style: TextStyle(color: Colors.white, fontSize: _getFontSize(context, 16), fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        Text(
          _plot.isEmpty ? 'No description available.' : _plot,
          maxLines: _isPlotExpanded ? null : 4,
          overflow: _isPlotExpanded ? TextOverflow.visible : TextOverflow.ellipsis,
          style: TextStyle(color: Colors.white70, fontSize: _getFontSize(context, 14), height: 1.45),
        ),
        if (_plot.length > 210)
          TextButton(
            onPressed: () => setState(() => _isPlotExpanded = !_isPlotExpanded),
            style: TextButton.styleFrom(padding: EdgeInsets.zero, foregroundColor: const Color(0xFF00C6FF)),
            child: Text(_isPlotExpanded ? 'Read less' : 'Read more'),
          ),
        const SizedBox(height: 12),
        Text(
          'Cast',
          style: TextStyle(color: Colors.white, fontSize: _getFontSize(context, 16), fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 38,
          child: _castMembers.isEmpty
              ? const Align(
                  alignment: Alignment.centerLeft,
                  child: Text('N/A', style: TextStyle(color: Colors.white54)),
                )
              : ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemBuilder: (context, index) => Chip(
                    backgroundColor: const Color(0xFF1F2430),
                    side: BorderSide.none,
                    label: Text(
                      _castMembers[index],
                      style: TextStyle(color: Colors.white70, fontSize: _getFontSize(context, 12)),
                    ),
                  ),
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemCount: _castMembers.length,
                ),
        ),
        const SizedBox(height: 14),
        _buildMetaRow('Director', _director.isEmpty ? 'N/A' : _director),
      ],
    );
  }

  Widget _buildSeasons() {
    if (_seasons.isEmpty) {
      return const SizedBox.shrink();
    }

    return SizedBox(
      height: 38,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _seasons.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final season = _seasons[index];
          final isSelected = season == _selectedSeason;
          return ChoiceChip(
            label: Text('Season $season'),
            selected: isSelected,
            selectedColor: const Color(0xFF0077B6),
            labelStyle: TextStyle(
              color: isSelected ? Colors.white : Colors.white70,
              fontWeight: FontWeight.w600,
            ),
            backgroundColor: const Color(0xFF1F2430),
            onSelected: (_) {
              setState(() {
                _selectedSeason = season;
              });
            },
          );
        },
      ),
    );
  }

  Widget _buildEpisodesList(List<Map<String, dynamic>> episodes) {
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: episodes.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final episode = episodes[index];
        final episodeId = int.tryParse(episode['id']?.toString() ?? '') ?? 0;
        final episodeNum = episode['episode_num']?.toString() ?? '-';
        final title = episode['title']?.toString() ?? 'Episode';

        final infoRaw = episode['info'];
        String duration = '';
        if (infoRaw is Map) {
          duration = infoRaw['duration']?.toString() ?? '';
        }

        return FutureBuilder<WatchProgressEntry?>(
          future: episodeId > 0 ? WatchProgressService.getProgress(episodeId) : Future.value(null),
          builder: (context, snapshot) {
            final progress = snapshot.data;
            final hasProgress = progress != null;

            return InkWell(
              onTap: () => _playEpisode(episode, _selectedSeason),
              borderRadius: BorderRadius.circular(12),
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF1A1A2E),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white10),
                ),
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      child: Row(
                        children: [
                          Text(
                            'E$episodeNum',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                if (duration.trim().isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 2),
                                    child: Text(
                                      duration,
                                      style: const TextStyle(color: Colors.white60, fontSize: 12),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          IconButton(
                            onPressed: () => _playEpisode(episode, _selectedSeason),
                            icon: const Icon(Icons.play_circle, color: Colors.white, size: 30),
                          ),
                        ],
                      ),
                    ),
                    if (hasProgress)
                      SizedBox(
                        height: 3,
                        width: double.infinity,
                        child: LinearProgressIndicator(
                          value: progress.progressPercent.clamp(0.0, 1.0),
                          backgroundColor: Colors.white12,
                          valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF00C6FF)),
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildMetaRow(String label, String value, {bool withStars = false}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$label: ',
          style: const TextStyle(color: Colors.white60, fontSize: 13, fontWeight: FontWeight.w600),
        ),
        if (withStars)
          ...List<Widget>.generate(5, (index) {
            final filled = index < (_ratingValue / 2).floor();
            return Icon(
              Icons.star,
              size: 14,
              color: filled ? Colors.amber : Colors.white24,
            );
          }),
        if (withStars) const SizedBox(width: 6),
        Text(
          value,
          style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}
