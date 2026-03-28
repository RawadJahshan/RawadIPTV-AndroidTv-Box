import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../data/datasources/remote/xtream_api.dart';
import '../../../data/models/movie_item.dart';
import '../../../data/services/favorites_service.dart';
import '../../../data/services/watch_progress_service.dart';
import '../player/movie_player_screen.dart';

class MovieDetailScreen extends StatefulWidget {
  final XtreamApi xtreamApi;
  final MovieItem movie;

  const MovieDetailScreen({
    super.key,
    required this.xtreamApi,
    required this.movie,
  });

  @override
  State<MovieDetailScreen> createState() => _MovieDetailScreenState();
}

class _MovieDetailScreenState extends State<MovieDetailScreen> {
  bool _loading = true;
  bool _isPlotExpanded = false;
  bool _isFavorite = false;

  late String _title;
  late String _posterUrl;
  String _plot = '';
  String _genre = '';
  String _director = '';
  String _cast = '';
  String _releaseDate = '';
  String _rating = '';
  int? _durationMinutes;
  String _trailerUrl = '';

  @override
  void initState() {
    super.initState();
    _title = widget.movie.title;
    _posterUrl = widget.movie.posterUrl;
    _plot = widget.movie.description;
    _genre = widget.movie.genre;
    _rating = widget.movie.rating;
    _loadFavoriteStatus();
    _load();
  }

  Future<void> _loadFavoriteStatus() async {
    final movie = widget.movie;
    final fav = await FavoritesService.isFavorite(movie.streamId, FavoriteType.movie);
    if (mounted) {
      setState(() => _isFavorite = fav);
    }
  }

  Future<void> _load() async {
    try {
      final vodInfo = await widget.xtreamApi.getVodInfo(widget.movie.streamId);
      final info = vodInfo['info'];
      if (info is Map) {
        _plot = _pick(info, ['plot', 'description'], fallback: _plot);
        _genre = _pick(info, ['genre'], fallback: _genre);
        _director = _pick(info, ['director']);
        _cast = _pick(info, ['cast']);
        _releaseDate = _pick(info, ['releaseDate', 'release_date', 'releasedate']);
        _rating = _pick(info, ['vote_average', 'rating'], fallback: _rating);
        _trailerUrl = _pick(info, ['trailer_url', 'youtube_trailer']);

        final durationSecs = _asInt(info['duration_secs']);
        final durationMins = _asInt(info['duration']);
        if (durationSecs != null && durationSecs > 0) {
          _durationMinutes = (durationSecs / 60).round();
        } else if (durationMins != null && durationMins > 0) {
          _durationMinutes = durationMins;
        }

        final fetchedTitle = _pick(info, ['name', 'title']);
        if (fetchedTitle.isNotEmpty) {
          _title = fetchedTitle;
        }

        final fetchedPoster = _pick(info, ['stream_icon', 'movie_image']);
        if (fetchedPoster.isNotEmpty) {
          _posterUrl = fetchedPoster;
        }
      }
    } catch (_) {
      // Keep fallback movie values when details endpoint has sparse data.
    }

    if (!mounted) return;
    setState(() {
      _loading = false;
    });
  }

  String _pick(Map<dynamic, dynamic> map, List<String> keys, {String fallback = ''}) {
    for (final key in keys) {
      final value = map[key];
      if (value != null) {
        final normalized = value.toString().trim();
        if (normalized.isNotEmpty) {
          return normalized;
        }
      }
    }
    return fallback;
  }

  int? _asInt(dynamic value) {
    if (value == null) return null;
    return int.tryParse(value.toString());
  }

  double get _ratingValue => double.tryParse(_rating) ?? 0;

  List<String> get _castMembers => _cast
      .split(RegExp(r'[,/|]'))
      .map((name) => name.trim())
      .where((name) => name.isNotEmpty)
      .toList();

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



