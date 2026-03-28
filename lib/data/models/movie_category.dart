class MovieCategory {
  final int id;
  final String name;

  const MovieCategory({
    required this.id,
    required this.name,
  });

  factory MovieCategory.fromJson(Map<String, dynamic> json) {
    return MovieCategory(
      id: int.tryParse(json['category_id'].toString()) ?? 0,
      name: json['category_name']?.toString() ?? 'Unknown',
    );
  }
}
