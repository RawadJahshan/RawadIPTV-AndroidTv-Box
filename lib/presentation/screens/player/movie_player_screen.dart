import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tha_player/tha_player.dart';

import '../../../data/services/watch_progress_service.dart';

class MoviePlayerScreen extends StatefulWidget {
  final String streamUrl;
  final String title;
  final int streamId;
  final Duration? startAt;
  final String? poster;
  final int? seriesId;
  final String? seriesName;

  const MoviePlayerScreen({
    super.key,
    required this.streamUrl,
    required this.title,
    required this.streamId,
    this.poster,
    this.startAt,
    this.seriesId,
    this.seriesName,
  });

  @override
  State<MoviePlayerScreen> createState() => _MoviePlayerScreenState();
}

class _MoviePlayerScreenState extends State<MoviePlayerScreen> {
  static const MethodChannel _deviceInfoChannel = MethodChannel('rawad_iptv/device_info');
  static const Duration _tvOverlayAutoHide = Duration(seconds: 8);
  static const Duration _tvSeekStep = Duration(seconds: 10);

  late ThaNativePlayerController _ctrl;

  final FocusNode _playerRootFocusNode = FocusNode(debugLabel: 'tv_player_root');
  final FocusNode _playPauseFocusNode = FocusNode(debugLabel: 'tv_play_pause');
  final FocusNode _timelineFocusNode = FocusNode(debugLabel: 'tv_timeline');
  final FocusNode _subtitleFocusNode = FocusNode(debugLabel: 'tv_subtitles');
  final FocusNode _audioFocusNode = FocusNode(debugLabel: 'tv_audio');
  final FocusNode _qualityFocusNode = FocusNode(debugLabel: 'tv_quality');

  Timer? _progressTimer;
  Timer? _tvOverlayHideTimer;

  String? _errorMessage;
  bool _show4KDialog = false;
  bool? _isAndroidTvDevice;

  bool _tvOverlayVisible = false;
  Duration? _pendingSeekPosition;

  List<ThaSubtitleTrack> _subtitleTracks = <ThaSubtitleTrack>[];
  List<ThaAudioTrack> _audioTracks = <ThaAudioTrack>[];
  List<ThaVideoTrack> _videoTracks = <ThaVideoTrack>[];

  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  DateTime? _lastProgressSaveAt;

  bool get _isSeriesPlayback => widget.seriesId != null;
  bool get _isAndroidPlatform => defaultTargetPlatform == TargetPlatform.android;

  void _syncPlaybackState() {
    final state = _ctrl.playbackState.value;
    _position = state.position;
    _duration = state.duration;
    if (mounted) {
      setState(() {});
    }
  }

