import 'dart:async';
import 'dart:convert';
import 'dart:ui';

import 'package:flutter/gestures.dart';
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
  late ThaNativePlayerController _ctrl;
  final GlobalKey _playerSurfaceKey = GlobalKey(debugLabel: 'movie_player_surface');
  final FocusNode _playerFocusNode = FocusNode(debugLabel: 'movie_player_focus');
  final FocusNode _playPauseFocusNode = FocusNode(debugLabel: 'play_pause');
  final FocusNode _rewindFocusNode = FocusNode(debugLabel: 'rewind');
  final FocusNode _forwardFocusNode = FocusNode(debugLabel: 'forward');
  final FocusNode _seekBarFocusNode = FocusNode(debugLabel: 'seek_bar');
  Timer? _progressTimer;
  Timer? _hideTimer;
  String? _errorMessage;
  bool _show4KDialog = false;
  bool _overlayVisible = false;
  bool _isSeeking = false;
  Duration _seekPreviewPosition = Duration.zero;

  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  DateTime? _lastProgressSaveAt;
  bool get _isSeriesPlayback => widget.seriesId != null;

  void _syncPlaybackState() {
    final state = _ctrl.playbackState.value;
    _position = state.position;
    _duration = state.duration;
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
        if (mounted) _ctrl.seekTo(widget.startAt!);
      });
    }

    _progressTimer =
        Timer.periodic(const Duration(seconds: 5), (_) => _saveProgress());
  }


  void _showOverlay() {
    setState(() => _overlayVisible = true);
    _resetHideTimer();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _playPauseFocusNode.requestFocus();
    });
  }

  void _hideOverlay() {
    _hideTimer?.cancel();
    setState(() => _overlayVisible = false);
  }

  void _resetHideTimer() {
    if (_isSeeking) return;
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 8), _hideOverlay);
  }

  void _togglePlayPause() {
    final state = _ctrl.playbackState.value;
    if (state.isPlaying) {
      _ctrl.pause();
    } else {
      _ctrl.play();
    }
    _resetHideTimer();
  }

  void _rewind() {
    final target = _position - const Duration(seconds: 10);
    _ctrl.seekTo(target < Duration.zero ? Duration.zero : target);
    _resetHideTimer();
  }

  void _fastForward() {
    final target = _position + const Duration(seconds: 10);
    _ctrl.seekTo(target > _duration ? _duration : target);
    _resetHideTimer();
  }

  void _startSeekMode() {
    setState(() {
      _isSeeking = true;
      _seekPreviewPosition = _position;
    });
    _hideTimer?.cancel();
  }

  void _cancelSeekMode() {
    setState(() {
      _isSeeking = false;
      _seekPreviewPosition = _position;
    });
    _resetHideTimer();
  }

  void _confirmSeek() {
    _ctrl.seekTo(_seekPreviewPosition);
    setState(() => _isSeeking = false);
    _resetHideTimer();
  }

  void _seekStep(int seconds) {
    setState(() {
      final ms = _seekPreviewPosition.inMilliseconds + (seconds * 1000);
      final clamped = ms.clamp(0, _duration.inMilliseconds);
      _seekPreviewPosition = Duration(milliseconds: clamped);
    });
  }

  bool _isSelectKey(LogicalKeyboardKey key) =>
      key == LogicalKeyboardKey.select ||
      key == LogicalKeyboardKey.enter ||
      key == LogicalKeyboardKey.numpadEnter ||
      key == LogicalKeyboardKey.gameButtonA;

  bool _isBackKey(LogicalKeyboardKey key) =>
      key == LogicalKeyboardKey.goBack ||
      key == LogicalKeyboardKey.escape ||
      key == LogicalKeyboardKey.browserBack;

  KeyEventResult _handlePlayerKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;

    if (_isBackKey(key)) return KeyEventResult.ignored;

    if (_show4KDialog || _errorMessage != null) return KeyEventResult.ignored;

    if (!_overlayVisible) {
      _showOverlay();
      return KeyEventResult.handled;
    }

    if (!_isSeeking) _resetHideTimer();

    if (_seekBarFocusNode.hasFocus) {
      if (key == LogicalKeyboardKey.arrowLeft) {
        _seekStep(-10);
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowRight) {
        _seekStep(10);
        return KeyEventResult.handled;
      }
      if (_isSelectKey(key)) {
        _confirmSeek();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowUp ||
          key == LogicalKeyboardKey.arrowDown) {
        _cancelSeekMode();
        return KeyEventResult.ignored;
      }
    }

    return KeyEventResult.ignored;
  }

  Widget _buildTvOverlay() {
    final isPlaying = _ctrl.playbackState.value.isPlaying;

    return FocusTraversalGroup(
      policy: OrderedTraversalPolicy(),
      child: Stack(
        children: [
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              height: 180,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [Colors.black87, Colors.transparent],
                ),
              ),
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              height: 100,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.black87, Colors.transparent],
                ),
              ),
            ),
          ),
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
                    shadows: [Shadow(color: Colors.black54, blurRadius: 4)],
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
              child: _buildTvButton(
                focusNode: FocusNode(),
                icon: Icons.close,
                onPressed: () => Navigator.of(context).pop(),
                size: 28,
              ),
            ),
          ),
          Center(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                FocusTraversalOrder(
                  order: const NumericFocusOrder(1),
                  child: _buildTvButton(
                    focusNode: _rewindFocusNode,
                    icon: Icons.replay_10,
                    onPressed: _rewind,
                    size: 40,
                  ),
                ),
                const SizedBox(width: 32),
                FocusTraversalOrder(
                  order: const NumericFocusOrder(2),
                  child: _buildTvButton(
                    focusNode: _playPauseFocusNode,
                    icon: isPlaying ? Icons.pause_circle : Icons.play_circle,
                    onPressed: _togglePlayPause,
                    size: 64,
                  ),
                ),
                const SizedBox(width: 32),
                FocusTraversalOrder(
                  order: const NumericFocusOrder(3),
                  child: _buildTvButton(
                    focusNode: _forwardFocusNode,
                    icon: Icons.forward_10,
                    onPressed: _fastForward,
                    size: 40,
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                child: Row(
                  children: [
                    Text(
                      _formatDuration(_position),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FocusTraversalOrder(
                        order: const NumericFocusOrder(4),
                        child: _buildSeekBar(),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      _formatDuration(_duration),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTvButton({
    required FocusNode focusNode,
    required IconData icon,
    required VoidCallback onPressed,
    double size = 36,
  }) {
    return Focus(
      focusNode: focusNode,
      child: Builder(
        builder: (context) {
          final focused = focusNode.hasFocus;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: focused ? Colors.white.withOpacity(0.25) : Colors.transparent,
              border: focused ? Border.all(color: Colors.white, width: 2) : null,
            ),
            child: IconButton(
              icon: Icon(icon, color: Colors.white, size: size),
              onPressed: () {
                onPressed();
                _resetHideTimer();
              },
            ),
          );
        },
      ),
    );
  }

  Widget _buildSeekBar() {
    return Focus(
      focusNode: _seekBarFocusNode,
      onFocusChange: (hasFocus) {
        if (hasFocus) {
          _startSeekMode();
        } else {
          _cancelSeekMode();
        }
      },
      child: Builder(
        builder: (context) {
          final focused = _seekBarFocusNode.hasFocus;
          final displayPosition = _isSeeking ? _seekPreviewPosition : _position;
          final progress = _duration.inMilliseconds > 0
              ? (displayPosition.inMilliseconds / _duration.inMilliseconds)
                  .clamp(0.0, 1.0)
              : 0.0;

          return AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            height: focused ? 12 : 5,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final totalWidth = constraints.maxWidth;
                final filledWidth = totalWidth * progress;

                return Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.centerLeft,
                  children: [
                    Positioned.fill(
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.white24,
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                    ),
                    Positioned(
                      left: 0,
                      top: 0,
                      bottom: 0,
                      width: filledWidth.clamp(0.0, totalWidth),
                      child: Container(
                        decoration: BoxDecoration(
                          color: _isSeeking ? Colors.orange : Colors.blue,
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                    ),
                    Positioned(
                      left: (filledWidth - 8).clamp(0.0, totalWidth - 16),
                      top: -4,
                      child: Container(
                        width: 16,
                        height: 16,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _isSeeking ? Colors.orange : Colors.white,
                          boxShadow: focused
                              ? [
                                  BoxShadow(
                                    color: Colors.white.withOpacity(0.6),
                                    blurRadius: 6,
                                    spreadRadius: 2,
                                  ),
                                ]
                              : null,
                        ),
                      ),
                    ),
                    if (_isSeeking)
                      Positioned(
                        left: (filledWidth - 28).clamp(0.0, totalWidth - 56),
                        bottom: 18,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black87,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            _formatDuration(_seekPreviewPosition),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          );
        },
      ),
    );
  }

  String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (h > 0) return '$h:$m:$s';
    return '$m:$s';
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
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _initPlayer();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _playerFocusNode.requestFocus();
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

  @override
  void dispose() {
    _restoreLandscapeAndSystemUi();
    _progressTimer?.cancel();
    _hideTimer?.cancel();
    _playerFocusNode.dispose();
    _playPauseFocusNode.dispose();
    _rewindFocusNode.dispose();
    _forwardFocusNode.dispose();
    _seekBarFocusNode.dispose();
    unawaited(_saveProgress(force: true));
    try {
      _ctrl.playbackState.removeListener(_syncPlaybackState);
      _ctrl.dispose();
    } catch (_) {}
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: true,
      onPopInvoked: (didPop) {
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
              Positioned.fill(
                child: Focus(
                  focusNode: _playerFocusNode,
                  autofocus: true,
                  onKeyEvent: _handlePlayerKey,
                  child: Container(
                    key: _playerSurfaceKey,
                    color: Colors.transparent,
                    child: ThaModernPlayer(
                      controller: _ctrl,
                      doubleTapSeek: Duration.zero,
                      autoHideAfter: Duration.zero,
                      initialBoxFit: BoxFit.contain,
                      autoFullscreen: false,
                      isFullscreen: true,
                      onError: _onError,
                      overlay: _overlayVisible
                          ? _buildTvOverlay()
                          : const SizedBox.shrink(),
                    ),
                  ),
                ),
              ),

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
                              _isSeriesPlayback
                                  ? '4K Episode Not Supported'
                                  : '4K Not Supported',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              _isSeriesPlayback
                                  ? 'Your device does not support 4K playback for this episode.\n\n'
                                        'Please go back and choose another episode.'
                                  : 'Your device does not support 4K playback.\n\n'
                                        'Please go back and choose another stream.',
                              style: TextStyle(
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
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 14,
                                  ),
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
