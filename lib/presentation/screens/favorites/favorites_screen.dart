import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../data/datasources/remote/xtream_api.dart';
import '../../../data/models/channel.dart';
import '../../../utils/favorites_manager.dart';
import '../live_tv/channels_detail_screen.dart';
import '../../../data/models/live_tv_category.dart';

class FavoritesScreen extends StatefulWidget {
  final XtreamApi xtreamApi;

  const FavoritesScreen({super.key, required this.xtreamApi});

  @override
  State<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends State<FavoritesScreen> {
  List<Channel> _favoriteChannels = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    _loadFavorites();
  }

  Future<void> _loadFavorites() async {
    setState(() => _isLoading = true);

    try {
      final liveIds = await FavoritesManager.getFavoriteLiveIds();
      final rawChannels = await widget.xtreamApi.getLiveStreams();

      final allChannels = rawChannels
          .map((json) => Channel.fromJson(
                Map<String, dynamic>.from(json),
                widget.xtreamApi.serverUrl,
                widget.xtreamApi.username,
                widget.xtreamApi.password,
              ))
          .toList();

      if (mounted) {
        setState(() {
          _favoriteChannels = allChannels.where((c) => liveIds.contains(c.id.toString())).toList();
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('loadFavorites error: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1E1E1E),
      appBar: AppBar(
        title: const Text('Favorites'),
        backgroundColor: const Color(0xFF0F0F1A),
        elevation: 0,
        actions: [
          IconButton(
            onPressed: _loadFavorites,
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _isLoading ? const Center(child: CircularProgressIndicator()) : _buildChannelsList(),
    );
  }

  Widget _buildChannelsList() {
    if (_favoriteChannels.isEmpty) {
      return _buildEmpty('No favorite channels yet', Icons.live_tv);
    }
    return ListView.separated(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.all(12),
      separatorBuilder: (_, index) => const Divider(color: Colors.white12),
      itemCount: _favoriteChannels.length,
      itemBuilder: (context, index) {
        final channel = _favoriteChannels[index];
        return ListTile(
          leading: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A2E),
              borderRadius: BorderRadius.circular(8),
            ),
            child: channel.logoUrl.isNotEmpty
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(
                      channel.logoUrl,
                      cacheWidth: 400,
                      cacheHeight: 450,
                      filterQuality: FilterQuality.low,
                      fit: BoxFit.contain,
                      errorBuilder: (_, error, stackTrace) => const Icon(Icons.tv, color: Colors.white54),
                    ),
                  )
                : const Icon(Icons.tv, color: Colors.white54),
          ),
          title: Text(channel.name, style: const TextStyle(color: Colors.white)),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.favorite, color: Colors.red),
                onPressed: () async {
                  await FavoritesManager.removeFavoriteLive(channel.id.toString());
                  setState(() => _favoriteChannels.remove(channel));
                },
              ),
              const Icon(Icons.arrow_forward_ios, color: Colors.white38, size: 14),
            ],
          ),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ChannelsDetailScreen(
                  xtreamApi: widget.xtreamApi,
                  profileId: '',
                  category: LiveTvCategory(id: channel.id, name: channel.name),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildEmpty(String message, IconData icon) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: Colors.white24, size: 64),
          const SizedBox(height: 16),
          Text(message, style: const TextStyle(color: Colors.white38, fontSize: 16)),
        ],
      ),
    );
  }
}
