import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'data/datasources/remote/xtream_api.dart';
import 'data/services/domain_manager.dart';
import 'data/services/profile_service.dart';
import 'presentation/screens/profiles/profiles_screen.dart';
import 'presentation/screens/favorites/favorites_screen.dart';
import 'presentation/screens/series/series_categories_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  MediaKit.ensureInitialized();
  // Restore the last-known-working domain before any API calls are made.
  await DomainManager.instance.init();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'IPTV App',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF1E1E1E),
        focusColor: Colors.blueAccent.withValues(alpha: 0.35),
        listTileTheme: const ListTileThemeData(
          selectedTileColor: Color(0x332196F3),
        ),
      ),
      builder: (context, child) {
        return Shortcuts(
          shortcuts: const <ShortcutActivator, Intent>{
            SingleActivator(LogicalKeyboardKey.select): ActivateIntent(),
            SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
            SingleActivator(LogicalKeyboardKey.numpadEnter): ActivateIntent(),
            SingleActivator(LogicalKeyboardKey.goBack): DismissIntent(),
            SingleActivator(LogicalKeyboardKey.escape): DismissIntent(),
          },
          child: Actions(
            actions: <Type, Action<Intent>>{
              DismissIntent: CallbackAction<DismissIntent>(
                onInvoke: (_) {
                  final navigator = Navigator.maybeOf(context);
                  if (navigator != null && navigator.canPop()) {
                    navigator.pop();
                  }
                  return null;
                },
              ),
            },
            child: FocusTraversalGroup(
              policy: ReadingOrderTraversalPolicy(),
              child: Focus(
                autofocus: true,
                child: child ?? const SizedBox.shrink(),
              ),
            ),
          ),
        );
      },
      home: const ProfilesScreen(),
      onGenerateRoute: (settings) {
        if (settings.name == '/favorites') {
          final xtreamApi = settings.arguments as XtreamApi;
          return MaterialPageRoute(
            builder: (_) => FavoritesScreen(xtreamApi: xtreamApi),
          );
        }
        if (settings.name == '/series') {
          final xtreamApi = settings.arguments as XtreamApi;
          return MaterialPageRoute(
            builder: (_) => FutureBuilder(
              future: ProfileService.getActiveProfile(),
              builder: (context, snapshot) {
                final profileId = snapshot.data?.id ?? '';
                return SeriesCategoriesScreen(
                  xtreamApi: xtreamApi,
                  profileId: profileId,
                );
              },
            ),
          );
        }
        return null;
      },
    );
  }
}