  void _initPlayer() {
    _ctrl = ThaNativePlayerController.single(
      ThaMediaSource(
        widget.streamUrl,
        headers: const {
          'User-Agent': 'Mozilla/5.0 (Linux; Android 10)',
          'Connection': 'keep-alive',
        },
      ),
      autoPlay: true,
    );

    _ctrl.playbackState.addListener(_syncPlaybackState);

    if (widget.startAt != null && widget.startAt! > Duration.zero) {
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) {
          _ctrl.seekTo(widget.startAt!);
        }
      });
    }

    _progressTimer = Timer.periodic(const Duration(seconds: 5), (_) => _saveProgress());
  }

  void _onError(String? error) {
    if (!mounted) return;
    final errorStr = error ?? '';

    final is4KError = errorStr.contains('NO_EXCEEDS_CAPABILITIES') ||
        errorStr.contains('EXCEEDS_CAPABILITIES') ||
        errorStr.contains('format_supported=NO') ||
        (errorStr.contains('hevc') && errorStr.contains('3840'));

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      if (is4KError) {
        setState(() {
          _show4KDialog = true;
          _errorMessage = null;
        });
      } else {
        setState(() {
          _errorMessage = _isSeriesPlayback
              ? 'Episode playback error. Please go back and try another episode.'
              : 'Playback error. Please go back and try another stream.';
          _show4KDialog = false;
        });
      }
    });
  }

  void _restoreLandscapeAndSystemUi() {
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: SystemUiOverlay.values,
    );
  }

  @override
  void initState() {
    super.initState();
    _detectAndroidTvDevice();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _initPlayer();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _playerRootFocusNode.requestFocus();
      }
    });
  }

  Future<void> _saveProgress({bool force = false}) async {
    if (_duration.inMilliseconds <= 0) return;

    final now = DateTime.now();
    if (!force &&
        _lastProgressSaveAt != null &&
        now.difference(_lastProgressSaveAt!) < const Duration(seconds: 5)) {
      return;
    }

    _lastProgressSaveAt = now;

    await WatchProgressService.saveProgress(
      streamId: widget.streamId,
      title: widget.title,
      poster: widget.poster,
      positionMs: _position.inMilliseconds,
      durationMs: _duration.inMilliseconds,
    );

    if (widget.seriesId != null && widget.seriesName != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'series_episode_meta_${widget.streamId}',
        jsonEncode({
          'seriesId': widget.seriesId,
          'seriesName': widget.seriesName,
          'episodeTitle': widget.title,
          'poster': widget.poster,
          'streamId': widget.streamId,
        }),
      );
    }
  }

  Future<void> _detectAndroidTvDevice() async {
    if (!_isAndroidPlatform) {
      return;
    }

    try {
      final isTv = await _deviceInfoChannel.invokeMethod<bool>('isAndroidTv') ?? false;
      if (!mounted) return;
      setState(() {
        _isAndroidTvDevice = isTv;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isAndroidTvDevice = null;
      });
    }
  }

  bool _isSelectKey(LogicalKeyboardKey key) {
    return key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.gameButtonA;
  }

  bool _isBackKey(LogicalKeyboardKey key) {
    return key == LogicalKeyboardKey.goBack ||
        key == LogicalKeyboardKey.escape ||
        key == LogicalKeyboardKey.backspace;
  }

  void _resetTvOverlayInactivityTimer() {
    _tvOverlayHideTimer?.cancel();
    if (!_tvOverlayVisible) return;
    _tvOverlayHideTimer = Timer(_tvOverlayAutoHide, () {
      if (!mounted || !_tvOverlayVisible) return;
      _hideTvOverlay();
    });
  }

  Future<void> _refreshTrackData() async {
    try {
      final subtitles = await _ctrl.getSubtitleTracks();
      final audios = await _ctrl.getAudioTracks();
      final videos = await _ctrl.getVideoTracks();
      if (!mounted) return;
      setState(() {
        _subtitleTracks = subtitles;
        _audioTracks = audios;
        _videoTracks = videos;
      });
    } catch (_) {
      // Keep overlay interactive even if tracks are unavailable for a stream.
    }
  }

  Future<void> _showTvOverlay({bool focusPlayPause = true}) async {
    if (!mounted) return;
    setState(() {
      _tvOverlayVisible = true;
      _pendingSeekPosition = null;
    });
    _resetTvOverlayInactivityTimer();
    unawaited(_refreshTrackData());
    if (focusPlayPause) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _tvOverlayVisible) {
          _playPauseFocusNode.requestFocus();
        }
      });
    }
  }

  void _hideTvOverlay() {
    _tvOverlayHideTimer?.cancel();
    if (!mounted) return;
    setState(() {
      _tvOverlayVisible = false;
      _pendingSeekPosition = null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _playerRootFocusNode.requestFocus();
      }
    });
  }

  Future<void> _togglePlayPause() async {
    _resetTvOverlayInactivityTimer();
    final dynamic state = _ctrl.playbackState.value;
    final bool isPlaying = (state.isPlaying as bool?) ?? (state.playing as bool?) ?? false;
    if (isPlaying) {
      await _ctrl.pause();
    } else {
      await _ctrl.play();
    }
  }

  Duration _clampPosition(Duration position) {
    if (_duration <= Duration.zero) {
      return Duration.zero;
    }
    if (position < Duration.zero) return Duration.zero;
    if (position > _duration) return _duration;
    return position;
  }

  Future<void> _adjustPendingSeek(int direction) async {
    if (!_tvOverlayVisible) return;
    final base = _pendingSeekPosition ?? _position;
    final updated = _clampPosition(base + (_tvSeekStep * direction));
    setState(() {
      _pendingSeekPosition = updated;
    });
    _resetTvOverlayInactivityTimer();
  }

  Future<void> _confirmPendingSeek() async {
    final target = _pendingSeekPosition;
    if (target == null) return;
    await _ctrl.seekTo(target);
    setState(() {
      _pendingSeekPosition = null;
      _position = target;
    });
    _resetTvOverlayInactivityTimer();
    _timelineFocusNode.requestFocus();
  }

  Future<void> _openSubtitleMenu() async {
    _resetTvOverlayInactivityTimer();
    await _refreshTrackData();
    if (!mounted) return;
    final selected = await showDialog<String>(
      context: context,
      barrierColor: Colors.black54,
      builder: (context) {
        final selectedId = _subtitleTracks.where((t) => t.selected).map((t) => t.id).firstOrNull;
        return _TvTrackDialog<String>(
          title: 'Subtitles',
          selectedValue: selectedId ?? '__off__',
          items: [
            const _TvDialogItem<String>(value: '__off__', title: 'Off'),
            ..._subtitleTracks.map(
              (track) => _TvDialogItem<String>(
                value: track.id,
                title: (track.label?.trim().isNotEmpty ?? false)
                    ? track.label!.trim()
                    : (track.language?.trim().isNotEmpty ?? false)
                        ? track.language!.trim()
                        : 'Subtitle',
                subtitle: track.language,
              ),
            ),
          ],
        );
      },
    );

    if (selected == null) {
      if (mounted) {
        _subtitleFocusNode.requestFocus();
      }
      return;
    }

    await _ctrl.selectSubtitleTrack(selected == '__off__' ? null : selected);
    await _refreshTrackData();
    if (mounted) {
      _subtitleFocusNode.requestFocus();
    }
  }

  Future<void> _openAudioMenu() async {
    _resetTvOverlayInactivityTimer();
    await _refreshTrackData();
    if (!mounted) return;
    final selected = await showDialog<String>(
      context: context,
      barrierColor: Colors.black54,
      builder: (context) {
        final selectedId = _audioTracks.where((t) => t.selected).map((t) => t.id).firstOrNull;
        return _TvTrackDialog<String>(
          title: 'Audio Tracks',
          selectedValue: selectedId,
          items: _audioTracks
              .map(
                (track) => _TvDialogItem<String>(
                  value: track.id,
                  title: (track.label?.trim().isNotEmpty ?? false)
                      ? track.label!.trim()
                      : (track.language?.trim().isNotEmpty ?? false)
                          ? track.language!.trim()
                          : 'Audio',
                  subtitle: track.language,
                ),
              )
              .toList(),
        );
      },
    );

    if (selected == null) {
      if (mounted) {
        _audioFocusNode.requestFocus();
      }
      return;
    }

    await _ctrl.selectAudioTrack(selected);
    await _refreshTrackData();
    if (mounted) {
      _audioFocusNode.requestFocus();
    }
  }

  Future<void> _openQualityMenu() async {
    _resetTvOverlayInactivityTimer();
    await _refreshTrackData();
    if (!mounted) return;

    final selected = await showDialog<String>(
      context: context,
      barrierColor: Colors.black54,
      builder: (context) {
        final selectedTrackId = _videoTracks.where((t) => t.selected).map((t) => t.id).firstOrNull;
        return _TvTrackDialog<String>(
          title: 'Quality',
          selectedValue: selectedTrackId ?? '__auto__',
          items: [
            const _TvDialogItem<String>(
              value: '__auto__',
              title: 'Auto',
            ),
            ..._videoTracks.map(
              (track) => _TvDialogItem<String>(
                value: track.id,
                title: track.displayLabel,
                subtitle: track.bitrate != null ? '${(track.bitrate! / 1000).round()} kbps' : null,
              ),
            ),
          ],
        );
      },
    );

    if (selected == null) {
      if (mounted) {
        _qualityFocusNode.requestFocus();
      }
      return;
    }

    if (selected == '__auto__') {
      await _ctrl.clearVideoTrackSelection();
    } else {
      await _ctrl.selectVideoTrack(selected);
    }
    await _refreshTrackData();
    if (mounted) {
      _qualityFocusNode.requestFocus();
    }
  }

  String _formatDuration(Duration duration) {
    final totalSeconds = duration.inSeconds;
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;

    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  KeyEventResult _onTvRootKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }

    final key = event.logicalKey;

    if (_isBackKey(key)) {
      if (_tvOverlayVisible) {
        _hideTvOverlay();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    if (!_tvOverlayVisible && _isSelectKey(key)) {
      unawaited(_showTvOverlay());
      return KeyEventResult.handled;
    }

    if (_tvOverlayVisible) {
      _resetTvOverlayInactivityTimer();
    }

    return KeyEventResult.ignored;
  }

  Widget _buildTvPlayer() {
    final currentPosition = _pendingSeekPosition ?? _position;
    final progress = _duration.inMilliseconds > 0
        ? (currentPosition.inMilliseconds / _duration.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;

    return SizedBox.expand(
      child: Focus(
        focusNode: _playerRootFocusNode,
        autofocus: true,
        onKeyEvent: _onTvRootKeyEvent,
        child: Stack(
          children: [
            Positioned.fill(
              child: ThaNativePlayerView(
                controller: _ctrl,
                boxFit: BoxFit.contain,
              ),
            ),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: IgnorePointer(
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                    child: Text(
                      widget.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                        shadows: [Shadow(color: Colors.black87, blurRadius: 6)],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (_tvOverlayVisible)
              Positioned(
                left: 24,
                right: 24,
                bottom: 20,
                child: SafeArea(
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.75),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.white24),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                    child: FocusTraversalGroup(
                      policy: OrderedTraversalPolicy(),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _FocusableTimeline(
                            focusNode: _timelineFocusNode,
                            progress: progress,
                            position: currentPosition,
                            duration: _duration,
                            pendingSeek: _pendingSeekPosition,
                            formatDuration: _formatDuration,
                            onNavigateLeft: () => _adjustPendingSeek(-1),
                            onNavigateRight: () => _adjustPendingSeek(1),
                            onConfirm: _confirmPendingSeek,
                            onInteraction: _resetTvOverlayInactivityTimer,
                          ),
                          const SizedBox(height: 14),
                          Row(
                            children: [
                              _TvControlButton(
                                focusNode: _playPauseFocusNode,
                                icon: ((_ctrl.playbackState.value as dynamic).isPlaying as bool?) ??
                                        ((_ctrl.playbackState.value as dynamic).playing as bool?) ??
                                        false
                                    ? Icons.pause
                                    : Icons.play_arrow,
                                label: ((_ctrl.playbackState.value as dynamic).isPlaying as bool?) ??
                                        ((_ctrl.playbackState.value as dynamic).playing as bool?) ??
                                        false
                                    ? 'Pause'
                                    : 'Play',
                                onPressed: _togglePlayPause,
                                onFocused: _resetTvOverlayInactivityTimer,
                              ),
                              const SizedBox(width: 12),
                              _TvControlButton(
                                focusNode: _subtitleFocusNode,
                                icon: Icons.closed_caption,
                                label: 'Subtitles',
                                onPressed: _openSubtitleMenu,
                                onFocused: _resetTvOverlayInactivityTimer,
                              ),
                              const SizedBox(width: 12),
                              _TvControlButton(
                                focusNode: _audioFocusNode,
                                icon: Icons.audiotrack,
                                label: 'Audio',
                                onPressed: _openAudioMenu,
                                onFocused: _resetTvOverlayInactivityTimer,
                              ),
                              const SizedBox(width: 12),
                              _TvControlButton(
                                focusNode: _qualityFocusNode,
                                icon: Icons.high_quality,
                                label: 'Quality',
                                onPressed: _openQualityMenu,
                                onFocused: _resetTvOverlayInactivityTimer,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildMobilePlayer() {
    return ThaModernPlayer(
      controller: _ctrl,
      doubleTapSeek: const Duration(seconds: 10),
      autoHideAfter: const Duration(seconds: 8),
      initialBoxFit: BoxFit.contain,
      autoFullscreen: false,
      isFullscreen: true,
      onError: _onError,
      overlay: Stack(
        children: [
          Positioned(
            top: 0,
            left: 0,
            right: 60,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  widget.title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    shadows: [
                      Shadow(
                        color: Colors.black54,
                        blurRadius: 4,
                      ),
                    ],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ),
          Positioned(
            top: 0,
            right: 0,
            child: SafeArea(
              child: IconButton(
                icon: const Icon(
                  Icons.close,
                  color: Colors.white,
                  size: 28,
                ),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _restoreLandscapeAndSystemUi();
    _progressTimer?.cancel();
    _tvOverlayHideTimer?.cancel();
    unawaited(_saveProgress(force: true));
    _playerRootFocusNode.dispose();
    _playPauseFocusNode.dispose();
    _timelineFocusNode.dispose();
    _subtitleFocusNode.dispose();
    _audioFocusNode.dispose();
    _qualityFocusNode.dispose();
    try {
      _ctrl.playbackState.removeListener(_syncPlaybackState);
      _ctrl.dispose();
    } catch (_) {}
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isTvMode = _isAndroidPlatform &&
        (_isAndroidTvDevice ?? MediaQuery.maybeNavigationModeOf(context) == NavigationMode.directional);

    return PopScope(
      canPop: !_tvOverlayVisible,
      onPopInvoked: (didPop) {
        if (!didPop && _tvOverlayVisible) {
          _hideTvOverlay();
          return;
        }
        _restoreLandscapeAndSystemUi();
        if (didPop) {
          unawaited(_saveProgress(force: true));
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SizedBox.expand(
          child: Stack(
            children: [
              Positioned.fill(child: isTvMode ? _buildTvPlayer() : _buildMobilePlayer()),
              if (_show4KDialog)
                Positioned.fill(
                  child: Container(
                    color: Colors.black87,
                    child: Center(
                      child: Container(
                        margin: const EdgeInsets.all(32),
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E1E2E),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.warning_amber_rounded,
                              color: Colors.orange,
                              size: 48,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              _isSeriesPlayback ? '4K Episode Not Supported' : '4K Not Supported',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              _isSeriesPlayback
                                  ? 'Your device does not support 4K playback for this episode.\n\nPlease go back and choose another episode.'
                                  : 'Your device does not support 4K playback.\n\nPlease go back and choose another stream.',
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 14,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 24),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                onPressed: () => Navigator.of(context).pop(),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.blue,
                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                ),
                                child: const Text('Go Back'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              if (_errorMessage != null)
                Positioned.fill(
                  child: Container(
                    color: Colors.black87,
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.error_outline,
                            color: Colors.red,
                            size: 64,
                          ),
                          const SizedBox(height: 16),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 32),
                            child: Text(
                              _errorMessage!,
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 16,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                          const SizedBox(height: 24),
                          ElevatedButton(
                            onPressed: () => Navigator.of(context).pop(),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red,
                            ),
                            child: const Text('Go Back'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TvControlButton extends StatefulWidget {
  final FocusNode focusNode;
  final IconData icon;
  final String label;
  final VoidCallback onFocused;
  final Future<void> Function() onPressed;

  const _TvControlButton({
    required this.focusNode,
    required this.icon,
    required this.label,
    required this.onFocused,
    required this.onPressed,
  });

  @override
  State<_TvControlButton> createState() => _TvControlButtonState();
}

class _TvControlButtonState extends State<_TvControlButton> {
  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(_onFocusChange);
  }

  @override
  void didUpdateWidget(covariant _TvControlButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode != widget.focusNode) {
      oldWidget.focusNode.removeListener(_onFocusChange);
      widget.focusNode.addListener(_onFocusChange);
    }
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_onFocusChange);
    super.dispose();
  }

  void _onFocusChange() {
    if (widget.focusNode.hasFocus) {
      widget.onFocused();
    }
    if (mounted) {
      setState(() {});
    }
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }

    if (event.logicalKey == LogicalKeyboardKey.select ||
        event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter ||
        event.logicalKey == LogicalKeyboardKey.gameButtonA) {
      widget.onPressed();
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final focused = widget.focusNode.hasFocus;
    return Focus(
      focusNode: widget.focusNode,
      onKeyEvent: _onKey,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: focused ? Colors.white : Colors.white10,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: focused ? Colors.lightBlueAccent : Colors.transparent,
            width: 2,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              widget.icon,
              color: focused ? Colors.black : Colors.white,
              size: 20,
            ),
            const SizedBox(width: 8),
            Text(
              widget.label,
              style: TextStyle(
                color: focused ? Colors.black : Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FocusableTimeline extends StatefulWidget {
  final FocusNode focusNode;
  final double progress;
  final Duration position;
  final Duration duration;
  final Duration? pendingSeek;
  final String Function(Duration duration) formatDuration;
  final Future<void> Function() onNavigateLeft;
  final Future<void> Function() onNavigateRight;
  final Future<void> Function() onConfirm;
  final VoidCallback onInteraction;

  const _FocusableTimeline({
    required this.focusNode,
    required this.progress,
    required this.position,
    required this.duration,
    required this.pendingSeek,
    required this.formatDuration,
    required this.onNavigateLeft,
    required this.onNavigateRight,
    required this.onConfirm,
    required this.onInteraction,
  });

  @override
  State<_FocusableTimeline> createState() => _FocusableTimelineState();
}

class _FocusableTimelineState extends State<_FocusableTimeline> {
  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(_onFocusChanged);
  }

  @override
  void didUpdateWidget(covariant _FocusableTimeline oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode != widget.focusNode) {
      oldWidget.focusNode.removeListener(_onFocusChanged);
      widget.focusNode.addListener(_onFocusChanged);
    }
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_onFocusChanged);
    super.dispose();
  }

  void _onFocusChanged() {
    if (widget.focusNode.hasFocus) {
      widget.onInteraction();
    }
    if (mounted) {
      setState(() {});
    }
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }

    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      widget.onInteraction();
      widget.onNavigateLeft();
      return KeyEventResult.handled;
    }

    if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      widget.onInteraction();
      widget.onNavigateRight();
      return KeyEventResult.handled;
    }

    if (event.logicalKey == LogicalKeyboardKey.select ||
        event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter ||
        event.logicalKey == LogicalKeyboardKey.gameButtonA) {
      widget.onInteraction();
      widget.onConfirm();
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final focused = widget.focusNode.hasFocus;
    final pendingSeek = widget.pendingSeek;

    return Focus(
      focusNode: widget.focusNode,
      onKeyEvent: _onKey,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: focused ? Colors.white12 : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: focused ? Colors.lightBlueAccent : Colors.white30,
            width: focused ? 2 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  widget.formatDuration(widget.position),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                Text(
                  widget.formatDuration(widget.duration),
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                minHeight: 8,
                value: widget.progress,
                backgroundColor: Colors.white24,
                valueColor: const AlwaysStoppedAnimation<Color>(Colors.lightBlueAccent),
              ),
            ),
            if (pendingSeek != null) ...[
              const SizedBox(height: 8),
              Text(
                'Pending seek: ${widget.formatDuration(pendingSeek)} (OK to confirm)',
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _TvDialogItem<T> {
  final T value;
  final String title;
  final String? subtitle;

  const _TvDialogItem({required this.value, required this.title, this.subtitle});
}

class _TvTrackDialog<T> extends StatelessWidget {
  final String title;
  final List<_TvDialogItem<T>> items;
  final T? selectedValue;

  const _TvTrackDialog({
    required this.title,
    required this.items,
    required this.selectedValue,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF111111),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      title: Text(
        title,
        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
      ),
      content: SizedBox(
        width: 460,
        child: items.isEmpty
            ? const Text('No tracks available', style: TextStyle(color: Colors.white70))
            : ListView.builder(
                shrinkWrap: true,
                itemCount: items.length,
                itemBuilder: (context, index) {
                  final item = items[index];
                  final selected = item.value == selectedValue;
                  return ListTile(
                    autofocus: index == 0,
                    selected: selected,
                    leading: Icon(
                      selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                      color: selected ? Colors.lightBlueAccent : Colors.white70,
                    ),
                    title: Text(item.title, style: const TextStyle(color: Colors.white)),
                    subtitle: item.subtitle == null
                        ? null
                        : Text(item.subtitle!, style: const TextStyle(color: Colors.white60)),
                    onTap: () => Navigator.of(context).pop(item.value),
                  );
                },
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
