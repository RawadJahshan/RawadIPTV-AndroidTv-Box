import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
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
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  DateTime? _lastProgressSaveAt;
  bool _isSavingFinalProgress = false;

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

  Duration _toDuration(dynamic value) {
    if (value is Duration) return value;
    if (value is int) return Duration(milliseconds: value);
    if (value is double) {
      return Duration(milliseconds: value.toInt());
    }
    return Duration.zero;
  }

  void _onPositionChanged(dynamic position, dynamic duration) {
    _position = _toDuration(position);
    _duration = _toDuration(duration);
    unawaited(_saveProgress());
  }

  Future<void> _saveFinalProgress() async {
    if (_isSavingFinalProgress) return;
    _isSavingFinalProgress = true;
    try {
      await _saveProgress(force: true);
    } finally {
      _isSavingFinalProgress = false;
    }
  }

  @override
  void dispose() {
    unawaited(_saveFinalProgress());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) {
          unawaited(_saveFinalProgress());
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          title: Text(
            widget.title,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        body: ThaModernPlayer(
          src: widget.streamUrl,
          httpHeaders: const {
            'User-Agent': 'Mozilla/5.0 (Linux; Android 10)',
            'Connection': 'keep-alive',
          },
          autoPlay: true,
          startAt: widget.startAt,
          onPositionChanged: _onPositionChanged,
        ),
      ),
    );
  }
}
