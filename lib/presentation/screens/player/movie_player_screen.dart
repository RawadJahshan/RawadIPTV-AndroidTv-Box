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
  late ThaNativePlayerController _ctrl;
  final FocusNode _playerFocusNode = FocusNode(debugLabel: 'movie_player_focus');
  Timer? _progressTimer;
  String? _errorMessage;
  bool _show4KDialog = false;

  bool _overlayVisible = false;
  int _focusedButtonIndex = 2; // 0=back10, 1=play/pause, 2=forward10
  bool _isOnTimeline = false;
  Timer? _seekHoldTimer;
  Timer? _overlayHideTimer;

  // Button indices:
  // 0 = Back 10s
  // 1 = Play/Pause
  // 2 = Forward 10s
  // 3 = Subtitles
  // 4 = Audio
  // 5 = Timeline (seek bar)
  static const int _totalButtons = 6;

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



  KeyEventResult _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      if (event is KeyUpEvent) {
        _seekHoldTimer?.cancel();
      }
      return KeyEventResult.ignored;
    }

    final key = event.logicalKey;

    if (_show4KDialog || _errorMessage != null) {
      return KeyEventResult.ignored;
    }

    // If overlay is hidden, left/right seek directly
    if (!_overlayVisible) {
      if (key == LogicalKeyboardKey.arrowLeft ||
          key == LogicalKeyboardKey.arrowRight ||
          key == LogicalKeyboardKey.mediaRewind ||
          key == LogicalKeyboardKey.mediaFastForward) {
        final isLeft = key == LogicalKeyboardKey.arrowLeft ||
            key == LogicalKeyboardKey.mediaRewind;
        _startSeekHold(isLeft ? -10 : 10);
        return KeyEventResult.handled;
      }
      // OK/Select shows overlay with play/pause focused
      if (key == LogicalKeyboardKey.select ||
          key == LogicalKeyboardKey.enter ||
          key == LogicalKeyboardKey.numpadEnter ||
          key == LogicalKeyboardKey.mediaPlayPause) {
        if (key == LogicalKeyboardKey.mediaPlayPause) {
          _ctrl.playbackState.value.isPlaying ? _ctrl.pause() : _ctrl.play();
        } else {
          _showOverlay();
        }
        return KeyEventResult.handled;
      }
      // Back button exits
      if (key == LogicalKeyboardKey.escape ||
          key == LogicalKeyboardKey.goBack ||
          key == LogicalKeyboardKey.browserBack) {
        Navigator.of(context).pop();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    // Overlay is visible — navigate buttons
    _resetOverlayTimer();

    if (key == LogicalKeyboardKey.arrowLeft) {
      if (_isOnTimeline) {
        // On timeline — seek left
        _startSeekHold(-10);
      } else {
        setState(() {
          _focusedButtonIndex =
              (_focusedButtonIndex - 1).clamp(0, _totalButtons - 1);
          _isOnTimeline = _focusedButtonIndex == 5;
        });
      }
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.arrowRight) {
      if (_isOnTimeline) {
        // On timeline — seek right
        _startSeekHold(10);
      } else {
        setState(() {
          _focusedButtonIndex =
              (_focusedButtonIndex + 1).clamp(0, _totalButtons - 1);
          _isOnTimeline = _focusedButtonIndex == 5;
        });
      }
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.arrowUp) {
      if (_isOnTimeline) {
        // Move up from timeline to buttons
        setState(() {
          _focusedButtonIndex = 1;
          _isOnTimeline = false;
        });
      }
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.arrowDown) {
      // Move down to timeline
      setState(() {
        _focusedButtonIndex = 5;
        _isOnTimeline = true;
      });
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      _activateFocusedButton();
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.escape ||
        key == LogicalKeyboardKey.goBack ||
        key == LogicalKeyboardKey.browserBack) {
      setState(() => _overlayVisible = false);
      return KeyEventResult.handled;
    }

    return KeyEventResult.handled;
  }

  void _showOverlay() {
    setState(() {
      _overlayVisible = true;
      _focusedButtonIndex = 1; // default to play/pause
      _isOnTimeline = false;
    });
    _resetOverlayTimer();
  }

  void _resetOverlayTimer() {
    _overlayHideTimer?.cancel();
    _overlayHideTimer = Timer(const Duration(seconds: 5), () {
      if (mounted) {
        setState(() => _overlayVisible = false);
      }
    });
  }

  void _startSeekHold(int seconds) {
    // Seek once immediately
    _seek(seconds);
    // Then keep seeking while held
    _seekHoldTimer?.cancel();
    _seekHoldTimer =
        Timer.periodic(const Duration(milliseconds: 500), (_) => _seek(seconds));
  }

  void _seek(int seconds) {
    final current = _ctrl.playbackState.value.position;
    final duration = _ctrl.playbackState.value.duration;
    final target = current + Duration(seconds: seconds);
    final clamped = target < Duration.zero
        ? Duration.zero
        : (duration > Duration.zero && target > duration ? duration : target);
    _ctrl.seekTo(clamped);
  }

  void _activateFocusedButton() {
    switch (_focusedButtonIndex) {
      case 0: // Back 10s
        _seek(-10);
        break;
      case 1: // Play/Pause
        final playing = _ctrl.playbackState.value.isPlaying;
        playing ? _ctrl.pause() : _ctrl.play();
        break;
      case 2: // Forward 10s
        _seek(10);
        break;
      case 3: // Subtitles - show subtitle selector
        // TODO: implement subtitle dialog
        break;
      case 4: // Audio - show audio selector
        // TODO: implement audio dialog
        break;
      case 5: // Timeline - already handled by arrows
        break;
    }
  }

  Widget _buildTvOverlay() {
    if (!_overlayVisible) return const SizedBox.shrink();

    final state = _ctrl.playbackState.value;
    final position = state.position;
    final duration = state.duration;
    final isPlaying = state.isPlaying;
    final totalMs = duration.inMilliseconds <= 0
        ? 1.0
        : duration.inMilliseconds.toDouble();
    final sliderValue = position.inMilliseconds.toDouble().clamp(0.0, totalMs);

    return Positioned.fill(
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xCC000000),
              Colors.transparent,
              Colors.transparent,
              Color(0xCC000000),
            ],
            stops: [0.0, 0.3, 0.7, 1.0],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                child: Column(
                  children: [
                    _buildFocusableButton(
                      index: 5,
                      child: SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          activeTrackColor:
                              _focusedButtonIndex == 5 ? Colors.blue : Colors.white,
                          thumbColor:
                              _focusedButtonIndex == 5 ? Colors.blue : Colors.white,
                          inactiveTrackColor: Colors.white38,
                          thumbShape: const RoundSliderThumbShape(
                            enabledThumbRadius: 8,
                          ),
                        ),
                        child: Slider(
                          value: sliderValue,
                          min: 0,
                          max: totalMs,
                          onChanged: (v) {
                            _ctrl.seekTo(Duration(milliseconds: v.toInt()));
                            _resetOverlayTimer();
                          },
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Row(
                        children: [
                          Text(
                            _formatDuration(position),
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 13,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            _formatDuration(duration),
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _buildFocusableButton(
                          index: 0,
                          child: const Icon(
                            Icons.replay_10,
                            color: Colors.white,
                            size: 36,
                          ),
                          onTap: () => _seek(-10),
                        ),
                        const SizedBox(width: 24),
                        _buildFocusableButton(
                          index: 1,
                          child: Icon(
                            isPlaying ? Icons.pause : Icons.play_arrow,
                            color: Colors.white,
                            size: 48,
                          ),
                          onTap: () => isPlaying ? _ctrl.pause() : _ctrl.play(),
                        ),
                        const SizedBox(width: 24),
                        _buildFocusableButton(
                          index: 2,
                          child: const Icon(
                            Icons.forward_10,
                            color: Colors.white,
                            size: 36,
                          ),
                          onTap: () => _seek(10),
                        ),
                        const SizedBox(width: 32),
                        _buildFocusableButton(
                          index: 3,
                          child: const Icon(
                            Icons.closed_caption,
                            color: Colors.white,
                            size: 28,
                          ),
                          onTap: () {
                            // TODO: subtitle dialog
                          },
                        ),
                        const SizedBox(width: 16),
                        _buildFocusableButton(
                          index: 4,
                          child: const Icon(
                            Icons.audiotrack,
                            color: Colors.white,
                            size: 28,
                          ),
                          onTap: () {
                            // TODO: audio dialog
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFocusableButton({
    required int index,
    required Widget child,
    VoidCallback? onTap,
  }) {
    final isFocused = _focusedButtonIndex == index && _overlayVisible;
    return GestureDetector(
      onTap: () {
        setState(() {
          _focusedButtonIndex = index;
          _isOnTimeline = index == 5;
        });
        onTap?.call();
        _resetOverlayTimer();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: isFocused ? Colors.white.withOpacity(0.25) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: isFocused ? Border.all(color: Colors.white, width: 2) : null,
        ),
        child: child,
      ),
    );
  }

  String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '${d.inMinutes}:$s';
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
    _seekHoldTimer?.cancel();
    _overlayHideTimer?.cancel();
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
        body: Focus(
          focusNode: _playerFocusNode,
          autofocus: true,
          onKeyEvent: (node, event) => _handleKeyEvent(event),
          child: SizedBox.expand(
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
                    ),
                ),
              ),

              ValueListenableBuilder<ThaPlaybackState>(
                valueListenable: _ctrl.playbackState,
                builder: (_, state, __) => _buildTvOverlay(),
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
