class MovieWatchProgress {
  final int streamId;
  final String title;
  final String poster;
  final int positionMs;
  final int durationMs;

  const MovieWatchProgress({
    required this.streamId,
    required this.title,
    required this.poster,
    required this.positionMs,
    required this.durationMs,
  });

  factory MovieWatchProgress.fromJson(Map<String, dynamic> json) {
    return MovieWatchProgress(
      streamId: int.tryParse(json['streamId'].toString()) ?? 0,
      title: json['title']?.toString() ?? '',
      poster: json['poster']?.toString() ?? '',
      positionMs: int.tryParse(json['positionMs'].toString()) ?? 0,
      durationMs: int.tryParse(json['durationMs'].toString()) ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'streamId': streamId,
      'title': title,
      'poster': poster,
      'positionMs': positionMs,
      'durationMs': durationMs,
    };
  }

  double get progress {
    if (durationMs <= 0) return 0;
    return (positionMs / durationMs).clamp(0, 1);
  }
}
