import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../../data/datasources/remote/xtream_api.dart';
import '../../../data/models/channel.dart';
import '../../../data/models/live_tv_category.dart';
import '../../../data/services/catalog_cache_service.dart';
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

enum _LiveTvFocusArea { channelList, playerPanel, retryPanel }

class _ChannelsDetailScreenState extends State<ChannelsDetailScreen> {
  late Future<List<Channel>> _channelsFuture;
  int _selectedChannelIndex = 0;
  Player? _player;
  VideoController? _controller;
  bool _isFavorite = false;
  bool _isBuffering = false;
  bool _hasError = false;
  String _resolution = '';
  String _fps = '';
  String _errorMessage = '';
  bool _usingM3u8 = false;
  int _retryCount = 0;
  bool _didStartInitialPlayback = false;
  bool _hasVideoFrame = false;
  bool _isFullscreen = false;
  static const int _maxRetries = 3;
  static const Map<String, String> _streamHttpHeaders = {
    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)',
    'Connection': 'keep-alive',
  };

  final FocusScopeNode _screenFocusScope = FocusScopeNode();
  final ScrollController _channelScrollController = ScrollController();
  final FocusNode _playerPanelFocusNode = FocusNode(debugLabel: 'PlayerPanel');
  final FocusNode _favoriteButtonFocusNode =
      FocusNode(debugLabel: 'FavoriteButton');
  final FocusNode _retryButtonFocusNode = FocusNode(debugLabel: 'RetryButton');
  final FocusNode _backButtonFocusNode = FocusNode(debugLabel: 'BackButton');
  List<FocusNode> _channelItemFocusNodes = <FocusNode>[];
  _LiveTvFocusArea _lastMainFocusArea = _LiveTvFocusArea.channelList;
  _LiveTvFocusArea _focusBeforeRetry = _LiveTvFocusArea.channelList;

  StreamSubscription<bool>? _bufferingSubscription;
  StreamSubscription? _videoParamsSubscription;
  StreamSubscription? _tracksSubscription;
  StreamSubscription<String>? _errorSubscription;
  StreamSubscription<bool>? _playingSubscription;
  StreamSubscription<Duration>? _positionSubscription;
  Timer? _fallbackTimer;
  Timer? _retryTimer;
  Timer? _watchdogTimer;
  Duration _lastPosition = Duration.zero;
  DateTime _lastProgressAt = DateTime.now();
  bool _isPlaying = false;
  bool _didRecoverPlaybackPipeline = false;

  void _forceLandscape() {
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void initState() {
    super.initState();
    _forceLandscape();
    _initializePlaybackPipeline();
    _channelsFuture = _loadChannels();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _forceLandscape();
  }

  void _initializePlaybackPipeline() {
    _clearPlayerSubscriptions();
    _player?.dispose();

    final player = Player(
      configuration: const PlayerConfiguration(
        bufferSize: 48 * 1024 * 1024,
        logLevel: MPVLogLevel.warn,
      ),
    );
    _player = player;

    _controller = VideoController(
      player,
      configuration: const VideoControllerConfiguration(
        enableHardwareAcceleration: true,
        androidAttachSurfaceAfterVideoParameters: false,
      ),
    );

    _bufferingSubscription = player.stream.buffering.listen((buffering) {
      if (!mounted) return;
      setState(() => _isBuffering = buffering && !_hasVideoFrame && !_hasError);
    });

    _videoParamsSubscription = player.stream.videoParams.listen((params) {
      if (!mounted || params.w == null || params.h == null) return;
      _fallbackTimer?.cancel();
      _retryTimer?.cancel();
      setState(() {
        _hasVideoFrame = true;
        _resolution = '${params.w}x${params.h}';
        _hasError = false;
        _isBuffering = false;
        _retryCount = 0;
      });
      _focusRecoveryAfterPlaybackResumes();
      debugPrint('[LiveTV] video params ready: ${params.w}x${params.h}');
    });

    _tracksSubscription = player.stream.tracks.listen((tracks) {
      if (!mounted || tracks.video.isEmpty) return;
      for (final track in tracks.video) {
        if (track.fps != null && track.fps! > 0) {
          setState(() {
            _fps = '${track.fps!.toStringAsFixed(0)} FPS';
          });
          break;
        }
      }
    });

    _errorSubscription = player.stream.error.listen((error) {
      if (!mounted || error.isEmpty) return;
      debugPrint('Player error: $error');
      _handleError();
    });

    _playingSubscription = player.stream.playing.listen((playing) {
      _isPlaying = playing;
      debugPrint(
        '[LiveTV] state playing=$playing buffering=$_isBuffering hasVideo=$_hasVideoFrame',
      );
    });

    _positionSubscription = player.stream.position.listen((position) {
      if (position > _lastPosition) {
        _lastPosition = position;
        _lastProgressAt = DateTime.now();
      }
    });

    _watchdogTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (!mounted || _hasError || !_isPlaying) return;
      final stalledFor = DateTime.now().difference(_lastProgressAt);
      if (stalledFor > const Duration(seconds: 25) && _hasVideoFrame) {
        debugPrint('[LiveTV] stalled playback detected, retrying stream');
        _handleError();
      }
    });
  }

  void _clearPlayerSubscriptions() {
    _bufferingSubscription?.cancel();
    _videoParamsSubscription?.cancel();
    _tracksSubscription?.cancel();
    _errorSubscription?.cancel();
    _playingSubscription?.cancel();
    _positionSubscription?.cancel();
  }

  Future<void> _recoverPlaybackPipeline(Channel channel) async {
    if (_didRecoverPlaybackPipeline || !mounted) return;
    _didRecoverPlaybackPipeline = true;
    debugPrint('[LiveTV] recovering playback pipeline and retrying stream...');
    _initializePlaybackPipeline();
    await _playStream(channel);
  }

  void _showRetryError(String message) {
    if (!mounted) return;
    setState(() {
      _hasError = true;
      _errorMessage = message;
      _isBuffering = false;
    });
    _moveFocusToRetryPanel();
  }

  void _handleError() {
    if (!mounted) return;
    _fallbackTimer?.cancel();

    if (!_usingM3u8) {
      debugPrint('[LiveTV] TS failed, switching to m3u8...');
      _channelsFuture.then((channels) {
        if (mounted && channels.isNotEmpty) {
          _tryM3u8Fallback(channels[_selectedChannelIndex]);
        }
      });
      return;
    }

    if (_retryCount < _maxRetries) {
      _retryCount++;
      debugPrint('[LiveTV] retry $_retryCount/$_maxRetries...');
      _retryTimer = Timer(const Duration(seconds: 2), () {
        if (!mounted) return;
        _channelsFuture.then((channels) {
          if (mounted && channels.isNotEmpty) {
            _playStream(channels[_selectedChannelIndex]);
          }
        });
      });
      return;
    }

    _channelsFuture.then((channels) {
      if (!mounted || channels.isEmpty) return;
      _recoverPlaybackPipeline(channels[_selectedChannelIndex]).then((_) {
        if (!mounted || _hasVideoFrame) return;
        _showRetryError('Stream unavailable');
      });
    });
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
        .map((json) => Channel.fromJson(
              json,
              widget.xtreamApi.serverUrl,
              widget.xtreamApi.username,
              widget.xtreamApi.password,
            ))
        .toList();
  }

  Future<void> _playStream(Channel channel) async {
    final player = _player;
    if (player == null) return;
    _fallbackTimer?.cancel();
    _retryTimer?.cancel();
    _usingM3u8 = false;
    _retryCount = 0;
    _lastPosition = Duration.zero;
    _lastProgressAt = DateTime.now();

    if (mounted) {
      setState(() {
        _hasError = false;
        _isBuffering = true;
        _resolution = '';
        _fps = '';
        _errorMessage = '';
        _hasVideoFrame = false;
      });
    }

    debugPrint('[LiveTV] opening TS stream: ${channel.streamUrl}');
    try {
      await player.open(
        Media(channel.streamUrl, httpHeaders: _streamHttpHeaders),
        play: true,
      );

      _fallbackTimer = Timer(const Duration(seconds: 8), () {
        if (mounted && !_hasVideoFrame && !_hasError) {
          debugPrint('[LiveTV] no video after 8s, trying m3u8...');
          _tryM3u8Fallback(channel);
        }
      });
    } catch (e) {
      debugPrint('[LiveTV] playStream TS error: $e');
      _tryM3u8Fallback(channel);
    }
  }

  Future<void> _tryM3u8Fallback(Channel channel) async {
    if (!mounted) return;
    _fallbackTimer?.cancel();
    _usingM3u8 = true;
    _lastPosition = Duration.zero;
    _lastProgressAt = DateTime.now();

    debugPrint('[LiveTV] trying m3u8: ${channel.streamUrlM3u8}');
    setState(() {
      _isBuffering = true;
      _hasError = false;
      _resolution = '';
      _hasVideoFrame = false;
    });

    try {
      final player = _player;
      if (player == null) return;
      await player.open(
        Media(channel.streamUrlM3u8, httpHeaders: _streamHttpHeaders),
        play: true,
      );

      _fallbackTimer = Timer(const Duration(seconds: 8), () {
        if (mounted && !_hasVideoFrame) {
          _showRetryError('Stream unavailable');
        }
      });
    } catch (e) {
      debugPrint('[LiveTV] m3u8 error: $e');
      _showRetryError('Stream unavailable');
    }
  }

  Future<void> _loadFavoriteStatus(String channelId) async {
    final fav = await FavoritesManager.isFavorite(channelId);
    if (mounted) {
      setState(() => _isFavorite = fav);
    }
  }

  Future<void> _toggleFavorite(Channel channel) async {
    if (_isFavorite) {
      await FavoritesManager.removeFavorite(channel.id.toString());
    } else {
      await FavoritesManager.addFavorite(channel.id.toString());
    }
    if (mounted) {
      setState(() => _isFavorite = !_isFavorite);
    }
  }

  Future<void> _onChannelSelected(Channel channel, int index) async {
    if (_selectedChannelIndex == index) return;
    setState(() {
      _selectedChannelIndex = index;
      _isBuffering = true;
      _hasError = false;
      _resolution = '';
      _fps = '';
    });
    _didRecoverPlaybackPipeline = false;
    await _playStream(channel);
    await _loadFavoriteStatus(channel.id.toString());
  }

  void _retryStream(List<Channel> channels) {
    _retryCount = 0;
    _usingM3u8 = false;
    _didRecoverPlaybackPipeline = false;
    _fallbackTimer?.cancel();
    _retryTimer?.cancel();
    _playStream(channels[_selectedChannelIndex]);
  }

  Future<void> _startInitialPlaybackIfNeeded(List<Channel> channels) async {
    if (_didStartInitialPlayback || channels.isEmpty || !mounted) return;
    _didStartInitialPlayback = true;
    final initial = channels[_selectedChannelIndex];
    debugPrint('[LiveTV] initial playback: ${initial.name}');
    await _playStream(initial);
    await _loadFavoriteStatus(initial.id.toString());
  }

  void _ensureChannelFocusNodes(int length) {
    if (_channelItemFocusNodes.length == length) return;
    for (final node in _channelItemFocusNodes) {
      node.dispose();
    }
    _channelItemFocusNodes = List<FocusNode>.generate(
      length,
      (index) => FocusNode(debugLabel: 'ChannelItem-$index'),
    );
  }

  void _requestChannelFocus(int index) {
    if (_channelItemFocusNodes.isEmpty || index >= _channelItemFocusNodes.length) {
      return;
    }
    _lastMainFocusArea = _LiveTvFocusArea.channelList;
    _channelItemFocusNodes[index].requestFocus();
  }

  void _requestPlayerPanelFocus() {
    _lastMainFocusArea = _LiveTvFocusArea.playerPanel;
    _playerPanelFocusNode.requestFocus();
  }

  void _moveFocusToRetryPanel() {
    _focusBeforeRetry = _screenFocusScope.focusedChild == _playerPanelFocusNode
        ? _LiveTvFocusArea.playerPanel
        : _LiveTvFocusArea.channelList;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _lastMainFocusArea = _LiveTvFocusArea.retryPanel;
      _retryButtonFocusNode.requestFocus();
    });
  }

  void _focusRecoveryAfterPlaybackResumes() {
    if (_hasError || !mounted) return;
    _lastMainFocusArea = _focusBeforeRetry;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _hasError) return;
      if (_lastMainFocusArea == _LiveTvFocusArea.playerPanel) {
        _requestPlayerPanelFocus();
      } else {
        _requestChannelFocus(_selectedChannelIndex);
      }
    });
  }

  void _enterFullscreenMode() {
    if (_isFullscreen || !mounted) return;
    setState(() => _isFullscreen = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _requestPlayerPanelFocus();
    });
  }

  void _exitFullscreenMode() {
    if (!_isFullscreen || !mounted) return;
    setState(() => _isFullscreen = false);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _requestPlayerPanelFocus();
    });
  }

  KeyEventResult _onScreenKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (_hasError) return KeyEventResult.ignored;

    if (event.logicalKey == LogicalKeyboardKey.arrowRight &&
        !_isFullscreen &&
        _channelItemFocusNodes.any((n) => n.hasFocus)) {
      _requestPlayerPanelFocus();
      return KeyEventResult.handled;
    }

    if (event.logicalKey == LogicalKeyboardKey.arrowLeft &&
        !_isFullscreen &&
        (_playerPanelFocusNode.hasFocus || _favoriteButtonFocusNode.hasFocus)) {
      _requestChannelFocus(_selectedChannelIndex);
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  KeyEventResult _onChannelItemKeyEvent(
    KeyEvent event,
    Channel channel,
    int index,
  ) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    if (event.logicalKey == LogicalKeyboardKey.select ||
        event.logicalKey == LogicalKeyboardKey.enter) {
      _onChannelSelected(channel, index);
      return KeyEventResult.handled;
    }

    if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      _requestPlayerPanelFocus();
      return KeyEventResult.handled;
    }

    if (event.logicalKey == LogicalKeyboardKey.arrowUp && index > 0) {
      _requestChannelFocus(index - 1);
      return KeyEventResult.handled;
    }

    if (event.logicalKey == LogicalKeyboardKey.arrowDown &&
        index < _channelItemFocusNodes.length - 1) {
      _requestChannelFocus(index + 1);
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  @override
  void dispose() {
    _forceLandscape();
    _fallbackTimer?.cancel();
    _retryTimer?.cancel();
    _watchdogTimer?.cancel();
    _clearPlayerSubscriptions();
    for (final node in _channelItemFocusNodes) {
      node.dispose();
    }
    _playerPanelFocusNode.dispose();
    _favoriteButtonFocusNode.dispose();
    _retryButtonFocusNode.dispose();
    _backButtonFocusNode.dispose();
    _screenFocusScope.dispose();
    _channelScrollController.dispose();
    _player?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return PopScope(
      canPop: !_isFullscreen,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _isFullscreen) {
          _exitFullscreenMode();
        }
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
            _ensureChannelFocusNodes(channels.length);
            final selectedChannel = channels[_selectedChannelIndex];

            WidgetsBinding.instance.addPostFrameCallback((_) {
              unawaited(_startInitialPlaybackIfNeeded(channels));
              if (!_hasError &&
                  !_channelItemFocusNodes.any((n) => n.hasFocus) &&
                  !_playerPanelFocusNode.hasFocus &&
                  !_favoriteButtonFocusNode.hasFocus) {
                if (_isFullscreen) {
                  _requestPlayerPanelFocus();
                } else {
                  _requestChannelFocus(_selectedChannelIndex);
                }
              }
            });

            return FocusTraversalGroup(
              child: FocusScope(
                node: _screenFocusScope,
                child: Focus(
                  autofocus: true,
                  onKeyEvent: _onScreenKeyEvent,
                  child: Row(
                    children: [
                      if (!_isFullscreen)
                        Container(
                          width: size.width * 0.32,
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
                                controller: _channelScrollController,
                                itemCount: channels.length,
                                itemBuilder: (context, index) {
                                  final channel = channels[index];
                                  final isSelected = index == _selectedChannelIndex;
                                  final focusNode = _channelItemFocusNodes[index];

                                  return Focus(
                                    focusNode: focusNode,
                                    canRequestFocus: !_hasError,
                                    onFocusChange: (focused) {
                                      if (!focused) return;
                                      _lastMainFocusArea = _LiveTvFocusArea.channelList;
                                      final itemContext = focusNode.context;
                                      if (itemContext == null || !itemContext.mounted) {
                                        return;
                                      }
                                      Scrollable.ensureVisible(
                                        itemContext,
                                        alignment: 0.5,
                                        duration: const Duration(milliseconds: 140),
                                      );
                                    },
                                    onKeyEvent: (_, event) =>
                                        _onChannelItemKeyEvent(event, channel, index),
                                    child: Builder(
                                      builder: (context) {
                                        final hasFocus = Focus.of(context).hasFocus;
                                        return GestureDetector(
                                          onTap: () {
                                            _requestChannelFocus(index);
                                            _onChannelSelected(channel, index);
                                          },
                                          child: AnimatedContainer(
                                            duration: const Duration(milliseconds: 120),
                                            margin: const EdgeInsets.symmetric(
                                              horizontal: 10,
                                              vertical: 5,
                                            ),
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 12,
                                              vertical: 10,
                                            ),
                                            decoration: BoxDecoration(
                                              color: isSelected
                                                  ? const Color(0xFF173655)
                                                  : const Color(0xFF121221),
                                              borderRadius: BorderRadius.circular(10),
                                              border: Border.all(
                                                color: hasFocus
                                                    ? const Color(0xFF00C2FF)
                                                    : (isSelected
                                                        ? const Color(0xFF2C78BA)
                                                        : Colors.transparent),
                                                width: hasFocus ? 2.5 : 1.4,
                                              ),
                                              boxShadow: hasFocus
                                                  ? [
                                                      const BoxShadow(
                                                        color: Color(0x6600C2FF),
                                                        blurRadius: 10,
                                                        spreadRadius: 1,
                                                      ),
                                                    ]
                                                  : null,
                                            ),
                                            child: Row(
                                              children: [
                                                Container(
                                                  width: 40,
                                                  height: 40,
                                                  decoration: BoxDecoration(
                                                    color: const Color(0xFF1E1E2E),
                                                    borderRadius: BorderRadius.circular(6),
                                                  ),
                                                  child: channel.logoUrl.isNotEmpty
                                                      ? ClipRRect(
                                                          borderRadius:
                                                              BorderRadius.circular(6),
                                                          child: Image.network(
                                                            channel.logoUrl,
                                                            cacheWidth: 400,
                                                            cacheHeight: 450,
                                                            filterQuality: FilterQuality.low,
                                                            fit: BoxFit.contain,
                                                            errorBuilder: (_, __, ___) =>
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
                                                      color: hasFocus
                                                          ? Colors.white
                                                          : (isSelected
                                                              ? Colors.white
                                                              : Colors.white70),
                                                      fontSize: 13,
                                                      fontWeight: hasFocus || isSelected
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
                                                    color: Colors.lightBlueAccent,
                                                    size: 16,
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
                        ),
                      Expanded(
                        child: Column(
                          children: [
                            Focus(
                              focusNode: _playerPanelFocusNode,
                              canRequestFocus: !_hasError,
                              onFocusChange: (focused) {
                                if (focused) {
                                  _lastMainFocusArea = _LiveTvFocusArea.playerPanel;
                                }
                              },
                              onKeyEvent: (_, event) {
                                if (event is! KeyDownEvent) return KeyEventResult.ignored;
                                if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
                                  if (_isFullscreen) return KeyEventResult.handled;
                                  _requestChannelFocus(_selectedChannelIndex);
                                  return KeyEventResult.handled;
                                }
                                if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
                                  if (_isFullscreen) return KeyEventResult.handled;
                                  _favoriteButtonFocusNode.requestFocus();
                                  return KeyEventResult.handled;
                                }
                                if (event.logicalKey == LogicalKeyboardKey.select ||
                                    event.logicalKey == LogicalKeyboardKey.enter) {
                                  _enterFullscreenMode();
                                  return KeyEventResult.handled;
                                }
                                return KeyEventResult.ignored;
                              },
                              child: Builder(
                                builder: (context) {
                                  final playerFocused = Focus.of(context).hasFocus;
                                  return GestureDetector(
                                    onTap: _enterFullscreenMode,
                                    child: Container(
                                      height: _isFullscreen
                                          ? double.infinity
                                          : (size.height - kToolbarHeight) * 0.62,
                                      decoration: BoxDecoration(
                                        color: Colors.black,
                                        border: Border.all(
                                          color: playerFocused
                                              ? const Color(0xFF00C2FF)
                                              : Colors.transparent,
                                          width: 3,
                                        ),
                                      ),
                                      child: Stack(
                                        children: [
                                        SizedBox.expand(
                                          child: _controller == null
                                              ? const SizedBox.shrink()
                                              : Video(
                                                  controller: _controller!,
                                                  fit: BoxFit.contain,
                                                  onEnterFullscreen: () async {
                                                    await SystemChrome.setEnabledSystemUIMode(
                                                      SystemUiMode.immersiveSticky,
                                                    );
                                                    await SystemChrome.setPreferredOrientations([
                                                      DeviceOrientation.landscapeLeft,
                                                      DeviceOrientation.landscapeRight,
                                                    ]);
                                                  },
                                                  onExitFullscreen: () async {
                                                    await SystemChrome.setEnabledSystemUIMode(
                                                      SystemUiMode.manual,
                                                      overlays: SystemUiOverlay.values,
                                                    );
                                                    await SystemChrome.setPreferredOrientations([
                                                      DeviceOrientation.landscapeLeft,
                                                      DeviceOrientation.landscapeRight,
                                                    ]);
                                                  },
                                                ),
                                        ),
                                        if (_isBuffering && !_hasError)
                                          Container(
                                            color: Colors.black54,
                                            child: Center(
                                              child: Column(
                                                mainAxisAlignment: MainAxisAlignment.center,
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
                                                      'Trying HLS fallback...',
                                                      style: TextStyle(
                                                        color: Colors.white54,
                                                        fontSize: 11,
                                                      ),
                                                    ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        if (_resolution.isNotEmpty || _fps.isNotEmpty)
                                          Positioned(
                                            top: 8,
                                            right: 8,
                                            child: Container(
                                              padding: const EdgeInsets.symmetric(
                                                horizontal: 8,
                                                vertical: 4,
                                              ),
                                              decoration: BoxDecoration(
                                                color: Colors.black.withValues(alpha: 0.7),
                                                borderRadius: BorderRadius.circular(6),
                                              ),
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.end,
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
                                        if (_hasError)
                                          _buildRetryOverlay(channels),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                            if (!_isFullscreen)
                              Expanded(
                                child: Container(
                                  color: const Color(0xFF1E1E1E),
                                  padding: const EdgeInsets.all(16),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                    Row(
                                      children: [
                                        if (selectedChannel.logoUrl.isNotEmpty)
                                          Container(
                                            width: 50,
                                            height: 50,
                                            margin: const EdgeInsets.only(right: 12),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFF0F0F1A),
                                              borderRadius: BorderRadius.circular(8),
                                            ),
                                            child: ClipRRect(
                                              borderRadius: BorderRadius.circular(8),
                                              child: Image.network(
                                                selectedChannel.logoUrl,
                                                cacheWidth: 400,
                                                cacheHeight: 450,
                                                filterQuality: FilterQuality.low,
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
                                    Focus(
                                      focusNode: _favoriteButtonFocusNode,
                                      canRequestFocus: !_hasError,
                                      onKeyEvent: (_, event) {
                                        if (event is! KeyDownEvent) {
                                          return KeyEventResult.ignored;
                                        }
                                        if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
                                          _requestPlayerPanelFocus();
                                          return KeyEventResult.handled;
                                        }
                                        if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
                                          _requestChannelFocus(_selectedChannelIndex);
                                          return KeyEventResult.handled;
                                        }
                                        if (event.logicalKey == LogicalKeyboardKey.select ||
                                            event.logicalKey == LogicalKeyboardKey.enter) {
                                          _toggleFavorite(selectedChannel);
                                          return KeyEventResult.handled;
                                        }
                                        return KeyEventResult.ignored;
                                      },
                                      child: Builder(
                                        builder: (context) {
                                          final hasFocus = Focus.of(context).hasFocus;
                                          return ElevatedButton.icon(
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
                                              backgroundColor: const Color(0xFF1A1A2E),
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                horizontal: 20,
                                                vertical: 12,
                                              ),
                                              side: BorderSide(
                                                color: hasFocus
                                                    ? const Color(0xFF00C2FF)
                                                    : Colors.white24,
                                                width: hasFocus ? 2.2 : 1,
                                              ),
                                            ),
                                          );
                                        },
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
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildRetryOverlay(List<Channel> channels) {
    return Positioned.fill(
      child: Container(
        color: Colors.black.withValues(alpha: 0.88),
        alignment: Alignment.center,
        child: Container(
          width: 460,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: const Color(0xFF171723),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFF00C2FF), width: 1.8),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.error_outline,
                color: Colors.redAccent,
                size: 48,
              ),
              const SizedBox(height: 12),
              Text(
                _errorMessage,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Check stream availability and retry playback.',
                style: TextStyle(color: Colors.white70, fontSize: 13),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Focus(
                    focusNode: _retryButtonFocusNode,
                    onKeyEvent: (_, event) {
                      if (event is! KeyDownEvent) return KeyEventResult.ignored;
                      if (event.logicalKey == LogicalKeyboardKey.select ||
                          event.logicalKey == LogicalKeyboardKey.enter) {
                        setState(() => _hasError = false);
                        _retryStream(channels);
                        return KeyEventResult.handled;
                      }
                      if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
                        _backButtonFocusNode.requestFocus();
                        return KeyEventResult.handled;
                      }
                      return KeyEventResult.ignored;
                    },
                    child: Builder(
                      builder: (context) {
                        final hasFocus = Focus.of(context).hasFocus;
                        return ElevatedButton.icon(
                          autofocus: true,
                          onPressed: () {
                            setState(() => _hasError = false);
                            _retryStream(channels);
                          },
                          icon: const Icon(Icons.refresh),
                          label: const Text('Retry'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF0077FF),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 22,
                              vertical: 14,
                            ),
                            side: BorderSide(
                              color: hasFocus ? Colors.white : Colors.transparent,
                              width: hasFocus ? 2.3 : 0,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Focus(
                    focusNode: _backButtonFocusNode,
                    onKeyEvent: (_, event) {
                      if (event is! KeyDownEvent) return KeyEventResult.ignored;
                      if (event.logicalKey == LogicalKeyboardKey.select ||
                          event.logicalKey == LogicalKeyboardKey.enter) {
                        Navigator.of(context).maybePop();
                        return KeyEventResult.handled;
                      }
                      if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
                        _retryButtonFocusNode.requestFocus();
                        return KeyEventResult.handled;
                      }
                      return KeyEventResult.ignored;
                    },
                    child: Builder(
                      builder: (context) {
                        final hasFocus = Focus.of(context).hasFocus;
                        return OutlinedButton(
                          onPressed: () => Navigator.of(context).maybePop(),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 22,
                              vertical: 14,
                            ),
                            side: BorderSide(
                              color: hasFocus
                                  ? const Color(0xFF00C2FF)
                                  : Colors.white54,
                              width: hasFocus ? 2.3 : 1.2,
                            ),
                          ),
                          child: const Text(
                            'Exit',
                            style: TextStyle(color: Colors.white),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
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
