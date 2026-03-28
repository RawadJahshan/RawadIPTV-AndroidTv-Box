import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../data/datasources/remote/xtream_api.dart';
import '../../../data/models/movie_category.dart';
import 'series_list_screen.dart';

class SeriesCategoriesScreen extends StatefulWidget {
  final XtreamApi xtreamApi;

  const SeriesCategoriesScreen({super.key, required this.xtreamApi});

  @override
  State<SeriesCategoriesScreen> createState() => _SeriesCategoriesScreenState();
}

class _SeriesCategoriesScreenState extends State<SeriesCategoriesScreen> {
  late Future<List<MovieCategory>> _futureCategories;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  static const List<MovieCategory> _fixedCategories = <MovieCategory>[
    MovieCategory(id: -1, name: 'All'),
    MovieCategory(id: -2, name: 'Continue Watching'),
    MovieCategory(id: -3, name: 'My Favorites'),
  ];

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    _futureCategories = _fetchCategories();
  }

  Future<List<MovieCategory>> _fetchCategories() async {
    final raw = await widget.xtreamApi.getSeriesCategories();
    return raw.map((json) => MovieCategory.fromJson(json)).toList();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<MovieCategory> _visibleCategories(List<MovieCategory> apiCategories) {
    if (_searchQuery.isEmpty) {
      return <MovieCategory>[..._fixedCategories, ...apiCategories];
    }

    final lowerQuery = _searchQuery.toLowerCase();
    final filteredApiCategories = apiCategories
        .where((category) => category.name.toLowerCase().contains(lowerQuery))
        .toList();

    return <MovieCategory>[
      ..._fixedCategories,
      ...filteredApiCategories,
    ];
  }

  double _getFontSize(BuildContext context, double base) {
    final width = MediaQuery.of(context).size.width;
    if (width >= 900) return base;
    return base * 0.85;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: true,
      child: Scaffold(
        backgroundColor: const Color(0xFF1E1E1E),
        appBar: AppBar(
          toolbarHeight: 46,
          title: const Text('Series', style: TextStyle(fontSize: 15)),
          backgroundColor: const Color(0xFF0F0F1A),
          elevation: 0,
        ),
        body: FutureBuilder<List<MovieCategory>>(
        future: _futureCategories,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }

          final apiCategories = snapshot.data ?? <MovieCategory>[];
          final visibleCategories = _visibleCategories(apiCategories);

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 6,
                ),
                child: TextField(
                  controller: _searchController,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Search categories...',
                    hintStyle: const TextStyle(
                      color: Colors.white38,
                      fontSize: 13,
                    ),
                    prefixIcon: const Icon(
                      Icons.search,
                      color: Colors.white38,
                      size: 18,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, color: Colors.white38),
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _searchQuery = '');
                            },
                          )
                        : null,
                    filled: true,
                    fillColor: const Color(0xFF0F0F1A),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: Colors.blue, width: 2),
                    ),
                  ),
                  onChanged: (value) => setState(() => _searchQuery = value),
                ),
              ),
              Expanded(
                child: OrientationBuilder(
                  builder: (context, orientation) {
                    final isLandscape = orientation == Orientation.landscape;
                    if (isLandscape) {
                      return GridView.builder(
                        physics: const BouncingScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          mainAxisSpacing: 8,
                          crossAxisSpacing: 8,
                          mainAxisExtent: 56,
                        ),
                        itemCount: visibleCategories.length,
                        itemBuilder: (context, index) {
                          final category = visibleCategories[index];
                          return _buildCategoryTile(category);
                        },
                      );
                    }
                    return ListView.separated(
                      physics: const BouncingScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
                      separatorBuilder: (_, __) => const Divider(color: Colors.white12),
                      itemCount: visibleCategories.length,
                      itemBuilder: (context, index) {
                        final category = visibleCategories[index];
                        return _buildCategoryTile(category);
                      },
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
      ),
    );
  }

  Widget _buildCategoryTile(MovieCategory category) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      minTileHeight: 56,
      title: Text(
        category.name,
        style: TextStyle(color: Colors.white, fontSize: _getFontSize(context, 16)),
      ),
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => SeriesListScreen(
              xtreamApi: widget.xtreamApi,
              categoryId: category.id,
              categoryName: category.name,
            ),
          ),
        );
      },
    );
  }
}
