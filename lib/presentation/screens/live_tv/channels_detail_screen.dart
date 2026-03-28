import 'dart:async';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import '../../../data/datasources/remote/xtream_api.dart';
import '../../../data/models/channel.dart';
import '../../../data/models/live_tv_category.dart';
import '../../../utils/favorites_manager.dart';

class ChannelsDetailScreen extends StatefulWidget {
  final XtreamApi xtreamApi;
  final LiveTvCategory category;

  const ChannelsDetailScreen({
    super.key,
    required this.xtreamApi,
    required this.category,
  });

  @override
  State<ChannelsDetailScreen> createState() =>
      _ChannelsDetailScreenState();
}

class _ChannelsDetailScreenState extends State<ChannelsDetailScreen> {
  late Future<List<Channel>> _channelsFuture;
  int _selectedChannelIndex = 0;
  late final Player _player;
  late final VideoController _controller;
  bool _isFavorite = false;
  bool _isBuffering = false;
  bool _hasError = false;
  String _resolution = '';
  String _fps = '';
  String _errorMessage = '';
  bool _usingM3u8 = false;
  int _retryCount = 0;
  static const int _maxRetries = 3;

  StreamSubscription? _bufferingSubscription;
  StreamSubscription? _videoParamsSubscription;
  StreamSubscription? _tracksSubscription;
  StreamSubscription? _errorSubscription;
  Timer? _fallbackTimer;
  Timer? _retryTimer;

  @override
  void initState() {
    super.initState();

    _player = Player(
      configuration: const PlayerConfiguration(
        bufferSize: 32 * 1024 * 1024,
        logLevel: MPVLogLevel.warn,
      ),
    );

    _controller = VideoController(
      _player,
      configuration: const VideoControllerConfiguration(
        enableHardwareAcceleration: true,
      ),
    );

    _setupListeners();
    _channelsFuture = _loadChannels();
  }

  void _setupListeners() {
    _bufferingSubscription =
        _player.stream.buffering.listen((buffering) {
      if (mounted) setState(() => _isBuffering = buffering);
    });

    _videoParamsSubscription =
        _player.stream.videoParams.listen((params) {
      if (mounted && params.w != null && params.h != null) {
        _fallbackTimer?.cancel();
        _retryTimer?.cancel();
        setState(() {
          _resolution = '${params.w}x${params.h}';
          _hasError = false;
          _isBuffering = false;
          _retryCount = 0;
        });
      }
    });

    _tracksSubscription = _player.stream.tracks.listen((tracks) {
      if (mounted && tracks.video.isNotEmpty) {
        for (final track in tracks.video) {
          if (track.fps != null && track.fps! > 0) {
            if (mounted) {
              setState(() {
                _fps = '${track.fps!.toStringAsFixed(0)} FPS';
              });
            }
            break;
          }
        }
      }
    });

    _errorSubscription = _player.stream.error.listen((error) {
      if (mounted && error.isNotEmpty) {
        debugPrint('Player error: $error');
        _handleError();
      }
    });
  }

  void _handleError() {
    if (!mounted) return;
    _fallbackTimer?.cancel();

    if (!_usingM3u8) {
      // Try m3u8 first
      debugPrint('Switching to m3u8...');
      _channelsFuture.then((channels) {
        if (mounted && channels.isNotEmpty) {
          _tryM3u8Fallback(channels[_selectedChannelIndex]);
        }
      });
    } else if (_retryCount < _maxRetries) {
      // Retry same stream
      _retryCount++;
      debugPrint('Retry $_retryCount/$_maxRetries...');
      _retryTimer = Timer(const Duration(seconds: 2), () {
        if (mounted) {
          _channelsFuture.then((channels) {
            if (mounted && channels.isNotEmpty) {
              _playStream(channels[_selectedChannelIndex]);
            }
          });
        }
      });
    } else {
      // Give up
      setState(() {
        _hasError = true;
        _errorMessage = 'Stream unavailable';
        _isBuffering = false;
      });
    }
  }

