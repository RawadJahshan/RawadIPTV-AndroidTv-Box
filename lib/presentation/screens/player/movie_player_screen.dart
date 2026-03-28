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
  Timer? _progressTimer;
  bool _triedFallback = false;
  String? _errorMessage;

  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  DateTime? _lastProgressSaveAt;

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
        _ctrl.seekTo(widget.startAt!);
      });
    }

    _progressTimer =
        Timer.periodic(const Duration(seconds: 5), (_) => _saveProgress());
  }

  void _show4KFallbackDialog() {
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        title: const Text(
          '4K Not Supported',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'Your device does not support 4K playback.\n\n'
          'Would you like to try playing at 1080p instead?',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              Navigator.of(context).pop();
            },
            child: const Text(
              'Go Back',
              style: TextStyle(color: Colors.white54),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              unawaited(_retryAt1080p());
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
            ),
            child: const Text('Play 1080p'),
          ),
        ],
      ),
    );
  }

  Future<void> _retryAt1080p() async {
    if (!mounted) return;
    _triedFallback = true;

    try {
      _ctrl.playbackState.removeListener(_syncPlaybackState);
    } catch (_) {}

    try {
      _ctrl.dispose();
    } catch (_) {}

    final fallbackUrl = widget.streamUrl
        .replaceAll('.mkv', '.m3u8')
        .replaceAll('.mp4', '.m3u8');

    setState(() {
      _errorMessage = null;
    });

    _ctrl = ThaNativePlayerController.single(
      ThaMediaSource(
        fallbackUrl,
        headers: const {
          'User-Agent': 'Mozilla/5.0 (Linux; Android 10)',
          'Connection': 'keep-alive',
        },
      ),
      autoPlay: true,
    );
    _ctrl.playbackState.addListener(_syncPlaybackState);

    if (mounted) {
      setState(() {});
    }
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
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.immersiveSticky,
    );
    _initPlayer();
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
    unawaited(_saveProgress(force: true));
    _ctrl.playbackState.removeListener(_syncPlaybackState);
    _ctrl.dispose();
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
        body: Stack(
          children: [
            ThaModernPlayer(
              controller: _ctrl,
              doubleTapSeek: const Duration(seconds: 10),
              autoHideAfter: const Duration(seconds: 3),
              initialBoxFit: BoxFit.contain,
              autoFullscreen: true,
              onError: (error) {
                if (!mounted) return;
                final is4KError = (error ?? '').contains('EXCEEDS') ||
                    (error ?? '').contains('hevc') ||
                    (error ?? '').contains('3840');
                if (is4KError && !_triedFallback) {
                  _show4KFallbackDialog();
                } else {
                  setState(() {
                    _errorMessage = error ?? 'Playback error';
                  });
                }
              },
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
            Positioned(
              bottom: 8,
              right: 8,
              child: SizedBox(
                width: 48,
                height: 48,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {},
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
                        Text(
                          _errorMessage!,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 16,
                          ),
                          textAlign: TextAlign.center,
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
    );
  }
}
