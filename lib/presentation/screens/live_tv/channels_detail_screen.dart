import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../data/datasources/remote/xtream_api.dart';
import '../../../data/models/channel.dart';
import '../../../data/models/live_tv_category.dart';
import '../../../data/services/catalog_cache_service.dart';
import '../../../data/services/native_live_player.dart';
import '../../../utils/favorites_manager.dart';

class ChannelsDetailScreen extends StatefulWidget {
  final XtreamApi xtreamApi;
  final String profileId;
  final LiveTvCategory category;

  const ChannelsDetailScreen({
    super.key,
    required this.xtreamApi,
    required this.profileId,
    required this.category,
  });

  @override
  State<ChannelsDetailScreen> createState() => _ChannelsDetailScreenState();
}

class _ChannelsDetailScreenState extends State<ChannelsDetailScreen> {
  static const int _maxRetries = 3;
  static const Duration _fallbackTimeout = Duration(seconds: 8);
  static const Duration _watchdogInterval = Duration(seconds: 10);
  static const Duration _watchdogStallThreshold = Duration(seconds: 25);
  static const Map<String, String> _streamHttpHeaders = {
    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)',
    'Connection': 'keep-alive',
  };

  late Future<List<Channel>> _channelsFuture;
  final FocusScopeNode _screenFocusScope = FocusScopeNode();
  final FocusNode _screenFocusNode = FocusNode(debugLabel: 'LiveDetailScreen');
  final FocusNode _playerFocusNode = FocusNode(debugLabel: 'LiveMiniPlayer');
  final FocusNode _favoriteFocusNode = FocusNode(debugLabel: 'LiveFavorite');
  final ScrollController _channelScrollController = ScrollController();
  final List<FocusNode> _channelFocusNodes = <FocusNode>[];

  NativeLivePlayer? _nativePlayer;
  StreamSubscription<bool>? _bufferingSubscription;
  StreamSubscription<({int width, int height})>? _videoSizeSubscription;
  StreamSubscription<double>? _fpsSubscription;
  StreamSubscription<String>? _errorSubscription;
  StreamSubscription<bool>? _playingSubscription;
  StreamSubscription<int>? _positionSubscription;
  StreamSubscription<void>? _firstFrameSubscription;
  Timer? _fallbackTimer;
  Timer? _retryTimer;
  Timer? _watchdogTimer;

  int _selectedChannelIndex = 0;
  int? _activeChannelId;
  bool _playerInitialized = false;
  bool _isFullscreen = false;
  bool _isBuffering = false;
  bool _hasVideoFrame = false;
  bool _isPlaying = false;
  bool _hasError = false;
  bool _usingHlsFallback = false;
  bool _isFavorite = false;
  int _retryCount = 0;
  DateTime _lastPlaybackProgressAt = DateTime.now();
  String _errorMessage = '';
  String _resolutionText = '--';
  String _fpsText = '--';

  @override
  void initState() {
    super.initState();
    _forceLandscape();
    _nativePlayer = NativeLivePlayer();
    _channelsFuture = _loadChannels();
    unawaited(_initializePlayer());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _forceLandscape();
  }

  @override
  void dispose() {
    _fallbackTimer?.cancel();
    _retryTimer?.cancel();
    _watchdogTimer?.cancel();
    _cancelPlayerSubscriptions();
    for (final node in _channelFocusNodes) {
      node.dispose();
    }
    _screenFocusScope.dispose();
    _screenFocusNode.dispose();
    _playerFocusNode.dispose();
    _favoriteFocusNode.dispose();
    _channelScrollController.dispose();
    _nativePlayer?.stop();
    _nativePlayer?.release();
    _nativePlayer?.dispose();
    _nativePlayer = null;
    super.dispose();
  }

  void _forceLandscape() {
    SystemChrome.setPreferredOrientations(const <DeviceOrientation>[
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  Future<void> _initializePlayer() async {
    final player = _nativePlayer;
    if (player == null) return;

    _cancelPlayerSubscriptions();
    _watchdogTimer?.cancel();

    await player.initialize();
    if (!mounted) return;

    setState(() {
      _playerInitialized = true;
    });

    _bufferingSubscription = player.bufferingStream.listen((buffering) {
      if (!mounted) return;
      setState(() {
        _isBuffering = buffering && !_hasVideoFrame && _activeChannelId != null;
      });
    });

    _videoSizeSubscription = player.videoSizeStream.listen((size) {
      if (!mounted) return;
      _lastPlaybackProgressAt = DateTime.now();
      _fallbackTimer?.cancel();
      _retryTimer?.cancel();
      setState(() {
        _hasVideoFrame = true;
        _hasError = false;
        _isBuffering = false;
        _retryCount = 0;
        _resolutionText = '${size.width}x${size.height}';
      });
    });

    _fpsSubscription = player.fpsStream.listen((fps) {
      if (!mounted) return;
      _lastPlaybackProgressAt = DateTime.now();
      setState(() {
        _fpsText = fps > 0 ? '${fps.toStringAsFixed(0)} FPS' : '--';
      });
    });

    _errorSubscription = player.errorStream.listen((error) {
      if (!mounted) return;
      _handlePlaybackFailure(error);
    });

    _playingSubscription = player.playingStream.listen((playing) {
      _isPlaying = playing;
      if (playing) {
        _lastPlaybackProgressAt = DateTime.now();
      }
    });

    _positionSubscription = player.positionStream.listen((positionMs) {
      _lastPlaybackProgressAt = DateTime.now();
    });

    _firstFrameSubscription = player.firstFrameStream.listen((_) {
      if (!mounted) return;
      _lastPlaybackProgressAt = DateTime.now();
      if (_hasVideoFrame) return;
      setState(() {
        _hasVideoFrame = true;
        _isBuffering = false;
        _hasError = false;
      });
    });

    _watchdogTimer = Timer.periodic(_watchdogInterval, (_) {
      if (!mounted || _activeChannelId == null || _hasError) return;
      if (!_isPlaying || !_hasVideoFrame) return;
      final stalledFor = DateTime.now().difference(_lastPlaybackProgressAt);
      if (stalledFor > _watchdogStallThreshold) {
        _handlePlaybackFailure('Playback stalled');
      }
    });
  }

  void _cancelPlayerSubscriptions() {
    _bufferingSubscription?.cancel();
    _videoSizeSubscription?.cancel();
    _fpsSubscription?.cancel();
    _errorSubscription?.cancel();
    _playingSubscription?.cancel();
    _positionSubscription?.cancel();
    _firstFrameSubscription?.cancel();
  }

  Future<List<Channel>> _loadChannels() async {
    var rawChannels = await CatalogCacheService.getLiveStreamsByCategory(
      widget.profileId,
      widget.category.id,
    );

    if (rawChannels.isEmpty) {
      rawChannels = await widget.xtreamApi.getLiveStreams(
        categoryId: widget.category.id,
      );
      if (rawChannels.isNotEmpty) {
        await CatalogCacheService.saveLiveStreamsByCategory(
          widget.profileId,
          widget.category.id,
          rawChannels,
        );
      }
    }

    return rawChannels
        .map(
          (json) => Channel.fromJson(
            json,
            widget.xtreamApi.serverUrl,
            widget.xtreamApi.username,
            widget.xtreamApi.password,
          ),
        )
        .toList();
  }

  Future<void> _handleChannelActivation(Channel channel, int index) async {
    final isSameChannel = _selectedChannelIndex == index;
    final isAlreadyPlaying = _activeChannelId == channel.id;

    if (isSameChannel && isAlreadyPlaying && !_hasError) {
      _enterFullscreen();
      return;
    }

    setState(() {
      _selectedChannelIndex = index;
    });

    await _playChannel(channel);
    await _loadFavoriteStatus(channel.id.toString());
  }

  Future<void> _playChannel(Channel channel, {bool preferHls = false}) async {
    final player = _nativePlayer;
    if (player == null) return;

    _fallbackTimer?.cancel();
    _retryTimer?.cancel();
    _lastPlaybackProgressAt = DateTime.now();

    setState(() {
      _activeChannelId = channel.id;
      _isBuffering = true;
      _hasVideoFrame = false;
      _isPlaying = false;
      _hasError = false;
      _errorMessage = '';
      _retryCount = preferHls ? _retryCount : 0;
      _usingHlsFallback = preferHls;
      _resolutionText = '--';
      _fpsText = '--';
    });

    final streamUrl = preferHls ? channel.streamUrlM3u8 : channel.streamUrl;

    try {
      await player.play(streamUrl, headers: _streamHttpHeaders);
    } catch (_) {
      await _handlePlaybackAttemptFailure(channel, preferHls);
      return;
    }

    _fallbackTimer = Timer(_fallbackTimeout, () {
      if (!mounted || _activeChannelId != channel.id || _hasVideoFrame) return;
      unawaited(_handlePlaybackAttemptFailure(channel, preferHls));
    });
  }

  Future<void> _handlePlaybackAttemptFailure(
    Channel channel,
    bool attemptedHls,
  ) async {
    if (!mounted) return;

    _fallbackTimer?.cancel();

    if (!attemptedHls) {
      await _playChannel(channel, preferHls: true);
      return;
    }

    if (_retryCount < _maxRetries) {
      _retryCount++;
      _retryTimer?.cancel();
      _retryTimer = Timer(const Duration(seconds: 2), () {
        if (!mounted) return;
        unawaited(_playChannel(channel, preferHls: true));
      });
      return;
    }

    setState(() {
      _hasError = true;
      _isBuffering = false;
      _hasVideoFrame = false;
      _errorMessage = 'Stream unavailable';
      _resolutionText = '--';
      _fpsText = '--';
    });
  }

  Future<void> _handlePlaybackFailure(String message) async {
    if (!mounted || _activeChannelId == null) return;
    final channels = await _channelsFuture;
    if (!mounted || channels.isEmpty) return;

    final current = channels[_selectedChannelIndex];
    if (current.id != _activeChannelId) return;

    setState(() {
      _hasError = true;
      _isBuffering = false;
      _errorMessage = message;
    });

    await _handlePlaybackAttemptFailure(current, _usingHlsFallback);
  }

  Future<void> _loadFavoriteStatus(String channelId) async {
    final isFavorite = await FavoritesManager.isFavoriteLive(channelId);
    if (!mounted) return;
    setState(() {
      _isFavorite = isFavorite;
    });
  }

  Future<void> _toggleFavorite(Channel channel) async {
    if (_isFavorite) {
      await FavoritesManager.removeFavoriteLive(channel.id.toString());
    } else {
      await FavoritesManager.addFavoriteLive(channel.id.toString());
    }
    if (!mounted) return;
    setState(() {
      _isFavorite = !_isFavorite;
    });
  }

  void _ensureChannelFocusNodes(int count) {
    if (_channelFocusNodes.length == count) return;
    for (final node in _channelFocusNodes) {
      node.dispose();
    }
    _channelFocusNodes
      ..clear()
      ..addAll(
        List<FocusNode>.generate(
          count,
          (index) => FocusNode(debugLabel: 'LiveChannel-$index'),
        ),
      );
  }

  void _requestChannelFocus(int index) {
    if (index < 0 || index >= _channelFocusNodes.length) return;
    _channelFocusNodes[index].requestFocus();
  }

  void _requestPlayerFocus() {
    _playerFocusNode.requestFocus();
  }

  void _requestFavoriteFocus() {
    _favoriteFocusNode.requestFocus();
  }

  bool _isBackKey(LogicalKeyboardKey key) {
    return key == LogicalKeyboardKey.goBack ||
        key == LogicalKeyboardKey.escape ||
        key == LogicalKeyboardKey.backspace;
  }

  bool _isSelectKey(LogicalKeyboardKey key) {
    return key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.gameButtonA;
  }

  void _enterFullscreen() {
    if (_isFullscreen || _activeChannelId == null || !mounted) return;
    setState(() {
      _isFullscreen = true;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _requestPlayerFocus();
    });
  }

  void _exitFullscreen() {
    if (!_isFullscreen || !mounted) return;
    setState(() {
      _isFullscreen = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _requestPlayerFocus();
    });
  }

  KeyEventResult _handleRootKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    if (_isFullscreen && (_isBackKey(event.logicalKey) || _isSelectKey(event.logicalKey))) {
      _exitFullscreen();
      return KeyEventResult.handled;
    }

    if (!_isFullscreen &&
        event.logicalKey == LogicalKeyboardKey.arrowRight &&
        _channelFocusNodes.any((node) => node.hasFocus)) {
      _requestPlayerFocus();
      return KeyEventResult.handled;
    }

    if (!_isFullscreen &&
        event.logicalKey == LogicalKeyboardKey.arrowLeft &&
        (_playerFocusNode.hasFocus || _favoriteFocusNode.hasFocus)) {
      _requestChannelFocus(_selectedChannelIndex);
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  Future<void> _ensureInitialFocus() async {
    if (!mounted || _isFullscreen) return;
    final hasFocusedChannel = _channelFocusNodes.any((node) => node.hasFocus);
    if (hasFocusedChannel || _playerFocusNode.hasFocus || _favoriteFocusNode.hasFocus) {
      return;
    }
    _requestChannelFocus(_selectedChannelIndex);
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        if (_isFullscreen) {
          _exitFullscreen();
          return false;
        }
        return true;
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF1E1E1E),
        appBar: _isFullscreen
            ? null
            : AppBar(
                title: Text(widget.category.name),
                backgroundColor: const Color(0xFF0F0F1A),
                elevation: 0,
              ),
        body: FutureBuilder<List<Channel>>(
          future: _channelsFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(
                child: CircularProgressIndicator(),
              );
            }

            if (snapshot.hasError) {
              return Center(
                child: Text(
                  'Error: ${snapshot.error}',
                  style: const TextStyle(color: Colors.white),
                ),
              );
            }

            final channels = snapshot.data ?? const <Channel>[];
            if (channels.isEmpty) {
              return const Center(
                child: Text(
                  'No channels found',
                  style: TextStyle(color: Colors.white),
                ),
              );
            }

            _ensureChannelFocusNodes(channels.length);
            final selectedChannel = channels[_selectedChannelIndex];

            WidgetsBinding.instance.addPostFrameCallback((_) {
              unawaited(_ensureInitialFocus());
            });

            return FocusScope(
              node: _screenFocusScope,
              child: Focus(
                focusNode: _screenFocusNode,
                autofocus: true,
                onKeyEvent: _handleRootKeyEvent,
                child: _isFullscreen
                    ? _buildFullscreenPlayer()
                    : _buildWindowedLayout(channels, selectedChannel),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildWindowedLayout(List<Channel> channels, Channel selectedChannel) {
    return Row(
      children: <Widget>[
        SizedBox(
          width: MediaQuery.of(context).size.width * 0.32,
          child: _buildChannelList(channels),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                _buildMiniPlayer(),
                const SizedBox(height: 18),
                _buildMetadataSection(selectedChannel),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildChannelList(List<Channel> channels) {
    return Container(
      color: const Color(0xFF0F0F1A),
      child: Column(
        children: <Widget>[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            color: const Color(0xFF07070F),
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
              controller: _channelScrollController,
              itemCount: channels.length,
              itemBuilder: (context, index) {
                final channel = channels[index];
                final focusNode = _channelFocusNodes[index];
                final isSelected = index == _selectedChannelIndex;
                final isPlaying = channel.id == _activeChannelId;

                return Focus(
                  focusNode: focusNode,
                  onFocusChange: (hasFocus) {
                    if (!hasFocus) return;
                    final itemContext = focusNode.context;
                    if (itemContext == null || !itemContext.mounted) return;
                    Scrollable.ensureVisible(
                      itemContext,
                      alignment: 0.5,
                      duration: const Duration(milliseconds: 140),
                    );
                  },
                  onKeyEvent: (_, event) {
                    if (event is! KeyDownEvent) return KeyEventResult.ignored;

                    if (_isSelectKey(event.logicalKey)) {
                      unawaited(_handleChannelActivation(channel, index));
                      return KeyEventResult.handled;
                    }

                    if (event.logicalKey == LogicalKeyboardKey.arrowUp && index > 0) {
                      _requestChannelFocus(index - 1);
                      return KeyEventResult.handled;
                    }

                    if (event.logicalKey == LogicalKeyboardKey.arrowDown &&
                        index < _channelFocusNodes.length - 1) {
                      _requestChannelFocus(index + 1);
                      return KeyEventResult.handled;
                    }

                    if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
                      _requestPlayerFocus();
                      return KeyEventResult.handled;
                    }

                    return KeyEventResult.ignored;
                  },
                  child: Builder(
                    builder: (context) {
                      final hasFocus = Focus.of(context).hasFocus;

                      return GestureDetector(
                        onTap: () => unawaited(_handleChannelActivation(channel, index)),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 120),
                          margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? const Color(0xFF173655)
                                : const Color(0xFF121221),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: hasFocus
                                  ? const Color(0xFF00C2FF)
                                  : isSelected
                                      ? const Color(0xFF2C78BA)
                                      : Colors.transparent,
                              width: hasFocus ? 2.5 : 1.3,
                            ),
                            boxShadow: hasFocus
                                ? const <BoxShadow>[
                                    BoxShadow(
                                      color: Color(0x6600C2FF),
                                      blurRadius: 10,
                                      spreadRadius: 1,
                                    ),
                                  ]
                                : null,
                          ),
                          child: Row(
                            children: <Widget>[
                              Container(
                                width: 42,
                                height: 42,
                                decoration: BoxDecoration(
                                  color: const Color(0xFF1E1E2E),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: channel.logoUrl.isNotEmpty
                                    ? ClipRRect(
                                        borderRadius: BorderRadius.circular(6),
                                        child: Image.network(
                                          channel.logoUrl,
                                          fit: BoxFit.contain,
                                          errorBuilder: (_, __, ___) {
                                            return const Icon(
                                              Icons.tv,
                                              color: Colors.white54,
                                              size: 20,
                                            );
                                          },
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
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 13,
                                    fontWeight: hasFocus || isSelected
                                        ? FontWeight.bold
                                        : FontWeight.w500,
                                  ),
                                ),
                              ),
                              if (isPlaying)
                                const Icon(
                                  Icons.play_arrow,
                                  color: Colors.lightBlueAccent,
                                  size: 18,
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMiniPlayer() {
    return Focus(
      focusNode: _playerFocusNode,
      onKeyEvent: (_, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;

        if (_isSelectKey(event.logicalKey) && _activeChannelId != null) {
          _enterFullscreen();
          return KeyEventResult.handled;
        }

        if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
          _requestChannelFocus(_selectedChannelIndex);
          return KeyEventResult.handled;
        }

        if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
          _requestFavoriteFocus();
          return KeyEventResult.handled;
        }

        return KeyEventResult.ignored;
      },
      child: Builder(
        builder: (context) {
          final hasFocus = Focus.of(context).hasFocus;

          return GestureDetector(
            onTap: _activeChannelId == null ? null : _enterFullscreen,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: hasFocus ? const Color(0xFF00C2FF) : Colors.white10,
                  width: hasFocus ? 3 : 1,
                ),
              ),
              clipBehavior: Clip.antiAlias,
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: _buildPlayerSurface(showEmptyState: true),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildFullscreenPlayer() {
    return SizedBox.expand(
      child: ColoredBox(
        color: Colors.black,
        child: _buildPlayerSurface(showEmptyState: false),
      ),
    );
  }

  Widget _buildPlayerSurface({required bool showEmptyState}) {
    if (!_playerInitialized || _activeChannelId == null) {
      if (!showEmptyState) {
        return const ColoredBox(color: Colors.black);
      }

      return const ColoredBox(
        color: Colors.black,
        child: Center(
          child: Text(
            'Select a channel to start playback',
            style: TextStyle(color: Colors.white54, fontSize: 16),
          ),
        ),
      );
    }

    return AndroidView(
      viewType: 'rawad_iptv/live_player_view',
      creationParamsCodec: const StandardMessageCodec(),
    );
  }

  Widget _buildMetadataSection(Channel selectedChannel) {
    final statusText = _hasError
        ? _errorMessage
        : _isBuffering
            ? 'Connecting...'
            : _usingHlsFallback
                ? 'Playing HLS fallback'
                : _activeChannelId == null
                    ? 'Waiting for channel selection'
                    : 'Playing';

    return Expanded(
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: const Color(0xFF111827),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              selectedChannel.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: <Widget>[
                _buildInfoChip(Icons.hd, 'Resolution', _resolutionText),
                _buildInfoChip(Icons.speed, 'FPS', _fpsText),
                _buildInfoChip(
                  Icons.stream,
                  'Source',
                  _usingHlsFallback ? 'HLS' : 'TS',
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFF0F0F1A),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white10),
              ),
              child: Text(
                statusText,
                style: TextStyle(
                  color: _hasError ? Colors.redAccent : Colors.white70,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const Spacer(),
            Focus(
              focusNode: _favoriteFocusNode,
              onKeyEvent: (_, event) {
                if (event is! KeyDownEvent) return KeyEventResult.ignored;

                if (_isSelectKey(event.logicalKey)) {
                  unawaited(_toggleFavorite(selectedChannel));
                  return KeyEventResult.handled;
                }

                if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
                  _requestPlayerFocus();
                  return KeyEventResult.handled;
                }

                if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
                  _requestChannelFocus(_selectedChannelIndex);
                  return KeyEventResult.handled;
                }

                return KeyEventResult.ignored;
              },
              child: Builder(
                builder: (context) {
                  final hasFocus = Focus.of(context).hasFocus;

                  return ElevatedButton.icon(
                    onPressed: () => unawaited(_toggleFavorite(selectedChannel)),
                    icon: Icon(
                      _isFavorite ? Icons.favorite : Icons.favorite_border,
                      color: _isFavorite ? Colors.redAccent : Colors.white,
                    ),
                    label: Text(
                      _isFavorite ? 'Remove from Favorites' : 'Add to Favorites',
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1A1A2E),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 14,
                      ),
                      side: BorderSide(
                        color: hasFocus ? const Color(0xFF00C2FF) : Colors.white24,
                        width: hasFocus ? 2.4 : 1.1,
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoChip(IconData icon, String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF0F0F1A),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, color: Colors.white54, size: 15),
          const SizedBox(width: 8),
          Text(
            '$label: $value',
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
