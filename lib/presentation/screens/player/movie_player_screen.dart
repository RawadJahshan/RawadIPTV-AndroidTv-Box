import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import '../../../data/services/watch_progress_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  late final Player _player;
  late final VideoController _controller;
  bool _overlayVisible = true;
  Timer? _hideTimer;
  bool _isSeeking = false;
  double? _sliderDragValue;
  bool _isBuffering = true;
  bool _isPlaying = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  Timer? _progressTimer;
  bool _didResume = false;
  int _aspectRatioIndex = 0;

  final List<Map<String, dynamic>> _aspectRatios = [
    {'label': 'Auto', 'ratio': BoxFit.contain},
    {'label': 'Fill', 'ratio': BoxFit.fill},
    {'label': 'Cover', 'ratio': BoxFit.cover},
    {'label': '16:9', 'ratio': BoxFit.fitWidth},
    {'label': '4:3', 'ratio': BoxFit.fitHeight},
  ];

  @override
  void initState() {
    super.initState();
    _initPlayer();
  }

  Future<void> _initPlayer() async {
    _player = Player();
    _controller = VideoController(_player);

    _player.stream.position.listen((pos) {
      if (!mounted) return;
      setState(() => _position = pos);
      if (!_didResume &&
          widget.startAt != null &&
          widget.startAt! > Duration.zero &&
          _duration > Duration.zero &&
          pos > Duration.zero) {
        _didResume = true;
        final target = widget.startAt! > _duration
            ? _duration - const Duration(seconds: 2)
            : widget.startAt!;
        _player.seek(target < Duration.zero ? Duration.zero : target);
      }
    });

    _player.stream.duration.listen((dur) {
      if (!mounted) return;
      setState(() => _duration = dur);
    });

    _player.stream.buffering.listen((buffering) {
      if (!mounted) return;
      setState(() => _isBuffering = buffering);
    });

    _player.stream.playing.listen((playing) {
      if (!mounted) return;
      setState(() => _isPlaying = playing);
    });

    await _player.open(Media(widget.streamUrl, httpHeaders: {
      'User-Agent': 'Mozilla/5.0 (Linux; Android 10)',
      'Connection': 'keep-alive',
    }));

    _progressTimer =
        Timer.periodic(const Duration(seconds: 5), (_) => _saveProgress());

    _scheduleHide();
  }

  Future<void> _saveProgress() async {
    if (_duration.inMilliseconds <= 0) return;
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

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _overlayVisible = false);
    });
  }

  void _showOverlay() {
    if (!_overlayVisible) setState(() => _overlayVisible = true);
    _scheduleHide();
  }

  void _skip(int seconds) {
    final target = _position + Duration(seconds: seconds);
    if (target < Duration.zero) {
      _player.seek(Duration.zero);
    } else if (_duration > Duration.zero && target > _duration) {
      _player.seek(_duration);
    } else {
      _player.seek(target);
    }
  }

  Future<void> _seekTo(Duration target) async {
    setState(() => _isSeeking = true);
    try {
      await _player.seek(target);
      await Future<void>.delayed(const Duration(milliseconds: 200));
    } finally {
      if (mounted) setState(() => _isSeeking = false);
    }
  }

  String _fmt(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '${d.inMinutes}:$s';
  }

  @override
  void dispose() {
    _saveProgress();
    _hideTimer?.cancel();
    _progressTimer?.cancel();
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final totalMs =
        _duration.inMilliseconds <= 0 ? 1.0 : _duration.inMilliseconds.toDouble();
    final sliderValue = (_sliderDragValue ?? _position.inMilliseconds.toDouble())
        .clamp(0.0, totalMs);

    return PopScope(
      canPop: true,
      child: Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onDoubleTapDown: (details) {
          final screenWidth = MediaQuery.of(context).size.width;
          if (details.localPosition.dx < screenWidth / 2) {
            _skip(-10);
          } else {
            _skip(10);
          }
          _showOverlay();
        },
        onTap: _showOverlay,
        child: Stack(
          children: [
            Positioned.fill(
              child: Video(
                controller: _controller,
                fit: _aspectRatios[_aspectRatioIndex]['ratio'] as BoxFit,
                controls: NoVideoControls,
              ),
            ),
            if (_isBuffering || _isSeeking)
              const Positioned.fill(
                child: Center(
                  child: CircularProgressIndicator(color: Colors.white),
                ),
              ),
            if (_overlayVisible)
              Positioned.fill(
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
                      stops: [0.0, 0.25, 0.75, 1.0],
                    ),
                  ),
                  child: SafeArea(
                    child: Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 8),
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
                                iconSize: 28,
                                icon: const Icon(Icons.close, color: Colors.white),
                                onPressed: () => Navigator.of(context).pop(),
                              ),
                            ],
                          ),
                        ),
                        const Spacer(),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: Column(
                            children: [
                              Slider(
                                value: sliderValue,
                                min: 0,
                                max: totalMs,
                                onChangeStart: (v) =>
                                    setState(() => _sliderDragValue = v),
                                onChanged: (v) =>
                                    setState(() => _sliderDragValue = v),
                                onChangeEnd: (v) {
                                  setState(() => _sliderDragValue = null);
                                  _seekTo(Duration(milliseconds: v.toInt()));
                                },
                              ),
                              Padding(
                                padding: const EdgeInsets.only(
                                    left: 8, right: 8, bottom: 12),
                                child: Row(
                                  children: [
                                    Text(
                                      '${_fmt(_position)} / ${_fmt(_duration)}',
                                      style: const TextStyle(
                                          color: Colors.white70, fontSize: 13),
                                    ),
                                    const Spacer(),
                                    IconButton(
                                      iconSize: 28,
                                      icon: const Icon(Icons.replay_10,
                                          color: Colors.white),
                                      onPressed: () => _skip(-10),
                                    ),
                                    IconButton(
                                      iconSize: 32,
                                      icon: Icon(
                                        _isPlaying
                                            ? Icons.pause
                                            : Icons.play_arrow,
                                        color: Colors.white,
                                        size: 32,
                                      ),
                                      onPressed: () => _player.playOrPause(),
                                    ),
                                    IconButton(
                                      iconSize: 28,
                                      icon: const Icon(Icons.forward_10,
                                          color: Colors.white),
                                      onPressed: () => _skip(10),
                                    ),
                                    PopupMenuButton<int>(
                                      tooltip: 'Aspect Ratio',
                                      icon: const Icon(Icons.aspect_ratio,
                                          color: Colors.white),
                                      iconSize: 28,
                                      onSelected: (index) {
                                        setState(() => _aspectRatioIndex = index);
                                      },
                                      itemBuilder: (_) => _aspectRatios
                                          .asMap()
                                          .entries
                                          .map((e) => PopupMenuItem(
                                                value: e.key,
                                                child: Text(
                                                    e.value['label'] as String),
                                              ))
                                          .toList(),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
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
