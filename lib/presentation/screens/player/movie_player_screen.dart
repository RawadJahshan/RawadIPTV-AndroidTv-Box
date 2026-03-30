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
  static const Duration _overlayAutoHideDuration = Duration(seconds: 8);
  static const Duration _tvSeekStep = Duration(seconds: 10);

  late ThaNativePlayerController _ctrl;

  final FocusNode _rootFocusNode = FocusNode(debugLabel: 'movie_player_root');
  final FocusScopeNode _overlayFocusScope = FocusScopeNode(debugLabel: 'movie_player_overlay_scope');
  final FocusNode _playPauseFocusNode = FocusNode(debugLabel: 'movie_player_play_pause');
  final FocusNode _timelineFocusNode = FocusNode(debugLabel: 'movie_player_timeline');
  final FocusNode _subtitleFocusNode = FocusNode(debugLabel: 'movie_player_subtitle');
  final FocusNode _audioFocusNode = FocusNode(debugLabel: 'movie_player_audio');
  final FocusNode _qualityFocusNode = FocusNode(debugLabel: 'movie_player_quality');

  Timer? _progressTimer;
  Timer? _overlayHideTimer;

  String? _errorMessage;
  bool _show4KDialog = false;

  bool _overlayVisible = false;
  bool _timelineSeekMode = false;
  Duration? _pendingSeekPosition;

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

  void showOverlay() {
    if (!mounted) return;

    setState(() {
      _overlayVisible = true;
      _timelineSeekMode = false;
      _pendingSeekPosition = null;
    });

    restartOverlayTimer();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        FocusScope.of(context).setFirstFocus(_overlayFocusScope);
        _playPauseFocusNode.requestFocus();
      }
    });
  }

  void hideOverlay() {
    if (!mounted || !_overlayVisible) return;

    _overlayHideTimer?.cancel();
    setState(() {
      _overlayVisible = false;
      _timelineSeekMode = false;
      _pendingSeekPosition = null;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _rootFocusNode.requestFocus();
      }
    });
  }

  void restartOverlayTimer() {
    _overlayHideTimer?.cancel();
    _overlayHideTimer = Timer(_overlayAutoHideDuration, hideOverlay);
  }

  bool _isSelectKey(LogicalKeyboardKey key) {
    return key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.gameButtonA;
  }

  bool _isArrowKey(LogicalKeyboardKey key) {
    return key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.arrowDown ||
        key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.arrowRight;
  }

  Duration _clampPosition(Duration value) {
    final max = _duration > Duration.zero ? _duration : value;
    if (value < Duration.zero) return Duration.zero;
    if (max <= Duration.zero) return value;
    return value > max ? max : value;
  }

  KeyEventResult handleTimelineKey(KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    final key = event.logicalKey;

    if (key == LogicalKeyboardKey.arrowLeft || key == LogicalKeyboardKey.arrowRight) {
      final base = _pendingSeekPosition ?? _position;
      final next = key == LogicalKeyboardKey.arrowLeft ? base - _tvSeekStep : base + _tvSeekStep;

      setState(() {
        _timelineSeekMode = true;
        _pendingSeekPosition = _clampPosition(next);
      });
      restartOverlayTimer();
      return KeyEventResult.handled;
    }

    if (_isSelectKey(key)) {
      commitSeek();
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.arrowUp) {
      _playPauseFocusNode.requestFocus();
      restartOverlayTimer();
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  KeyEventResult handleRootKey(FocusNode node, KeyEvent event) {
    if (!_isAndroidPlatform || event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }

    if (_show4KDialog || _errorMessage != null) {
      return KeyEventResult.ignored;
    }

    final key = event.logicalKey;

    if (key == LogicalKeyboardKey.goBack ||
        key == LogicalKeyboardKey.escape ||
        key == LogicalKeyboardKey.browserBack) {
      return KeyEventResult.ignored;
    }

    if (_isSelectKey(key) && !_overlayVisible) {
      showOverlay();
      return KeyEventResult.handled;
    }

    if (!_overlayVisible) {
      return KeyEventResult.ignored;
    }

    if (_timelineFocusNode.hasFocus) {
      final result = handleTimelineKey(event);
      if (result == KeyEventResult.handled) {
        return result;
      }
    }

    if (_isSelectKey(key)) {
      restartOverlayTimer();
      _activateFocusedControl();
      return KeyEventResult.handled;
    }

    if (_isArrowKey(key)) {
      restartOverlayTimer();
      return KeyEventResult.ignored;
    }

    return KeyEventResult.ignored;
  }

  Future<void> commitSeek() async {
    final pending = _pendingSeekPosition;
    if (pending == null) return;

    setState(() {
      _timelineSeekMode = false;
      _pendingSeekPosition = null;
    });

    await _ctrl.seekTo(pending);
    if (mounted) {
      _timelineFocusNode.requestFocus();
      restartOverlayTimer();
    }
  }

  Future<void> openSubtitleMenu() async {
    restartOverlayTimer();
    final tracks = await _ctrl.getSubtitleTracks();
    if (!mounted) return;

    final options = <_TvMenuOption<String?>>[
      const _TvMenuOption(label: 'Off', value: null),
      ...tracks.map(
        (track) => _TvMenuOption<String?>(
          label: _trackLabel(track.label, track.language, fallback: track.id),
          value: track.id,
          selected: track.selected,
        ),
      ),
    ];

    final selected = await _showTvTrackSelectionDialog<String?>(
      title: 'Subtitles / CC',
      options: options,
    );

    if (!mounted) return;

    await _ctrl.selectSubtitleTrack(selected);
    if (mounted) {
      _subtitleFocusNode.requestFocus();
      restartOverlayTimer();
    }
  }

  Future<void> openAudioTrackMenu() async {
    restartOverlayTimer();
    final tracks = await _ctrl.getAudioTracks();
    if (!mounted) return;

    final options = tracks
        .map(
          (track) => _TvMenuOption<String>(
            label: _trackLabel(track.label, track.language, fallback: track.id),
            value: track.id,
            selected: track.selected,
          ),
        )
        .toList();

    final selected = await _showTvTrackSelectionDialog<String>(
      title: 'Audio Tracks',
      options: options,
    );

    if (!mounted || selected == null) {
      _audioFocusNode.requestFocus();
      return;
    }

    await _ctrl.selectAudioTrack(selected);
    if (mounted) {
      _audioFocusNode.requestFocus();
      restartOverlayTimer();
    }
  }

  Future<void> openQualityMenu() async {
    restartOverlayTimer();
    final tracks = await _ctrl.getVideoTracks();
    if (!mounted) return;

    final options = <_TvMenuOption<String>>[
      const _TvMenuOption(label: 'Auto', value: '__auto__'),
      ...tracks.map(
        (track) => _TvMenuOption<String>(
          label: track.displayLabel,
          value: track.id,
          selected: track.selected,
        ),
      ),
    ];

    final selected = await _showTvTrackSelectionDialog<String>(
      title: 'Quality',
      options: options,
    );

    if (!mounted || selected == null) {
      _qualityFocusNode.requestFocus();
      return;
    }

    if (selected == '__auto__') {
      await _ctrl.clearVideoTrackSelection();
    } else {
      await _ctrl.selectVideoTrack(selected);
    }

    if (mounted) {
      _qualityFocusNode.requestFocus();
      restartOverlayTimer();
    }
  }

  Future<T?> _showTvTrackSelectionDialog<T>({
    required String title,
    required List<_TvMenuOption<T>> options,
  }) async {
    final selected = await showDialog<T>(
      context: context,
      builder: (context) => _TvTrackSelectionDialog<T>(
        title: title,
        options: options,
      ),
    );

    if (!mounted) return selected;

    restartOverlayTimer();
    return selected;
  }

  void _activateFocusedControl() {
    if (_playPauseFocusNode.hasFocus) {
      final isPlaying = _ctrl.playbackState.value.isPlaying;
      if (isPlaying) {
        _ctrl.pause();
      } else {
        _ctrl.play();
      }
      return;
    }

    if (_timelineFocusNode.hasFocus) {
      commitSeek();
      return;
    }

    if (_subtitleFocusNode.hasFocus) {
      openSubtitleMenu();
      return;
    }

    if (_audioFocusNode.hasFocus) {
      openAudioTrackMenu();
      return;
    }

    if (_qualityFocusNode.hasFocus) {
      openQualityMenu();
    }
  }

  String _trackLabel(String? label, String? language, {required String fallback}) {
    if (label != null && label.trim().isNotEmpty) return label.trim();
    if (language != null && language.trim().isNotEmpty) return language.trim();
    return fallback;
  }

  String _formatDuration(Duration value) {
    final h = value.inHours;
    final mm = value.inMinutes.remainder(60).toString().padLeft(2, '0');
    final ss = value.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (h > 0) {
      return '$h:$mm:$ss';
    }
    return '$mm:$ss';
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
      if (mounted) {
        _rootFocusNode.requestFocus();
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

  @override
  void dispose() {
    _restoreLandscapeAndSystemUi();
    _progressTimer?.cancel();
    _overlayHideTimer?.cancel();
    _overlayFocusScope.dispose();
    _playPauseFocusNode.dispose();
    _timelineFocusNode.dispose();
    _subtitleFocusNode.dispose();
    _audioFocusNode.dispose();
    _qualityFocusNode.dispose();
    _rootFocusNode.dispose();
    unawaited(_saveProgress(force: true));
    try {
      _ctrl.playbackState.removeListener(_syncPlaybackState);
      _ctrl.dispose();
    } catch (_) {}
    super.dispose();
  }

  Widget _buildTvPlayer() {
    final activePosition = _pendingSeekPosition ?? _position;

    return FocusTraversalGroup(
      policy: OrderedTraversalPolicy(),
      child: Focus(
        focusNode: _rootFocusNode,
        autofocus: true,
        onKeyEvent: handleRootKey,
        child: Stack(
          children: [
            Positioned.fill(
              child: ExcludeFocus(
                excluding: true,
                child: IgnorePointer(
                  ignoring: true,
                  child: ThaNativePlayerView(
                    controller: _ctrl,
                    boxFit: BoxFit.contain,
                  ),
                ),
              ),
            ),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                  child: Text(
                    widget.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 18,
                      shadows: [Shadow(color: Colors.black87, blurRadius: 6)],
                    ),
                  ),
                ),
              ),
            ),
            if (_overlayVisible)
              Positioned.fill(
                child: FocusScope(
                  node: _overlayFocusScope,
                  child: Container(
                    color: Colors.black45,
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      child: SafeArea(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(26, 22, 26, 30),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Focus(
                                focusNode: _timelineFocusNode,
                                onKeyEvent: (_, event) => handleTimelineKey(event),
                                child: _TvTimelineBar(
                                  focused: _timelineFocusNode.hasFocus,
                                  position: activePosition,
                                  duration: _duration,
                                  isPendingSeek: _timelineSeekMode,
                                  formatDuration: _formatDuration,
                                ),
                              ),
                              const SizedBox(height: 14),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  _TvControlButton(
                                    focusNode: _playPauseFocusNode,
                                    label: _ctrl.playbackState.value.isPlaying ? 'Pause' : 'Play',
                                    icon: _ctrl.playbackState.value.isPlaying ? Icons.pause : Icons.play_arrow,
                                    onPressed: _activateFocusedControl,
                                  ),
                                  const SizedBox(width: 12),
                                  _TvControlButton(
                                    focusNode: _subtitleFocusNode,
                                    label: 'CC',
                                    icon: Icons.subtitles,
                                    onPressed: openSubtitleMenu,
                                  ),
                                  const SizedBox(width: 12),
                                  _TvControlButton(
                                    focusNode: _audioFocusNode,
                                    label: 'Audio',
                                    icon: Icons.audiotrack,
                                    onPressed: openAudioTrackMenu,
                                  ),
                                  const SizedBox(width: 12),
                                  _TvControlButton(
                                    focusNode: _qualityFocusNode,
                                    label: 'Quality',
                                    icon: Icons.tune,
                                    onPressed: openQualityMenu,
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
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
  Widget build(BuildContext context) {
    final isTvMode = _isAndroidPlatform && MediaQuery.maybeNavigationModeOf(context) == NavigationMode.directional;

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

class _TvControlButton extends StatelessWidget {
  final FocusNode focusNode;
  final String label;
  final IconData icon;
  final VoidCallback onPressed;

  const _TvControlButton({
    required this.focusNode,
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return FocusableActionDetector(
      focusNode: focusNode,
      onShowFocusHighlight: (_) {},
      child: Builder(
        builder: (context) {
          final focused = Focus.of(context).hasFocus;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: focused ? Colors.white : Colors.white30,
                width: focused ? 2 : 1,
              ),
              color: focused ? Colors.blueAccent : const Color(0xCC111111),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: onPressed,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, color: Colors.white),
                    const SizedBox(width: 8),
                    Text(
                      label,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _TvTimelineBar extends StatelessWidget {
  final bool focused;
  final Duration position;
  final Duration duration;
  final bool isPendingSeek;
  final String Function(Duration value) formatDuration;

  const _TvTimelineBar({
    required this.focused,
    required this.position,
    required this.duration,
    required this.isPendingSeek,
    required this.formatDuration,
  });

  @override
  Widget build(BuildContext context) {
    final progress = duration.inMilliseconds > 0 ? position.inMilliseconds / duration.inMilliseconds : 0.0;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: const Color(0xE6111111),
        border: Border.all(
          color: focused ? Colors.blueAccent : Colors.white30,
          width: focused ? 2 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LinearProgressIndicator(
            value: progress.clamp(0.0, 1.0),
            minHeight: 7,
            backgroundColor: Colors.white24,
            valueColor: const AlwaysStoppedAnimation(Colors.blueAccent),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(formatDuration(position), style: const TextStyle(color: Colors.white)),
              Text(formatDuration(duration), style: const TextStyle(color: Colors.white)),
            ],
          ),
          if (isPendingSeek)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'Press OK to seek to ${formatDuration(position)}',
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ),
        ],
      ),
    );
  }
}

class _TvMenuOption<T> {
  final String label;
  final T value;
  final bool selected;

  const _TvMenuOption({
    required this.label,
    required this.value,
    this.selected = false,
  });
}

class _TvTrackSelectionDialog<T> extends StatelessWidget {
  final String title;
  final List<_TvMenuOption<T>> options;

  const _TvTrackSelectionDialog({
    required this.title,
    required this.options,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF1A1A1A),
      insetPadding: const EdgeInsets.symmetric(horizontal: 42, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460, maxHeight: 420),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              Flexible(
                child: FocusTraversalGroup(
                  policy: OrderedTraversalPolicy(),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: options.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 6),
                    itemBuilder: (context, index) {
                      final option = options[index];
                      return _TvDialogOptionTile<T>(
                        autofocus: index == 0,
                        option: option,
                        onPressed: () => Navigator.of(context).pop(option.value),
                      );
                    },
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

class _TvDialogOptionTile<T> extends StatefulWidget {
  final bool autofocus;
  final _TvMenuOption<T> option;
  final VoidCallback onPressed;

  const _TvDialogOptionTile({
    required this.autofocus,
    required this.option,
    required this.onPressed,
  });

  @override
  State<_TvDialogOptionTile<T>> createState() => _TvDialogOptionTileState<T>();
}

class _TvDialogOptionTileState<T> extends State<_TvDialogOptionTile<T>> {
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode(debugLabel: 'tv_dialog_option_${widget.option.label}');
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FocusableActionDetector(
      focusNode: _focusNode,
      autofocus: widget.autofocus,
      child: Builder(
        builder: (context) {
          final focused = Focus.of(context).hasFocus;
          return InkWell(
            onTap: widget.onPressed,
            borderRadius: BorderRadius.circular(8),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 110),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                color: focused ? Colors.blueAccent : const Color(0xFF2A2A2A),
                border: Border.all(
                  color: focused ? Colors.white : Colors.white24,
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.option.label,
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                  if (widget.option.selected)
                    const Icon(Icons.check, color: Colors.white),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
