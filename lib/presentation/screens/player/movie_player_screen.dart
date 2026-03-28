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
  String? _errorMessage;
  bool _show4KDialog = false;

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
        if (mounted) _ctrl.seekTo(widget.startAt!);
      });
    }

    _progressTimer =
        Timer.periodic(const Duration(seconds: 5), (_) => _saveProgress());
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
          _errorMessage = 'Playback error. Please try another stream.';
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
                            const Text(
                              '4K Not Supported',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 12),
                            const Text(
                              'Your device does not support 4K playback.\n\n'
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