  Future<List<Channel>> _loadChannels() async {
    final rawChannels = await widget.xtreamApi.getLiveStreams(
      categoryId: widget.category.id,
    );
    final channels = rawChannels
        .map((json) => Channel.fromJson(
              json,
              widget.xtreamApi.serverUrl,
              widget.xtreamApi.username,
              widget.xtreamApi.password,
            ))
        .toList();

    if (channels.isNotEmpty) {
      await _playStream(channels[0]);
      await _loadFavoriteStatus(channels[0].id.toString());
    }

    return channels;
  }

  Future<void> _playStream(Channel channel) async {
    _fallbackTimer?.cancel();
    _retryTimer?.cancel();
    _usingM3u8 = false;
    _retryCount = 0;

    if (mounted) {
      setState(() {
        _hasError = false;
        _isBuffering = true;
        _resolution = '';
        _fps = '';
        _errorMessage = '';
      });
    }

    try {
      await _player.open(
        Media(
          channel.streamUrl,
          httpHeaders: {
            'User-Agent':
                'Mozilla/5.0 (Windows NT 10.0; Win64; x64)',
            'Connection': 'keep-alive',
          },
        ),
        play: true,
      );

      // If no video after 8 seconds try m3u8
      _fallbackTimer = Timer(const Duration(seconds: 8), () {
        if (mounted && _resolution.isEmpty && !_hasError) {
          debugPrint('No video after 8s, trying m3u8...');
          _tryM3u8Fallback(channel);
        }
      });
    } catch (e) {
      debugPrint('playStream error: $e');
      _tryM3u8Fallback(channel);
    }
  }

  Future<void> _tryM3u8Fallback(Channel channel) async {
    if (!mounted) return;
    _fallbackTimer?.cancel();
    _usingM3u8 = true;

    debugPrint('Trying m3u8: ${channel.streamUrlM3u8}');

    if (mounted) {
      setState(() {
        _isBuffering = true;
        _hasError = false;
        _resolution = '';
      });
    }

    try {
      await _player.open(
        Media(
          channel.streamUrlM3u8,
          httpHeaders: {
            'User-Agent':
                'Mozilla/5.0 (Windows NT 10.0; Win64; x64)',
            'Connection': 'keep-alive',
          },
        ),
        play: true,
      );

      // If still no video after 8 seconds show error
      _fallbackTimer = Timer(const Duration(seconds: 8), () {
        if (mounted && _resolution.isEmpty) {
          setState(() {
            _hasError = true;
            _errorMessage = 'Stream unavailable';
            _isBuffering = false;
          });
        }
      });
    } catch (e) {
      debugPrint('m3u8 error: $e');
      if (mounted) {
        setState(() {
          _hasError = true;
          _errorMessage = 'Stream unavailable';
          _isBuffering = false;
        });
      }
    }
  }

  Future<void> _loadFavoriteStatus(String channelId) async {
    final fav = await FavoritesManager.isFavorite(channelId);
    if (mounted) setState(() => _isFavorite = fav);
  }

  void _toggleFavorite(Channel channel) async {
    if (_isFavorite) {
      await FavoritesManager.removeFavorite(channel.id.toString());
    } else {
      await FavoritesManager.addFavorite(channel.id.toString());
    }
    if (mounted) setState(() => _isFavorite = !_isFavorite);
  }

  void _onChannelSelected(Channel channel, int index) async {
    if (_selectedChannelIndex == index) return;
    setState(() {
      _selectedChannelIndex = index;
      _isBuffering = true;
      _hasError = false;
      _resolution = '';
      _fps = '';
    });
    await _playStream(channel);
    await _loadFavoriteStatus(channel.id.toString());
  }

  void _retryStream(List<Channel> channels) {
    _retryCount = 0;
    _usingM3u8 = false;
    _fallbackTimer?.cancel();
    _retryTimer?.cancel();
    _playStream(channels[_selectedChannelIndex]);
  }

