import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

class TrackInfo {
  final int index;
  final String type;
  final String name;
  final String codec;

  TrackInfo({
    required this.index,
    required this.type,
    required this.name,
    required this.codec,
  });
}

class TrackInfoService {
  static String _getFfprobePath() {
    final exeDir = File(Platform.resolvedExecutable).parent.path;
    final candidates = [
      '$exeDir\\ffprobe.exe',
      '$exeDir\\data\\flutter_assets\\ffprobe.exe',
      '$exeDir\\ffmpeg\\bin\\ffprobe.exe',
    ];
    for (final path in candidates) {
      if (File(path).existsSync()) return path;
    }
    return 'ffprobe';
  }

  static String _getFfmpegPath() {
    final exeDir = File(Platform.resolvedExecutable).parent.path;
    final candidates = [
      '$exeDir\\ffmpeg.exe',
      '$exeDir\\data\\flutter_assets\\ffmpeg.exe',
      '$exeDir\\ffmpeg\\bin\\ffmpeg.exe',
    ];
    for (final path in candidates) {
      if (File(path).existsSync()) return path;
    }
    return 'ffmpeg';
  }

  static List<TrackInfo> _parseFfprobeTracks(Map<String, dynamic> json) {
    final streams = json['streams'] as List? ?? [];
    final tracks = <TrackInfo>[];
    var audioFallback = 0;
    var subFallback = 0;

    for (final stream in streams) {
      final s = stream as Map<String, dynamic>;
      final codecType = s['codec_type']?.toString() ?? '';
      final codec = s['codec_name']?.toString() ?? '';
      final tags = s['tags'] as Map? ?? {};
      final language = tags['language']?.toString() ?? '';
      final title = tags['title']?.toString() ?? '';
      var name = title.isNotEmpty
          ? title
          : language.isNotEmpty
              ? language.toUpperCase()
              : '';

      if (codecType == 'audio') {
        if (name.isEmpty) name = 'Audio ${audioFallback + 1}';
        tracks.add(
          TrackInfo(
            index: audioFallback + 1,
            type: 'audio',
            name: name,
            codec: codec,
          ),
        );
        audioFallback++;
      } else if (codecType == 'subtitle') {
        if (name.isEmpty) name = 'Subtitle ${subFallback + 1}';
        tracks.add(
          TrackInfo(
            index: subFallback + 1,
            type: 'subtitle',
            name: name,
            codec: codec,
          ),
        );
        subFallback++;
      }
    }

    return tracks;
  }

  static List<TrackInfo> _parseFfmpegOutput(String output) {
    final tracks = <TrackInfo>[];
    final lines = const LineSplitter().convert(output);
    final re = RegExp(
      r'Stream #\d+:(\d+)(?:\[[^\]]+\])?(?:\(([^)]+)\))?: (Audio|Subtitle):\s*([^,]+)',
      caseSensitive: false,
    );
    var audioFallback = 0;
    var subFallback = 0;

    for (final line in lines) {
      final match = re.firstMatch(line);
      if (match == null) continue;

      final language = (match.group(2) ?? '').trim();
      final typeRaw = (match.group(3) ?? '').toLowerCase();
      final codec = (match.group(4) ?? '').trim().toLowerCase();
      final isAudio = typeRaw == 'audio';
      final fallback = isAudio ? audioFallback : subFallback;

      final name = language.isNotEmpty
          ? language.toUpperCase()
          : isAudio
              ? 'Audio ${audioFallback + 1}'
              : 'Subtitle ${subFallback + 1}';

      tracks.add(
        TrackInfo(
          index: fallback + 1,
          type: isAudio ? 'audio' : 'subtitle',
          name: name,
          codec: codec,
        ),
      );

      if (isAudio) {
        audioFallback++;
      } else {
        subFallback++;
      }
    }

    return tracks;
  }

  static Future<List<TrackInfo>> getTracksForUrl(String url) async {
    try {
      final ffprobe = _getFfprobePath();
      debugPrint('[TrackInfoService] using ffprobe: $ffprobe');

      final result = await Process.run(
        ffprobe,
        [
          '-v',
          'quiet',
          '-print_format',
          'json',
          '-show_streams',
          '-user_agent',
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64)',
          url,
        ],
        runInShell: false,
      ).timeout(const Duration(seconds: 15));

      if (result.exitCode != 0) {
        debugPrint('[TrackInfoService] ffprobe error: ${result.stderr}');
      } else {
        final json = jsonDecode(result.stdout as String) as Map<String, dynamic>;
        final tracks = _parseFfprobeTracks(json);
        if (tracks.isNotEmpty) {
          debugPrint(
            '[TrackInfoService] found '
            '${tracks.where((t) => t.type == "audio").length} audio, '
            '${tracks.where((t) => t.type == "subtitle").length} subtitle tracks (ffprobe)',
          );
          return tracks;
        }
      }

      final ffmpeg = _getFfmpegPath();
      debugPrint('[TrackInfoService] fallback using ffmpeg: $ffmpeg');
      final ffmpegResult = await Process.run(
        ffmpeg,
        [
          '-hide_banner',
          '-user_agent',
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64)',
          '-i',
          url,
        ],
        runInShell: false,
      ).timeout(const Duration(seconds: 15));

      final tracks = _parseFfmpegOutput(ffmpegResult.stderr as String);
      debugPrint(
        '[TrackInfoService] found '
        '${tracks.where((t) => t.type == "audio").length} audio, '
        '${tracks.where((t) => t.type == "subtitle").length} subtitle tracks (ffmpeg fallback)',
      );
      return tracks;
    } catch (e) {
      debugPrint('[TrackInfoService] error: $e');
      return [];
    }
  }
}
