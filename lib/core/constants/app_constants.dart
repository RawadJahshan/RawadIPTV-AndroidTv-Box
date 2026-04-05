import '../../data/services/domain_manager.dart';

class AppConstants {
  // Active server URL — always delegates to DomainManager so the whole app
  // automatically picks up domain switches without touching every call-site.
  static String get serverUrl => DomainManager.instance.activeDomain;
  static String get apiBase => '${DomainManager.instance.activeDomain}/player_api.php';
}