  Future<void> _onPlayNow() async {
    final movie = widget.movie;
    final progress = await WatchProgressService.getProgress(movie.streamId);

    if (!mounted) return;

    final streamUrl = movie.streamUrl(
      widget.xtreamApi.serverUrl,
      widget.xtreamApi.username,
      widget.xtreamApi.password,
    );

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
      if (resume == null || !mounted) return;

      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => MoviePlayerScreen(
            streamUrl: streamUrl,
            title: _title,
            streamId: movie.streamId,
            poster: _posterUrl,
            startAt: resume ? progress.position : null,
          ),
        ),
      );
      return;
    }

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MoviePlayerScreen(
          streamUrl: streamUrl,
          title: _title,
          streamId: movie.streamId,
          poster: _posterUrl,
          startAt: null,
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
                        _buildActionButtons(),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildHeroHeader() {
    return SizedBox(
      height: 320,
      width: double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.network(
            _posterUrl,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Container(
              color: const Color(0xFF171717),
              child: const Icon(Icons.movie_creation_outlined, color: Colors.white30, size: 64),
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
              style: const TextStyle(
                color: Colors.white,
                fontSize: 30,
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
            _buildMetaRow('Duration', _durationMinutes == null ? 'N/A' : '${_durationMinutes} min'),
            _buildMetaRow('Genre', _genre.isEmpty ? 'N/A' : _genre),
          ],
        ),
        const SizedBox(height: 16),
        const Text(
          'Plot',
          style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        Text(
          _plot.isEmpty ? 'No description available.' : _plot,
          maxLines: _isPlotExpanded ? null : 4,
          overflow: _isPlotExpanded ? TextOverflow.visible : TextOverflow.ellipsis,
          style: const TextStyle(color: Colors.white70, fontSize: 14, height: 1.45),
        ),
        if (_plot.length > 210)
          TextButton(
            onPressed: () => setState(() => _isPlotExpanded = !_isPlotExpanded),
            style: TextButton.styleFrom(padding: EdgeInsets.zero, foregroundColor: const Color(0xFF00C6FF)),
            child: Text(_isPlotExpanded ? 'Read less' : 'Read more'),
          ),
        const SizedBox(height: 12),
        const Text(
          'Cast',
          style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700),
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
                      style: const TextStyle(color: Colors.white70, fontSize: 12),
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

  Widget _buildActionButtons() {
    final hasTrailer = _trailerUrl.trim().isNotEmpty;

    return Row(
      children: [
        Expanded(
          child: ElevatedButton.icon(
            onPressed: _onPlayNow,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0077B6),
              disabledBackgroundColor: const Color(0xFF0077B6),
              foregroundColor: Colors.white,
              disabledForegroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
            icon: const Icon(Icons.play_circle_fill, size: 18),
            label: const Text('Play Now'),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: FilledButton.icon(
            icon: Icon(_isFavorite ? Icons.favorite : Icons.favorite_border),
            label: Text(_isFavorite ? 'Remove from Favorites' : 'Add to Favorites'),
            style: FilledButton.styleFrom(
              backgroundColor: _isFavorite ? Colors.red : null,
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
            onPressed: () async {
              final movie = widget.movie;
              if (_isFavorite) {
                await FavoritesService.remove(movie.streamId, FavoriteType.movie);
                if (mounted) {
                  setState(() => _isFavorite = false);
                }
              } else {
                await FavoritesService.add(
                  FavoriteEntry(
                    id: movie.streamId,
                    name: movie.title,
                    poster: movie.posterUrl,
                    type: FavoriteType.movie,
                    addedAt: DateTime.now(),
                  ),
                );
                if (mounted) {
                  setState(() => _isFavorite = true);
                }
              }
            },
          ),
        ),
        if (hasTrailer) ...[
          const SizedBox(width: 8),
          Expanded(
            child: ElevatedButton.icon(
              onPressed: _openTrailer,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00A86B),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              icon: const Icon(Icons.ondemand_video, size: 18),
              label: const Text('Play Trailer'),
            ),
          ),
        ],
      ],
    );
  }
}
