import 'package:flutter/material.dart';

import '../../../data/datasources/remote/xtream_api.dart';
import '../../../data/models/profile.dart';
import '../../../data/services/playlist_sync_service.dart';
import '../../../data/services/profile_service.dart';
import '../home/home_dashboard.dart';

enum PlaylistImportMode { initialAdd, refresh }

class PlaylistImportScreen extends StatefulWidget {
  final XtreamApi xtreamApi;
  final Profile profile;
  final PlaylistImportMode mode;

  const PlaylistImportScreen({
    super.key,
    required this.xtreamApi,
    required this.profile,
    required this.mode,
  });

  @override
  State<PlaylistImportScreen> createState() => _PlaylistImportScreenState();
}

class _PlaylistImportScreenState extends State<PlaylistImportScreen> {
  PlaylistSyncProgress _progress = const PlaylistSyncProgress(
    title: 'Adding Playlist Content',
    status: 'Preparing...',
    step: 0,
    totalSteps: 6,
  );
  String? _error;

  @override
  void initState() {
    super.initState();
    _runImport();
  }

  Future<void> _runImport() async {
    setState(() => _error = null);
    try {
      await PlaylistSyncService.syncXtreamCatalog(
        xtreamApi: widget.xtreamApi,
        profileId: widget.profile.id,
        onProgress: (progress) {
          if (!mounted) return;
          setState(() => _progress = progress);
        },
      );

      final refreshedProfile = widget.profile.copyWith(
        lastRefreshAt: DateTime.now().toIso8601String(),
      );
      await ProfileService.saveProfile(refreshedProfile);
      await ProfileService.setActiveProfile(refreshedProfile.id);

      if (!mounted) return;
      if (widget.mode == PlaylistImportMode.initialAdd) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => HomeDashboard(
              username: refreshedProfile.username,
              expiryDate: refreshedProfile.expiryDate ?? 'Unknown',
              xtreamApi: widget.xtreamApi,
              profileId: refreshedProfile.id,
            ),
          ),
        );
      } else {
        Navigator.pop(context, true);
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.mode == PlaylistImportMode.refresh
        ? 'Refresh Playlist'
        : _progress.title;

    return Scaffold(
      backgroundColor: const Color(0xFF111827),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 540),
          child: Card(
            color: const Color(0xFF1F2937),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _progress.status,
                    style: const TextStyle(color: Colors.white70, fontSize: 16),
                  ),
                  const SizedBox(height: 16),
                  LinearProgressIndicator(
                    value: _progress.progress.clamp(0, 1),
                    minHeight: 10,
                    backgroundColor: Colors.white12,
                    valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF00C6FF)),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Step ${_progress.step}/${_progress.totalSteps}',
                    style: const TextStyle(color: Colors.white60),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 20),
                    Text(
                      _error!,
                      style: const TextStyle(color: Colors.redAccent),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: const Text('Cancel'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton(
                            onPressed: _runImport,
                            child: const Text('Retry'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
