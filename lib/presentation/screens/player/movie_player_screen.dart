import 'dart:async';
import 'dart:convert';

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
  static const Duration _remoteSeekStep = Duration(seconds: 10);

  late ThaNativePlayerController _ctrl;
  final FocusScopeNode _overlayFocusScopeNode = FocusScopeNode(
    debugLabel: 'movie_overlay_scope',
  );
  final FocusNode _screenFocusNode = FocusNode(debugLabel: 'movie_screen_focus');
  final FocusNode _defaultOverlayFocusNode = FocusNode(
    debugLabel: 'movie_overlay_play_pause',
  );
  final FocusNode _rewindFocusNode = FocusNode(debugLabel: 'movie_overlay_rewind');
  final FocusNode _forwardFocusNode = FocusNode(debugLabel: 'movie_overlay_forward');

  Timer? _progressTimer;
  String? _errorMessage;
  bool _show4KDialog = false;
  bool _showOverlay = false;

  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  DateTime? _lastProgressSaveAt;
  bool get _isSeriesPlayback => widget.seriesId != null;

  void _syncPlaybackState() {
    final state = _ctrl.playbackState.value;
    if (!mounted) {
      _position = state.position;
      _duration = state.duration;
      return;
    }

    setState(() {
      _position = state.position;
      _duration = state.duration;
    });
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

    _progressTimer = Timer.periodic(const Duration(seconds: 5), (_) => _saveProgress());
  }

  bool _isSelectKey(LogicalKeyboardKey key) =>
      key == LogicalKeyboardKey.select ||
      key == LogicalKeyboardKey.enter ||
      key == LogicalKeyboardKey.numpadEnter ||
      key == LogicalKeyboardKey.gameButtonA;

  void _showOverlayAndFocusDefault() {
    if (!_showOverlay) {
      setState(() {
        _showOverlay = true;
      });
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _overlayFocusScopeNode.requestFocus(_defaultOverlayFocusNode);
    });
  }

  void _hideOverlayAndRestoreScreenFocus() {
    if (!_showOverlay) return;
    setState(() {
      _showOverlay = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _screenFocusNode.requestFocus();
      }
    });
  }

  void _seekFromRemote(bool forward) {
    final state = _ctrl.playbackState.value;
    final max = state.duration;
    final current = state.position;
    final target = forward ? current + _remoteSeekStep : current - _remoteSeekStep;

    final clamped = max > Duration.zero
        ? Duration(milliseconds: target.inMilliseconds.clamp(0, max.inMilliseconds))
        : Duration(milliseconds: target.inMilliseconds.clamp(0, 1 << 31));

    _ctrl.seekTo(clamped);
  }

  void _togglePlayPause() {
    final isPlaying = _ctrl.playbackState.value.isPlaying;
    if (isPlaying) {
      _ctrl.pause();
    } else {
      _ctrl.play();
    }
  }

  KeyEventResult _handleScreenKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    final key = event.logicalKey;

    if (_show4KDialog || _errorMessage != null) {
      return KeyEventResult.ignored;
    }

    if (_isSelectKey(key)) {
      _showOverlayAndFocusDefault();
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.arrowLeft || key == LogicalKeyboardKey.arrowRight) {
      _seekFromRemote(key == LogicalKeyboardKey.arrowRight);
      _showOverlayAndFocusDefault();
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.arrowUp || key == LogicalKeyboardKey.arrowDown) {
      _showOverlayAndFocusDefault();
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.goBack ||
        key == LogicalKeyboardKey.escape ||
        key == LogicalKeyboardKey.browserBack) {
      Navigator.of(context).maybePop();
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  KeyEventResult _handleOverlayKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    final key = event.logicalKey;

    if (key == LogicalKeyboardKey.goBack ||
        key == LogicalKeyboardKey.escape ||
        key == LogicalKeyboardKey.browserBack) {
      _hideOverlayAndRestoreScreenFocus();
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.arrowLeft) {
      _overlayFocusScopeNode.focusInDirection(TraversalDirection.left);
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.arrowRight) {
      _overlayFocusScopeNode.focusInDirection(TraversalDirection.right);
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.arrowUp) {
      _overlayFocusScopeNode.focusInDirection(TraversalDirection.up);
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.arrowDown) {
      _overlayFocusScopeNode.focusInDirection(TraversalDirection.down);
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
      if (mounted) _screenFocusNode.requestFocus();
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
    _screenFocusNode.dispose();
    _defaultOverlayFocusNode.dispose();
    _rewindFocusNode.dispose();
    _forwardFocusNode.dispose();
    _overlayFocusScopeNode.dispose();
    unawaited(_saveProgress(force: true));
    try {
      _ctrl.playbackState.removeListener(_syncPlaybackState);
      _ctrl.dispose();
    } catch (_) {}
    super.dispose();
  }

  Widget _buildOverlayButton({
    required FocusNode focusNode,
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
  }) {
    return FilledButton.tonal(
      focusNode: focusNode,
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        backgroundColor: Colors.white.withValues(alpha: 0.14),
        foregroundColor: Colors.white,
      ),
      onPressed: onPressed,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 28),
          const SizedBox(height: 6),
          Text(label),
        ],
      ),
    );
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

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_showOverlay,
      onPopInvoked: (didPop) {
        if (_showOverlay && !didPop) {
          _hideOverlayAndRestoreScreenFocus();
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
          child: Focus(
            focusNode: _screenFocusNode,
            autofocus: true,
            onKeyEvent: _handleScreenKey,
            child: Stack(
              children: [
                Positioned.fill(
                  child: ThaModernPlayer(
                    controller: _ctrl,
                    doubleTapSeek: const Duration(seconds: 10),
                    autoHideAfter: const Duration(seconds: 3),
                    initialBoxFit: BoxFit.contain,
                    autoFullscreen: false,
                    isFullscreen: true,
                    onError: _onError,
                    overlay: const SizedBox.shrink(),
                  ),
                ),

                if (_showOverlay)
                  Positioned.fill(
                    child: FocusScope(
                      node: _overlayFocusScopeNode,
                      onKeyEvent: _handleOverlayKey,
                      child: Container(
                        color: Colors.black45,
                        child: SafeArea(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        widget.title,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 18,
                                          fontWeight: FontWeight.w600,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    FilledButton.tonalIcon(
                                      onPressed: _hideOverlayAndRestoreScreenFocus,
                                      style: FilledButton.styleFrom(
                                        backgroundColor:
                                            Colors.white.withValues(alpha: 0.14),
                                        foregroundColor: Colors.white,
                                      ),
                                      icon: const Icon(Icons.close),
                                      label: const Text('Close'),
                                    ),
                                  ],
                                ),
                                const Spacer(),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    _buildOverlayButton(
                                      focusNode: _rewindFocusNode,
                                      icon: Icons.replay_10,
                                      label: '-10s',
                                      onPressed: () => _seekFromRemote(false),
                                    ),
                                    const SizedBox(width: 18),
                                    _buildOverlayButton(
                                      focusNode: _defaultOverlayFocusNode,
                                      icon: _ctrl.playbackState.value.isPlaying
                                          ? Icons.pause
                                          : Icons.play_arrow,
                                      label: _ctrl.playbackState.value.isPlaying
                                          ? 'Pause'
                                          : 'Play',
                                      onPressed: _togglePlayPause,
                                    ),
                                    const SizedBox(width: 18),
                                    _buildOverlayButton(
                                      focusNode: _forwardFocusNode,
                                      icon: Icons.forward_10,
                                      label: '+10s',
                                      onPressed: () => _seekFromRemote(true),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 20),
                                Text(
                                  '${_formatDuration(_position)} / ${_formatDuration(_duration)}',
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 14,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                LinearProgressIndicator(
                                  value: _duration.inMilliseconds > 0
                                      ? _position.inMilliseconds /
                                          _duration.inMilliseconds
                                      : 0,
                                  minHeight: 6,
                                  backgroundColor: Colors.white24,
                                  color: Colors.redAccent,
                                ),
                              ],
                            ),
                          ),
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
      ),
    );
  }
}
