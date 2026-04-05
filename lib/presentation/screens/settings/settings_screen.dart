import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_constants.dart';
import '../../../data/services/domain_manager.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _isClearingCache = false;
  bool _isTestingServers = false;
  List<DomainResult>? _testResults;

  // ─── Cache clear ───────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

  Future<void> _clearCache() async {
    if (_isClearingCache) return;
    setState(() => _isClearingCache = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      const storage = FlutterSecureStorage();

      final username = await storage.read(key: 'username');
      final password = await storage.read(key: 'password');
      await prefs.clear();

      if (username != null) await storage.write(key: 'username', value: username);
      if (password != null) await storage.write(key: 'password', value: password);
      await prefs.setString('server_url', AppConstants.serverUrl);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Cache cleared successfully'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to clear cache: $error')),
      );
    } finally {
      if (mounted) setState(() => _isClearingCache = false);
    }
  }

  Future<void> _onClearCacheTapped() async {
    if (_isClearingCache) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Clear Cache'),
        content: const Text(
          'This will clear your watch history, '
          'favorites, and all cached data. '
          'Your login will be kept. '
          'Are you sure?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (confirm == true) await _clearCache();
  }

  // ─── Server speed test ─────────────────────────────────────────────────────

  Future<void> _testServers() async {
    if (_isTestingServers) return;
    setState(() {
      _isTestingServers = true;
      _testResults = null;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final username = prefs.getString('username') ?? '';
      final password = prefs.getString('password') ?? '';

      if (username.isEmpty || password.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Login first to test servers'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }

      final results = await DomainManager.instance.testAllDomains(
        username: username,
        password: password,
      );

      if (!mounted) return;
      setState(() => _testResults = results);

      // Auto-switch to the fastest working server.
      final working = results.where((r) => r.isReachable).toList()
        ..sort((a, b) => a.responseTimeMs!.compareTo(b.responseTimeMs!));
      if (working.isNotEmpty) {
        await DomainManager.instance.setActiveDomain(working.first.domain);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Switched to fastest server: ${working.first.displayName} '
                '(${working.first.responseTimeMs}ms)',
              ),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('All servers are unreachable'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } finally {
      if (mounted) setState(() => _isTestingServers = false);
    }
  }

  Future<void> _selectDomain(String domain) async {
    await DomainManager.instance.setActiveDomain(domain);
    if (mounted) {
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Server changed to ${Uri.parse(domain).host}'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  // ─── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        title: const Text('Settings'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // ── Server Selection ───────────────────────────────────────────────
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.dns_outlined, size: 20),
                      const SizedBox(width: 8),
                      const Text(
                        'Server Selection',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Spacer(),
                      TextButton.icon(
                        onPressed: _isTestingServers ? null : _testServers,
                        icon: _isTestingServers
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.speed, size: 16),
                        label: Text(
                          _isTestingServers ? 'Testing…' : 'Test All',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Active: ${Uri.parse(DomainManager.instance.activeDomain).host}',
                    style: TextStyle(
                      color: Colors.green.shade300,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ..._buildDomainRows(),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // ── Clear Cache ────────────────────────────────────────────────────
          Card(
            child: ListTile(
              title: const Text('Clear Cache'),
              subtitle: const Text(
                'Clears watch history, favorites, and cached data. Keeps login.',
              ),
              trailing: _isClearingCache
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.cleaning_services_outlined),
              onTap: _isClearingCache ? null : _onClearCacheTapped,
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildDomainRows() {
    final activeDomain = DomainManager.instance.activeDomain;

    // Build a map of test results for quick lookup.
    final resultMap = <String, DomainResult>{};
    if (_testResults != null) {
      for (final r in _testResults!) {
        resultMap[r.domain] = r;
      }
    }

    return DomainManager.domains.map((domain) {
      final isActive = domain == activeDomain;
      final result = resultMap[domain];
      final host = Uri.parse(domain).host;

      return InkWell(
        onTap: _isTestingServers ? null : () => _selectDomain(domain),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isActive ? Colors.blue : Colors.white12,
              width: isActive ? 1.5 : 1,
            ),
            color: isActive ? Colors.blue.withValues(alpha: 0.08) : null,
          ),
          child: Row(
            children: [
              Icon(
                isActive ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                size: 16,
                color: isActive ? Colors.blue : Colors.white38,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      host,
                      style: TextStyle(
                        fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                        fontSize: 13,
                      ),
                    ),
                    if (_testResults != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        result?.statusLabel ?? 'Not tested',
                        style: TextStyle(
                          fontSize: 11,
                          color: _statusColor(result),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (result != null && result.isReachable)
                _SpeedBadge(ms: result.responseTimeMs!),
            ],
          ),
        ),
      );
    }).toList();
  }

  Color _statusColor(DomainResult? result) {
    if (result == null) return Colors.white38;
    if (result.isReachable) return Colors.green;
    return Colors.red.shade300;
  }
}

class _SpeedBadge extends StatelessWidget {
  final int ms;
  const _SpeedBadge({required this.ms});

  @override
  Widget build(BuildContext context) {
    final color = ms < 300
        ? Colors.green
        : ms < 700
            ? Colors.orange
            : Colors.red;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        '${ms}ms',
        style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600),
      ),
    );
  }
}
