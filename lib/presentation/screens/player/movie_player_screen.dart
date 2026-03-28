import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:dart_vlc/dart_vlc.dart';
import '../../../data/services/watch_progress_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

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
  late Player _player;
  bool _overlayVisible = true;
  Timer? _hideTimer;
  bool _isSeeking = false;
  double? _sliderDragValue;
  bool _isBuffering = true;
  bool _isPlaying = false;
  bool _isFullscreen = false;
  int _bufferPercent = 0;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  Timer? _progressTimer;
  List<Map<String, dynamic>> _audioTracks = [];
  List<SubtitleTrack> _subtitleTracks = [];
  int _selectedAudioTrack = -1;
  int _selectedSubTrack = -1;
  int _aspectRatioIndex = 0;
  bool _didResume = false;
  bool _didRefreshTracks = false;

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
    _player = Player(id: widget.streamId);

    _attachPlayerListeners();
    _player.setUserAgent('Mozilla/5.0 (Windows NT 10.0; Win64; x64)');

    _player.open(
      Media.network(widget.streamUrl),
      autoStart: true,
    );

    if (widget.startAt != null && widget.startAt! > Duration.zero) {
      await Future<void>.delayed(const Duration(seconds: 2));
      _player.seek(widget.startAt!);
    }

    _progressTimer = Timer.periodic(
      const Duration(seconds: 5), (_) => _saveProgress());

    _scheduleHide();
  }

  Future<void> _refreshSubtitleTracks() async {
    final subTracks = _player.subtitleTracks;
    List<Map<String, dynamic>> audioTracks = [];
    try {
      final tracks = (_player as dynamic).audioTracks as List;
      audioTracks = tracks
          .map((t) => {
                'id': (t as dynamic).id as int,
                'name': (t as dynamic).name as String,
              })
          .toList();
    } catch (e) {
      debugPrint('[Player] audioTracks error: $e');
      final count = _player.audioTrackCount;
      audioTracks = List.generate(
        count,
        (i) => {
          'id': i,
          'name': 'Audio ${i + 1}',
        },
      );
    }
    debugPrint(
      '[Player] subs=${subTracks.map((t) => '${t.id}:${t.name}').toList()}',
    );
    debugPrint('[Player] audio=$audioTracks');
    if (!mounted) return;
    setState(() {
      _subtitleTracks = subTracks;
      _audioTracks = audioTracks;
    });
  }

  void _attachPlayerListeners({Duration? resumeAt}) {
    _player.positionStream.listen((pos) {
      if (!mounted) return;
      final newPos = pos.position ?? Duration.zero;
      final newDur = pos.duration ?? Duration.zero;
      setState(() {
        _position = newPos;
        _duration = newDur;
      });

      if (!_didResume &&
          resumeAt != null &&
          resumeAt > Duration.zero &&
          newDur > Duration.zero &&
          newPos > Duration.zero) {
        _didResume = true;
        _doResume(resumeAt, newDur);
      }
    });

    _player.bufferingProgressStream.listen((percent) {
      if (!mounted) return;
      setState(() {
        _bufferPercent = percent.toInt();
        _isBuffering = percent < 100;
      });
    });

    _player.playbackStream.listen((playback) {
      if (!mounted) return;
      setState(() {
        _isPlaying = playback.isPlaying;
        _isBuffering = !playback.isPlaying && !playback.isCompleted;
      });
      if (playback.isPlaying && !_didRefreshTracks) {
        _didRefreshTracks = true;
        unawaited(_refreshSubtitleTracks());
      }
    });
  }

  void _doResume(Duration startAt, Duration totalDuration) {
    final target = startAt > totalDuration ? totalDuration : startAt;
    _player.seek(target);
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
      _player.seek(target);
      await Future<void>.delayed(const Duration(milliseconds: 300));
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

  Future<void> _toggleFullscreen() async {
    try {
      final newValue = !_isFullscreen;
      setState(() => _isFullscreen = newValue);
      await WindowManager.instance.setFullScreen(newValue);
    } catch (e) {
      debugPrint('[Player] fullscreen error: $e');
      setState(() => _isFullscreen = false);
    }
  }

  Future<void> _exitFullscreen() async {
    setState(() => _isFullscreen = false);
    await WindowManager.instance.setFullScreen(false);
  }

  @override
  void dispose() {
    WindowManager.instance.setFullScreen(false);
    _saveProgress();
    _hideTimer?.cancel();
    _progressTimer?.cancel();
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final totalMs = _duration.inMilliseconds <= 0
        ? 1.0
        : _duration.inMilliseconds.toDouble();
    final sliderValue =
        (_sliderDragValue ?? _position.inMilliseconds.toDouble())
            .clamp(0.0, totalMs);

    return KeyboardListener(
      focusNode: FocusNode()..requestFocus(),
      autofocus: true,
      onKeyEvent: (event) {
        if (event is KeyDownEvent) {
          if (event.logicalKey == LogicalKeyboardKey.arrowRight) _skip(30);
          if (event.logicalKey == LogicalKeyboardKey.arrowLeft) _skip(-30);
          if (event.logicalKey == LogicalKeyboardKey.space) _player.playOrPause();
          if (event.logicalKey == LogicalKeyboardKey.keyF) {
            unawaited(_toggleFullscreen());
          }
          if (event.logicalKey == LogicalKeyboardKey.escape && _isFullscreen) {
            unawaited(_exitFullscreen());
          }
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: MouseRegion(
          onHover: (_) => _showOverlay(),
          child: GestureDetector(
            onTap: _showOverlay,
            child: Stack(
              children: [
                // Video
                Positioned.fill(
                  child: Video(
                    player: _player,
                    fit: _aspectRatios[_aspectRatioIndex]['ratio'] as BoxFit,
                    showControls: false,
                  ),
                ),

                // Buffering text top center
                if (_isBuffering)
                  Positioned(
                    top: 20,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          'Buffering $_bufferPercent%',
                          style: const TextStyle(
                              color: Colors.white, fontSize: 13),
                        ),
                      ),
                    ),
                  ),

                // Seeking spinner
                if (_isSeeking)
                  const Positioned.fill(
                    child: Center(
                      child: CircularProgressIndicator(color: Colors.white),
                    ),
                  ),

                // Overlay
                if (_overlayVisible)
                  Positioned.fill(
                    child: AnimatedOpacity(
                      opacity: 1.0,
                      duration: const Duration(milliseconds: 300),
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
                              // Top bar
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
                                      tooltip: 'Refresh Tracks',
                                      icon: const Icon(Icons.refresh,
                                          color: Colors.white),
                                      onPressed: _refreshSubtitleTracks,
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.close,
                                          color: Colors.white),
                                      onPressed: () =>
                                          Navigator.of(context).pop(),
                                    ),
                                  ],
                                ),
                              ),

                              const Spacer(),

                              // Bottom bar
                              Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 8),
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
                                        _seekTo(Duration(
                                            milliseconds: v.toInt()));
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
                                                color: Colors.white70,
                                                fontSize: 13),
                                          ),
                                          const Spacer(),
                                          // Skip back
                                          IconButton(
                                            icon: const Icon(Icons.replay_30,
                                                color: Colors.white),
                                            onPressed: () => _skip(-30),
                                          ),
                                          // Play/Pause
                                          IconButton(
                                            icon: Icon(
                                              _isPlaying
                                                  ? Icons.pause
                                                  : Icons.play_arrow,
                                              color: Colors.white,
                                              size: 32,
                                            ),
                                            onPressed: () =>
                                                _player.playOrPause(),
                                          ),
                                          // Skip forward
                                          IconButton(
                                            icon: const Icon(Icons.forward_30,
                                                color: Colors.white),
                                            onPressed: () => _skip(30),
                                          ),
                                          // Audio tracks
                                          if (_audioTracks.length > 1)
                                            PopupMenuButton<int>(
                                              tooltip: 'Audio Track',
                                              icon: const Icon(Icons.audiotrack,
                                                  color: Colors.white),
                                              onSelected: (trackId) {
                                                setState(() =>
                                                    _selectedAudioTrack = trackId);
                                                _player.setAudioTrack(trackId);
                                              },
                                              itemBuilder: (_) => _audioTracks
                                                  .map<PopupMenuEntry<int>>(
                                                (track) => PopupMenuItem<int>(
                                                  value: track['id'] as int,
                                                  child: Row(
                                                    children: [
                                                      if (_selectedAudioTrack ==
                                                          track['id'] as int)
                                                        const Padding(
                                                          padding: EdgeInsets.only(right: 8),
                                                          child: Icon(Icons.check, size: 16),
                                                        ),
                                                      Text(track['name'] as String),
                                                    ],
                                                  ),
                                                ),
                                              ).toList(),
                                            ),
                                          PopupMenuButton<int>(
                                            tooltip: 'Subtitles',
                                            icon: Icon(
                                              _selectedSubTrack == -1
                                                  ? Icons.closed_caption_disabled
                                                  : Icons.closed_caption,
                                              color: Colors.white,
                                            ),
                                            onSelected: (trackId) async {
                                              setState(() => _selectedSubTrack = trackId);
                                              if (trackId == -1) {
                                                await _player.disableSubtitleTrack();
                                              } else {
                                                await _player.setSubtitleTrack(trackId);
                                              }
                                            },
                                            itemBuilder: (_) => [
                                              PopupMenuItem<int>(
                                                value: -1,
                                                child: Row(
                                                  children: [
                                                    if (_selectedSubTrack == -1)
                                                      const Padding(
                                                        padding:
                                                            EdgeInsets.only(
                                                                right: 8),
                                                        child: Icon(Icons.check,
                                                            size: 16),
                                                      ),
                                                    const Text('Off'),
                                                  ],
                                                ),
                                              ),
                                              ..._subtitleTracks.map(
                                                (track) => PopupMenuItem<int>(
                                                  value: track.id,
                                                  child: Row(
                                                    children: [
                                                      if (_selectedSubTrack == track.id)
                                                        const Padding(
                                                          padding: EdgeInsets.only(right: 8),
                                                          child: Icon(Icons.check, size: 16),
                                                        ),
                                                      Text(track.name),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                          PopupMenuButton<int>(
                                            tooltip: 'Aspect Ratio',
                                            icon: const Icon(
                                              Icons.aspect_ratio,
                                              color: Colors.white,
                                            ),
                                            onSelected: (index) {
                                              setState(
                                                  () => _aspectRatioIndex = index);
                                            },
                                            itemBuilder: (_) => _aspectRatios
                                                .asMap()
                                                .entries
                                                .map(
                                                  (e) => PopupMenuItem(
                                                    value: e.key,
                                                    child: Row(
                                                      children: [
                                                        if (_aspectRatioIndex ==
                                                            e.key)
                                                          const Padding(
                                                            padding:
                                                                EdgeInsets.only(
                                                                    right: 8),
                                                            child: Icon(
                                                                Icons.check,
                                                                size: 16),
                                                          ),
                                                        Text(e.value['label']
                                                            as String),
                                                      ],
                                                    ),
                                                  ),
                                                )
                                                .toList(),
                                          ),
                                          IconButton(
                                            icon: Icon(
                                              _isFullscreen
                                                  ? Icons.fullscreen_exit
                                                  : Icons.fullscreen,
                                              color: Colors.white,
                                            ),
                                            onPressed: () =>
                                                _toggleFullscreen(),
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
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
