class MovieItem {
  final int streamId;
  final String title;
  final String posterUrl;
  final String description;
  final String genre;
  final String rating;
  final String year;
  final String containerExtension;

  const MovieItem({
    required this.streamId,
    required this.title,
    required this.posterUrl,
    required this.description,
    required this.genre,
    required this.rating,
    required this.year,
    required this.containerExtension,
  });

  factory MovieItem.fromJson(Map<String, dynamic> json) {
    return MovieItem(
      streamId: int.tryParse(json['stream_id'].toString()) ?? 0,
      title: json['name']?.toString() ?? 'Unknown',
      posterUrl: json['stream_icon']?.toString() ?? '',
      description: json['plot']?.toString() ?? json['description']?.toString() ?? '',
      genre: json['genre']?.toString() ?? '',
      rating: json['rating']?.toString() ?? '',
      year: json['year']?.toString() ?? '',
      containerExtension: json['container_extension']?.toString() ?? 'mp4',
    );
  }

  String streamUrl(String serverUrl, String username, String password) {
    return '$serverUrl/movie/$username/$password/$streamId.$containerExtension';
  }
}
