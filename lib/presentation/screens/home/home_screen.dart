import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_colors.dart';
import '../../../data/models/user_info.dart';
import '../../screens/settings/settings_screen.dart';

class HomeScreen extends StatefulWidget {
  final UserInfo userInfo;

  const HomeScreen({super.key, required this.userInfo});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late Timer _timer;
  String _currentDate = '';
  String _currentTime = '';

  @override
  void initState() {
    super.initState();
    _updateDateTime();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _updateDateTime());
  }

  void _updateDateTime() {
    final now = DateTime.now();
    setState(() {
      _currentDate = DateFormat('EEE, MMM d, yyyy').format(now);
      _currentTime = DateFormat('HH:mm:ss').format(now);
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  void _openSettings() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const SettingsScreen()),
    );
  }

  String formatUnixTimestamp(String unixTimestamp) {
    try {
      final timestamp = int.tryParse(unixTimestamp) ?? 0;
      final date = DateTime.fromMillisecondsSinceEpoch(timestamp * 1000);
      return DateFormat('yyyy-MM-dd').format(date);
    } catch (_) {
      return unixTimestamp;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        elevation: 2,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_currentDate, style: const TextStyle(fontSize: 14)),
            Text(
              _currentTime,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: _openSettings,
            tooltip: 'Settings',
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: ListView(
          physics: const BouncingScrollPhysics(),
          children: [
            const Icon(Icons.check_circle, color: Colors.green, size: 80),
            const SizedBox(height: 24),
            const Text(
              'Login Successful!',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 28,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Text(
              'Welcome, ${widget.userInfo.username}',
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 18),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Status: ${widget.userInfo.status}',
              style: const TextStyle(color: Colors.green, fontSize: 16),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Expires: ${formatUnixTimestamp(widget.userInfo.expDate)}',
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 16),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            const Divider(color: Colors.white54),
            const SizedBox(height: 16),
            const Center(
              child: Text(
                'Live TV Channel List will appear here',
                style: TextStyle(color: AppColors.textPrimary, fontSize: 18),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
