import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../live_tv/live_tv_categories_screen.dart';
import '../movies/movies_screen.dart';
import '../series/series_categories_screen.dart';
import '../../../data/datasources/remote/xtream_api.dart';
import '../profiles/profiles_screen.dart';
import '../settings/settings_screen.dart';

class HomeDashboard extends StatelessWidget {
  final String username;
  final String expiryDate;
  final XtreamApi xtreamApi;

  const HomeDashboard({
    super.key,
    required this.username,
    required this.expiryDate,
    required this.xtreamApi,
  });

  Widget _buildMenuCard(
    BuildContext context, {
    required String label,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    final cardHeight = MediaQuery.of(context).size.height * 0.35;
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            height: cardHeight,
            decoration: BoxDecoration(
              color: Colors.white10,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white24),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 48, color: Colors.white),
                const SizedBox(height: 12),
                Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF2C2C2C),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 24),
          child: Column(
            children: [
              Row(
                children: [
                  ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const ProfilesScreen(),
                        ),
                      );
                    },
                    icon: const Icon(Icons.switch_account, size: 18),
                    label: const Text('Switch Profile'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1A1A2E),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    username,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 30,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  Row(
                    children: [
                      const _DateTimeWidget(),
                      IconButton(
                        icon: const Icon(Icons.settings, color: Colors.white),
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const SettingsScreen(),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Expanded(
                child: Row(
                  children: [
                    _buildMenuCard(
                      context,
                      label: 'LIVE TV',
                      icon: Icons.live_tv,
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => LiveTvCategoriesScreen(xtreamApi: xtreamApi),
                          ),
                        );
                      },
                    ),
                    _buildMenuCard(
                      context,
                      label: 'MOVIES',
                      icon: Icons.movie,
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => MoviesScreen(xtreamApi: xtreamApi),
                          ),
                        );
                      },
                    ),
                    _buildMenuCard(
                      context,
                      label: 'SERIES',
                      icon: Icons.tv,
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => SeriesCategoriesScreen(xtreamApi: xtreamApi),
                          ),
                        );
                      },
                    ),
                    _buildMenuCard(
                      context,
                      label: 'FAVORITES',
                      icon: Icons.favorite,
                      onTap: () => Navigator.pushNamed(context, '/favorites', arguments: xtreamApi),
                    ),
                    _buildMenuCard(
                      context,
                      label: 'SETTINGS',
                      icon: Icons.settings,
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const SettingsScreen(),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.bottomRight,
                child: Text(
                  'Expiration: $expiryDate',
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                    height: 1.5,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DateTimeWidget extends StatefulWidget {
  const _DateTimeWidget();

  @override
  State<_DateTimeWidget> createState() => _DateTimeWidgetState();
}

class _DateTimeWidgetState extends State<_DateTimeWidget> {
  late String _time;
  late String _date;
  late final Timer _timer;

  @override
  void initState() {
    super.initState();
    _updateDateTime();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _updateDateTime());
  }

  void _updateDateTime() {
    final now = DateTime.now();
    setState(() {
      _time = "${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}";
      _date = DateFormat('MMM d, yyyy').format(now);
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          _time,
          style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
        ),
        Text(
          _date,
          style: const TextStyle(color: Colors.white54, fontSize: 14),
        ),
      ],
    );
  }
}
