import 'dart:async';
import 'dart:convert';
import 'dart:ui';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
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
  static const Duration _controlsHintDuration = Duration(seconds: 8);
  static const Duration _remoteAutoHideDuration = Duration(seconds: 8);
  static const Duration _tvSeekStep = Duration(seconds: 10);

  late ThaNativePlayerController _ctrl;
  final GlobalKey _playerSurfaceKey = GlobalKey(debugLabel: 'movie_player_surface');
  final FocusNode _playerFocusNode = FocusNode(debugLabel: 'movie_player_focus_root');
  final FocusNode _playPauseFocusNode = FocusNode(debugLabel: 'movie_player_play_pause');
  final FocusNode _timelineFocusNode = FocusNode(debugLabel: 'movie_player_timeline');
  final FocusNode _rewindFocusNode = FocusNode(debugLabel: 'movie_player_rewind');
  final FocusNode _forwardFocusNode = FocusNode(debugLabel: 'movie_player_forward');
  final FocusScopeNode _playerScopeNode = FocusScopeNode(
    debugLabel: 'movie_player_scope',
  );
  Timer? _progressTimer;
  Timer? _controlsHintTimer;
  Timer? _remoteAutoHideTimer;
  String? _errorMessage;
  bool _show4KDialog = false;
  bool _controlsLikelyVisible = false;
  int _syntheticPointerId = 9000;
  Duration? _pendingTimelineSeek;

  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  DateTime? _lastProgressSaveAt;
  bool get _isSeriesPlayback => widget.seriesId != null;

  Offset _surfaceTarget(double fx, double fy) {
    final context = _playerSurfaceKey.currentContext;
    if (context == null) return Offset.zero;
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return Offset.zero;
    return box.localToGlobal(Offset(box.size.width * fx, box.size.height * fy));
  }

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


  void _markControlsVisibleHint() {
    _remoteAutoHideTimer?.cancel();
    _controlsHintTimer?.cancel();
    if (mounted) {
      setState(() {
        _controlsLikelyVisible = true;
      });
    } else {
      _controlsLikelyVisible = true;
    }
    _controlsHintTimer = Timer(_controlsHintDuration, () {
      if (!mounted) {
        _controlsLikelyVisible = false;
        return;
      }
      setState(() {
        _controlsLikelyVisible = false;
      });
    });
    _remoteAutoHideTimer = Timer(_remoteAutoHideDuration, _hideControlsFromInactivity);
  }

  void _openControlsFromRemote() {
    _markControlsVisibleHint();
    _simulateSurfaceTap();
    _focusPlayPauseAfterOverlayShown();
  }

  void _focusPlayPauseAfterOverlayShown() {
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _playPauseFocusNode.requestFocus();
    });
  }

  void _simulateSurfaceTap() {
    final context = _playerSurfaceKey.currentContext;
    if (context == null) return;

    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;

    final center = box.localToGlobal(box.size.center(Offset.zero));
    final pointer = _syntheticPointerId++;

    GestureBinding.instance.handlePointerEvent(
      PointerDownEvent(
        pointer: pointer,
        position: center,
        kind: PointerDeviceKind.touch,
      ),
    );
    GestureBinding.instance.handlePointerEvent(
      PointerUpEvent(
        pointer: pointer,
        position: center,
        kind: PointerDeviceKind.touch,
      ),
    );
  }

  void _simulateTapAt(double fx, double fy) {
    final context = _playerSurfaceKey.currentContext;
    if (context == null) return;
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;

    final position = _surfaceTarget(fx, fy);
    final pointer = _syntheticPointerId++;
    GestureBinding.instance.handlePointerEvent(
      PointerDownEvent(
        pointer: pointer,
        position: position,
        kind: PointerDeviceKind.touch,
      ),
    );
    GestureBinding.instance.handlePointerEvent(
      PointerUpEvent(
        pointer: pointer,
        position: position,
        kind: PointerDeviceKind.touch,
      ),
    );
  }

  bool _isSelectKey(LogicalKeyboardKey key) =>
      key == LogicalKeyboardKey.select ||
      key == LogicalKeyboardKey.enter ||
      key == LogicalKeyboardKey.numpadEnter ||
      key == LogicalKeyboardKey.gameButtonA;

  bool _isArrowKey(LogicalKeyboardKey key) =>
      key == LogicalKeyboardKey.arrowUp ||
      key == LogicalKeyboardKey.arrowDown ||
      key == LogicalKeyboardKey.arrowLeft ||
      key == LogicalKeyboardKey.arrowRight;

  bool get _isAndroidPlatform => defaultTargetPlatform == TargetPlatform.android;

  void _hideControlsFromInactivity() {
    if (!mounted || !_controlsLikelyVisible) return;
    setState(() {
      _controlsLikelyVisible = false;
      _pendingTimelineSeek = null;
    });
    _simulateSurfaceTap();
    _playerFocusNode.requestFocus();
  }

  bool _isTimelineFocused() => _timelineFocusNode.hasFocus;

  Duration _coercePendingSeek(Duration value) {
    final max = _duration > Duration.zero ? _duration : value;
    if (value < Duration.zero) return Duration.zero;
    if (max <= Duration.zero) return value;
    return value > max ? max : value;
  }

  void _updatePendingSeek(LogicalKeyboardKey key) {
    final base = _pendingTimelineSeek ?? _position;
    final next = switch (key) {
      LogicalKeyboardKey.arrowLeft => base - _tvSeekStep,
      LogicalKeyboardKey.arrowRight => base + _tvSeekStep,
      _ => base,
    };
    setState(() {
      _pendingTimelineSeek = _coercePendingSeek(next);
    });
    _markControlsVisibleHint();
  }

  Future<void> _confirmPendingSeek() async {
    final pending = _pendingTimelineSeek;
    if (pending == null) return;
    setState(() {
      _pendingTimelineSeek = null;
    });
    await _ctrl.seekTo(pending);
    _markControlsVisibleHint();
    if (mounted) _timelineFocusNode.requestFocus();
  }

  void _activateFocusedControl() {
    if (_timelineFocusNode.hasFocus) {
      if (_pendingTimelineSeek != null) {
        unawaited(_confirmPendingSeek());
      }
      return;
    }

    if (_rewindFocusNode.hasFocus) {
      _simulateTapAt(0.38, 0.88);
      return;
    }
    if (_forwardFocusNode.hasFocus) {
      _simulateTapAt(0.62, 0.88);
      return;
    }

    _simulateTapAt(0.50, 0.88);
  }

  void _moveControlFocus(LogicalKeyboardKey key) {
    final current = FocusManager.instance.primaryFocus;

    if (current == _playPauseFocusNode) {
      if (key == LogicalKeyboardKey.arrowLeft) {
        _rewindFocusNode.requestFocus();
      } else if (key == LogicalKeyboardKey.arrowRight) {
        _forwardFocusNode.requestFocus();
      } else if (key == LogicalKeyboardKey.arrowDown) {
        _timelineFocusNode.requestFocus();
      }
      return;
    }

    if (current == _rewindFocusNode) {
      if (key == LogicalKeyboardKey.arrowRight) {
        _playPauseFocusNode.requestFocus();
      } else if (key == LogicalKeyboardKey.arrowDown) {
        _timelineFocusNode.requestFocus();
      }
      return;
    }

    if (current == _forwardFocusNode) {
      if (key == LogicalKeyboardKey.arrowLeft) {
        _playPauseFocusNode.requestFocus();
      } else if (key == LogicalKeyboardKey.arrowDown) {
        _timelineFocusNode.requestFocus();
      }
      return;
    }

    if (current == _timelineFocusNode && key == LogicalKeyboardKey.arrowUp) {
      _playPauseFocusNode.requestFocus();
    }
  }

  KeyEventResult _handlePlayerKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (!_isAndroidPlatform) return KeyEventResult.ignored;

    final key = event.logicalKey;

    if (_show4KDialog || _errorMessage != null) {
      return KeyEventResult.ignored;
    }

    if (_isSelectKey(key)) {
      if (!_controlsLikelyVisible) {
        _openControlsFromRemote();
        return KeyEventResult.handled;
      }
      _markControlsVisibleHint();
      _activateFocusedControl();
      return KeyEventResult.handled;
    }

    if (_isArrowKey(key)) {
      if (!_controlsLikelyVisible) {
        _openControlsFromRemote();
        return KeyEventResult.handled;
      }

      if (_isTimelineFocused() &&
          (key == LogicalKeyboardKey.arrowLeft ||
              key == LogicalKeyboardKey.arrowRight)) {
        _updatePendingSeek(key);
        return KeyEventResult.handled;
      }

      _markControlsVisibleHint();
      _moveControlFocus(key);
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
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
    _controlsHintTimer?.cancel();
    _remoteAutoHideTimer?.cancel();
    _playerScopeNode.dispose();
    _playPauseFocusNode.dispose();
    _timelineFocusNode.dispose();
    _rewindFocusNode.dispose();
    _forwardFocusNode.dispose();
    _playerFocusNode.dispose();
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
                child: FocusTraversalGroup(
                  child: FocusScope(
                    node: _playerScopeNode,
                    child: Focus(
                      focusNode: _playerFocusNode,
                      autofocus: true,
                      canRequestFocus: true,
                      descendantsAreFocusable: true,
                      onKeyEvent: _handlePlayerKey,
                      onFocusChange: (hasFocus) {
                        if (hasFocus && _controlsLikelyVisible) {
                          _markControlsVisibleHint();
                        }
                      },
                      child: Container(
                        key: _playerSurfaceKey,
                        color: Colors.transparent,
                        child: ThaModernPlayer(
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
                              if (_pendingTimelineSeek != null)
                                Positioned(
                                  top: 50,
                                  left: 12,
                                  child: SafeArea(
                                    child: DecoratedBox(
                                      decoration: BoxDecoration(
                                        color: Colors.black87,
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 6,
                                        ),
                                        child: Text(
                                          'Seek: ${_pendingTimelineSeek!.inMinutes.remainder(60).toString().padLeft(2, '0')}:${_pendingTimelineSeek!.inSeconds.remainder(60).toString().padLeft(2, '0')}',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              Positioned(
                                top: 0,
                                right: 0,
                                child: SafeArea(
                                  child: Focus(
                                    canRequestFocus: false,
                                    descendantsAreFocusable: false,
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
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),

              if (_controlsLikelyVisible)
                Positioned.fill(
                  child: IgnorePointer(
                    child: FocusTraversalGroup(
                      policy: OrderedTraversalPolicy(),
                      child: Stack(
                        children: [
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: 92,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Focus(
                                  focusNode: _rewindFocusNode,
                                  child: const SizedBox(width: 52, height: 52),
                                ),
                                const SizedBox(width: 28),
                                Focus(
                                  focusNode: _playPauseFocusNode,
                                  child: const SizedBox(width: 64, height: 64),
                                ),
                                const SizedBox(width: 28),
                                Focus(
                                  focusNode: _forwardFocusNode,
                                  child: const SizedBox(width: 52, height: 52),
                                ),
                              ],
                            ),
                          ),
                          Positioned(
                            left: 70,
                            right: 70,
                            bottom: 36,
                            child: Focus(
                              focusNode: _timelineFocusNode,
                              child: const SizedBox(height: 32),
                            ),
                          ),
                        ],
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
