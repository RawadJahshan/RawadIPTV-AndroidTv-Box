import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../data/datasources/remote/xtream_api.dart';
import '../../../data/services/catalog_cache_service.dart';
import '../../../data/models/live_tv_category.dart';
import 'channels_detail_screen.dart';
import '../../widgets/tv_keyboard_text_field.dart';

class LiveTvCategoriesScreen extends StatefulWidget {
  final XtreamApi xtreamApi;
  final String profileId;
  const LiveTvCategoriesScreen({
    super.key,
    required this.xtreamApi,
    required this.profileId,
  });

  @override
  State<LiveTvCategoriesScreen> createState() =>
      _LiveTvCategoriesScreenState();
}

class _LiveTvCategoriesScreenState
    extends State<LiveTvCategoriesScreen> {
  late Future<List<LiveTvCategory>> _futureCategories;
  String _searchQuery = '';
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    _futureCategories = _fetchCategories();
  }

  Future<List<LiveTvCategory>> _fetchCategories() async {
    var raw = await CatalogCacheService.getLiveCategories(widget.profileId);
    if (raw.isEmpty) {
      raw = await widget.xtreamApi.getLiveCategories();
      await CatalogCacheService.saveLiveCategories(widget.profileId, raw);
    }
    return raw
        .map((json) => LiveTvCategory.fromJson(json))
        .toList();
  }

  @override
  void dispose() {
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    double getFontSize(double base) {
      final width = MediaQuery.of(context).size.width;
      if (width >= 900) return base;
      return base * 0.85;
    }

    return PopScope(
      canPop: true,
      child: Scaffold(
        backgroundColor: const Color(0xFF1E1E1E),
        appBar: AppBar(
          toolbarHeight: 46,
          title: const Text('Live TV', style: TextStyle(fontSize: 15)),
          backgroundColor: const Color(0xFF0F0F1A),
          elevation: 0,
        ),
        body: FutureBuilder<List<LiveTvCategory>>(
        future: _futureCategories,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(child: Text('No categories found'));
          }

          final allCategories = snapshot.data!;
          final filtered = _searchQuery.isEmpty
              ? allCategories
              : allCategories
                  .where((c) => c.name
                      .toLowerCase()
                      .contains(_searchQuery.toLowerCase()))
                  .toList();

          return Column(
            children: [
              // Search bar
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 6,
                ),
                child: TvKeyboardTextField(
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
                            icon: const Icon(
                              Icons.clear,
                              color: Colors.white38,
                            ),
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
                      borderSide: const BorderSide(
                        color: Colors.blue,
                        width: 2,
                      ),
                    ),
                  ),
                  onChanged: (value) =>
                      setState(() => _searchQuery = value),
                ),
              ),

              // Count
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 4,
                ),
                child: Row(
                  children: [
                    Text(
                      '${filtered.length} Categories',
                      style: TextStyle(
                        color: Colors.white54,
                        fontSize: getFontSize(13),
                      ),
                    ),
                  ],
                ),
              ),

              // Categories list
              Expanded(
                child: filtered.isEmpty
                    ? const Center(
                        child: Text(
                          'No categories found',
                          style: TextStyle(color: Colors.white38),
                        ),
                      )
                    : OrientationBuilder(
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
                              itemCount: filtered.length,
                              itemBuilder: (context, index) {
                                return _buildCategoryTile(filtered[index], getFontSize);
                              },
                            );
                          }
                          return ListView.separated(
                            physics: const BouncingScrollPhysics(),
                            padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
                            separatorBuilder: (_, __) => const Divider(color: Colors.white12),
                            itemCount: filtered.length,
                            itemBuilder: (context, index) {
                              return _buildCategoryTile(filtered[index], getFontSize);
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

  Widget _buildCategoryTile(LiveTvCategory category, double Function(double) getFontSize) {
    return ListTile(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      tileColor: const Color(0xFF141827),
      focusColor: const Color(0x332296F3),
      hoverColor: const Color(0x332296F3),
      minTileHeight: 56,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      leading: const Icon(
        Icons.live_tv,
        color: Color(0xFF00c6ff),
      ),
      title: Text(
        category.name,
        style: TextStyle(color: Colors.white, fontSize: getFontSize(16)),
      ),
      trailing: const Icon(
        Icons.arrow_forward_ios,
        color: Colors.white38,
        size: 14,
      ),
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ChannelsDetailScreen(
              xtreamApi: widget.xtreamApi,
              profileId: widget.profileId,
              category: category,
            ),
          ),
        );
      },
    );
  }
}
