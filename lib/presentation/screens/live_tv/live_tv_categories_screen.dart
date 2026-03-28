import 'package:flutter/material.dart';
import '../../../data/datasources/remote/xtream_api.dart';
import '../../../data/models/live_tv_category.dart';
import 'channels_detail_screen.dart';

class LiveTvCategoriesScreen extends StatefulWidget {
  final XtreamApi xtreamApi;
  const LiveTvCategoriesScreen({super.key, required this.xtreamApi});

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
    _futureCategories = _fetchCategories();
  }

  Future<List<LiveTvCategory>> _fetchCategories() async {
    final raw = await widget.xtreamApi.getLiveCategories();
    return raw
        .map((json) => LiveTvCategory.fromJson(json))
        .toList();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1E1E1E),
      appBar: AppBar(
        title: const Text('Live TV'),
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
                padding: const EdgeInsets.all(12),
                child: TextField(
                  controller: _searchController,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'Search categories...',
                    hintStyle: const TextStyle(color: Colors.white38),
                    prefixIcon: const Icon(
                      Icons.search,
                      color: Colors.white38,
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
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
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
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 13,
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
                    : ListView.separated(
                        padding:
                            const EdgeInsets.symmetric(horizontal: 12),
                        separatorBuilder: (_, __) =>
                                                        const Divider(color: Colors.white12),
                        itemCount: filtered.length,
                        itemBuilder: (context, index) {
                          final category = filtered[index];
                          return ListTile(
                            leading: const Icon(
                              Icons.live_tv,
                              color: Color(0xFF00c6ff),
                            ),
                            title: Text(
                              category.name,
                              style: const TextStyle(color: Colors.white),
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
                                    category: category,
                                  ),
                                ),
                              );
                            },
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}