  @override
  void dispose() {
    _fallbackTimer?.cancel();
    _retryTimer?.cancel();
    _bufferingSubscription?.cancel();
    _videoParamsSubscription?.cancel();
    _tracksSubscription?.cancel();
    _errorSubscription?.cancel();
    _player.dispose();
    super.dispose();
  }  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: const Color(0xFF1E1E1E),
      appBar: AppBar(
        title: Text(widget.category.name),
        backgroundColor: const Color(0xFF0F0F1A),
        elevation: 0,
      ),
      body: FutureBuilder<List<Channel>>(
        future: _channelsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Loading channels...'),
                ],
              ),
            );
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(child: Text('No channels found'));
          }

          final channels = snapshot.data!;
          final selectedChannel = channels[_selectedChannelIndex];

          return Row(
            children: [
              // Left: Channel List 30%
              Container(
                width: size.width * 0.3,
                color: const Color(0xFF0F0F1A),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      color: const Color(0xFF07070F),
                      width: double.infinity,
                      child: Text(
                        '${channels.length} Channels',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    Expanded(
                      child: ListView.builder(
                        itemCount: channels.length,
                        itemBuilder: (context, index) {
                          final channel = channels[index];
                          final isSelected =
                              index == _selectedChannelIndex;
                          return Material(
                            color: isSelected
                                ? const Color(0xFF1A3A5C)
                                : Colors.transparent,
                            child: InkWell(
                              onTap: () =>
                                  _onChannelSelected(channel, index),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 40,
                                      height: 40,
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF1E1E2E),
                                        borderRadius:
                                            BorderRadius.circular(6),
                                      ),
                                      child: channel.logoUrl.isNotEmpty
                                          ? ClipRRect(
                                              borderRadius:
                                                  BorderRadius.circular(
                                                      6),
                                              child: Image.network(
                                                channel.logoUrl,
                                                fit: BoxFit.contain,
                                                errorBuilder:
                                                    (_, __, ___) =>
                                                        const Icon(
                                                  Icons.tv,
                                                  color: Colors.white54,
                                                  size: 20,
                                                ),
                                              ),
                                            )
                                          : const Icon(
                                              Icons.tv,
                                              color: Colors.white54,
                                              size: 20,
                                            ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        channel.name,
                                        style: TextStyle(
                                          color: isSelected
                                              ? Colors.white
                                              : Colors.white70,
                                          fontSize: 13,
                                          fontWeight: isSelected
                                              ? FontWeight.bold
                                              : FontWeight.normal,
                                        ),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    if (isSelected)
                                      const Icon(
                                        Icons.play_arrow,
                                        color: Colors.blue,
                                        size: 16,
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),

              // Right: Video + Info 70%
              Expanded(
                child: Column(
                  children: [
                    // Video Player
                    Container(
                      height:
                          (size.height - kToolbarHeight) * 0.62,
                      color: Colors.black,
                      child: Stack(
                        children: [
                          SizedBox.expand(
                            child: Video(
                              controller: _controller,
                              fit: BoxFit.contain,
                            ),
                          ),

                          // Buffering overlay
                          if (_isBuffering && !_hasError)
                            Container(
                              color: Colors.black87,
                              child: Center(
                                child: Column(
                                  mainAxisAlignment:
                                      MainAxisAlignment.center,
                                  children: [
                                    const CircularProgressIndicator(
                                      color: Colors.white,
                                      strokeWidth: 2,
                                    ),
                                    const SizedBox(height: 12),
                                    Text(
                                      'Loading ${selectedChannel.name}...',
                                      style: const TextStyle(
                                        color: Colors.white70,
                                        fontSize: 13,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    if (_usingM3u8)
                                      const Text(
                                        'Trying HLS stream...',
                                        style: TextStyle(
                                          color: Colors.white38,
                                          fontSize: 11,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),

                          // Error overlay
                          if (_hasError)
                            Container(
                              color: Colors.black87,
                              child: Center(
                                child: Column(
                                  mainAxisAlignment:
                                      MainAxisAlignment.center,
                                  children: [
                                    const Icon(
                                      Icons.error_outline,
                                      color: Colors.red,
                                      size: 48,
                                    ),
                                    const SizedBox(height: 12),
                                    Text(
                                      _errorMessage,
                                      style: const TextStyle(
                                        color: Colors.white70,
                                      ),
                                    ),
                                    const SizedBox(height: 16),
                                    ElevatedButton.icon(
                                      onPressed: () =>
                                          _retryStream(channels),
                                      icon: const Icon(Icons.refresh),
                                      label: const Text('Retry'),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.blue,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),

                          // Resolution/FPS overlay
                          if (_resolution.isNotEmpty ||
                              _fps.isNotEmpty)
                            Positioned(
                              top: 8,
                              right: 8,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color:
                                      Colors.black.withValues(alpha: 0.7),
                                  borderRadius:
                                      BorderRadius.circular(6),
                                ),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.end,
                                  children: [
                                    if (_resolution.isNotEmpty)
                                      Text(
                                        _resolution,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    if (_fps.isNotEmpty)
                                      Text(
                                        _fps,
                                        style: const TextStyle(
                                          color: Colors.white70,
                                          fontSize: 11,
                                        ),
                                      ),
                                    if (_usingM3u8)
                                      const Text(
                                        'HLS',
                                        style: TextStyle(
                                          color: Colors.greenAccent,
                                          fontSize: 10,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),

                    // Info Panel
                    Expanded(
                      child: Container(
                        color: const Color(0xFF1E1E1E),
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Channel name and logo
                            Row(
                              children: [
                                if (selectedChannel.logoUrl.isNotEmpty)
                                  Container(
                                    width: 50,
                                    height: 50,
                                    margin: const EdgeInsets.only(
                                        right: 12),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF0F0F1A),
                                      borderRadius:
                                          BorderRadius.circular(8),
                                    ),
                                    child: ClipRRect(
                                      borderRadius:
                                          BorderRadius.circular(8),
                                      child: Image.network(
                                        selectedChannel.logoUrl,
                                        fit: BoxFit.contain,
                                        errorBuilder: (_, __, ___) =>
                                            const Icon(
                                          Icons.tv,
                                          color: Colors.white54,
                                        ),
                                      ),
                                    ),
                                  ),
                                Expanded(
                                  child: Text(
                                    selectedChannel.name,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),

                            const SizedBox(height: 12),

                            // Stream info chips
                            Row(
                              children: [
                                if (_resolution.isNotEmpty)
                                  _infoChip(Icons.hd, _resolution),
                                if (_resolution.isNotEmpty)
                                  const SizedBox(width: 8),
                                if (_fps.isNotEmpty)
                                  _infoChip(Icons.speed, _fps),
                                if (_fps.isNotEmpty)
                                  const SizedBox(width: 8),
                                if (_usingM3u8)
                                  _infoChip(Icons.stream, 'HLS'),
                              ],
                            ),

                            const SizedBox(height: 16),

                            // EPG placeholder
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: const Color(0xFF0F0F1A),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Row(
                                children: [
                                  Icon(
                                    Icons.tv_outlined,
                                    color: Colors.white54,
                                    size: 16,
                                  ),
                                  SizedBox(width: 8),
                                  Text(
                                    'EPG: No guide available',
                                    style: TextStyle(
                                      color: Colors.white54,
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            const SizedBox(height: 16),

                            // Favorite button
                            ElevatedButton.icon(
                              onPressed: () =>
                                  _toggleFavorite(selectedChannel),
                              icon: Icon(
                                _isFavorite
                                    ? Icons.favorite
                                    : Icons.favorite_border,
                                color: _isFavorite
                                    ? Colors.red
                                    : Colors.white,
                              ),
                              label: Text(
                                _isFavorite
                                    ? 'Remove from Favorites'
                                    : 'Add to Favorites',
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor:
                                    const Color(0xFF1A1A2E),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 20,
                                  vertical: 12,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _infoChip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 10,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFF0F0F1A),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white54, size: 14),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}