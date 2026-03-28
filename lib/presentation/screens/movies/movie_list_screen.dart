import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../data/datasources/remote/xtream_api.dart';
import '../../../data/models/movie_item.dart';
import '../../../data/services/favorites_service.dart';
import '../../../data/services/watch_progress_service.dart';
import 'movie_detail_screen.dart';

class MovieListScreen extends StatefulWidget {
  final XtreamApi xtreamApi;
  final int categoryId;
  final String categoryName;

  const MovieListScreen({
    super.key,
    required this.xtreamApi,
    required this.categoryId,
    required this.categoryName,
  });

  @override
  State<MovieListScreen> createState() => _MovieListScreenState();
}

class _MovieListScreenState extends State<MovieListScreen> {
  static const int _pageSize = 50;
  final TextEditingController _searchController = TextEditingController();

  bool _isLoading = true;
  String? _errorMessage;
  String _searchQuery = '';
  List<MovieItem> _movies = <MovieItem>[];
  int _currentPage = 0;
  bool _hasMore = true;

  bool get _isContinueWatching => widget.categoryId == -2;
  bool get _isFavorites => widget.categoryId == -3;

  @override
  void initState() {
    super.initState();
    _loadMovies();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadMovies() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    if (_isFavorites) {
      try {
        final entries = await FavoritesService.getAll(FavoriteType.movie);
        if (!mounted) {
          return;
        }
        setState(() {
          _isLoading = false;
          _movies = entries
              .map(
                (entry) => MovieItem(
                  streamId: entry.id,
                  title: entry.name,
                  posterUrl: entry.poster ?? '',
                  description: '',
                  genre: '',
                  rating: '',
                  year: '',
                  containerExtension: 'mp4',
                ),
              )
              .toList();
        });
      } catch (_) {
        if (!mounted) {
          return;
        }
        setState(() {
          _isLoading = false;
          _errorMessage = 'Failed to load favorite movies.';
          _movies = <MovieItem>[];
        });
      }
      return;
    }

    if (_isContinueWatching) {
      try {
        final entries = await WatchProgressService.getAllProgress();
        if (!mounted) {
          return;
        }
        setState(() {
          _isLoading = false;
          _errorMessage = null;
          _movies = entries
              .map(
                (entry) => MovieItem(
                  streamId: entry.streamId,
                  title: entry.title,
                  posterUrl: entry.poster ?? '',
                  description: '',
                  genre: '',
                  rating: '',
                  year: '',
                  containerExtension: 'mp4',
                ),
              )
              .toList();
        });
      } catch (_) {
        if (!mounted) {
          return;
        }
        setState(() {
          _isLoading = false;
          _errorMessage = 'Failed to load continue watching movies.';
          _movies = <MovieItem>[];
        });
      }
      return;
    }

    try {
      final List<Map<String, dynamic>> rawStreams;
      if (widget.categoryId == -1) {
        rawStreams = await widget.xtreamApi.getVodStreamsStrict();
      } else {
        rawStreams = await widget.xtreamApi.getVodStreamsStrict(
          categoryId: widget.categoryId,
        );
      }

      final movies = rawStreams.map((json) => MovieItem.fromJson(json)).toList();

      if (!mounted) {
        return;
      }

      setState(() {
        _movies = movies;
        _currentPage = 0;
        _hasMore = movies.length > _pageSize;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = 'Failed to load movies. Please try again.';
        _isLoading = false;
      });
    }
  }

  List<MovieItem> get _filteredMovies {
    if (_searchQuery.isEmpty) {
      return _movies;
    }
    final lowerQuery = _searchQuery.toLowerCase();
    return _movies.where((movie) => movie.title.toLowerCase().contains(lowerQuery)).toList();
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
                  hintText: 'Search movies...',
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
                              _hasMore = _movies.length > _pageSize;
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
                  _hasMore = _filteredMovies.length > _pageSize;
                }),
              ),
            ),
            Expanded(
              child: _buildBody(context),
            ),
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
              onPressed: _loadMovies,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    final filteredMovies = _filteredMovies;

    if (filteredMovies.isEmpty) {
      if (_isFavorites) {
        return Center(
          child: Text(
            'No favorite movies yet',
            style: TextStyle(color: Colors.white54, fontSize: _getFontSize(context, 16)),
          ),
        );
      }
      if (_isContinueWatching) {
        return Center(
          child: Text(
            'No movies in Continue Watching yet',
            style: TextStyle(color: Colors.white54, fontSize: _getFontSize(context, 16)),
          ),
        );
      }
      return Center(
        child: Text(
          'No movies found',
          style: TextStyle(color: Colors.white54, fontSize: _getFontSize(context, 16)),
        ),
      );
    }

    final end = ((_currentPage + 1) * _pageSize).clamp(0, filteredMovies.length);
    final paginatedMovies = filteredMovies.take(end).toList();
    _hasMore = end < filteredMovies.length;

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
              (context, index) => _MovieCard(
                movie: paginatedMovies[index],
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => MovieDetailScreen(
                        xtreamApi: widget.xtreamApi,
                        movie: paginatedMovies[index],
                      ),
                    ),
                  );
                },
              ),
              childCount: paginatedMovies.length,
            ),
          ),
        ),
        if (_hasMore && filteredMovies.length > _pageSize)
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
}

class _MovieCard extends StatefulWidget {
  final MovieItem movie;
  final VoidCallback onTap;

  const _MovieCard({required this.movie, required this.onTap});

  @override
  State<_MovieCard> createState() => _MovieCardState();
}

class _MovieCardState extends State<_MovieCard> {
  bool _isHovering = false;

  @override
  Widget build(BuildContext context) {
    final enableHover = kIsWeb ||
        defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.linux;

    return FutureBuilder<WatchProgressEntry?>(
      future: WatchProgressService.getProgress(widget.movie.streamId),
      builder: (context, snapshot) {
        final progress = snapshot.data;
        final progressValue = (progress?.progressPercent ?? 0.0).clamp(0.0, 1.0);

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
                                  widget.movie.posterUrl,
                                  cacheWidth: 400,
                                  cacheHeight: 450,
                                  filterQuality: FilterQuality.low,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => Container(
                                    color: Colors.white10,
                                    child: const Icon(Icons.movie, color: Colors.white38, size: 30),
                                  ),
                                ),
                              ),
                              Positioned(
                                top: 6,
                                left: 6,
                                child: FutureBuilder<bool>(
                                  future: FavoritesService.isFavorite(
                                    widget.movie.streamId,
                                    FavoriteType.movie,
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
                                        widget.movie.rating.isEmpty ? '-' : widget.movie.rating,
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
                            widget.movie.title,
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
                        if (progress != null)
                          SizedBox(
                            height: 4,
                            child: LinearProgressIndicator(
                              value: progressValue,
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
      },
    );
  }

}
