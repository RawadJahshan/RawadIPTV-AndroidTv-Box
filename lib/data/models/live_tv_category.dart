class LiveTvCategory {
  final int id;
  final String name;

  LiveTvCategory({
    required this.id,
    required this.name,
  });

  factory LiveTvCategory.fromJson(Map<String, dynamic> json) {
    return LiveTvCategory(
      id: int.parse(json['category_id'].toString()),
      name: json['category_name'].toString(),
    );
  }
}