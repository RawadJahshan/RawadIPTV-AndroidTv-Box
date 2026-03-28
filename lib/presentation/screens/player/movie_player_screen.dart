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

  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  DateTime? _lastProgressSaveAt;

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

    if (widget.startAt != null && widget.startAt! > Duration.zero) {
      Future.delayed(const Duration(seconds: 2), () {
        _ctrl.seekTo(widget.startAt!);
      });
    }

    _progressTimer =
        Timer.periodic(const Duration(seconds: 5), (_) => _saveProgress());
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
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) {
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
              bottom: 0,
              right: 0,
              child: SizedBox(
                width: 56,
                height: 56,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {},
                ),
              ),
            ),
            ValueListenableBuilder<ThaPlaybackState>(
              valueListenable: _ctrl.playbackState,
              builder: (_, state, __) {
                _position = state.position;
                _duration = state.duration;
                return const SizedBox.shrink();
              },
            ),
          ],
        ),
      ),
    );
  }
}
