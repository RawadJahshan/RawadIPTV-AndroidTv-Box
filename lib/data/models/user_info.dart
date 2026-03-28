class UserInfo {
  final String serverUrl;
  final String username;
  final String password;
  final String status;
  final String expDate;
  final int maxConnections;
  final int activeConnections;

  UserInfo({
    required this.serverUrl,
    required this.username,
    required this.password,
    required this.status,
    required this.expDate,
    required this.maxConnections,
    required this.activeConnections,
  });

  factory UserInfo.fromJson(
    Map<String, dynamic> json,
    String serverUrl,
    String username,
    String password,
  ) {
    final userInfo = json['user_info'] ?? {};
    return UserInfo(
      serverUrl: serverUrl,
      username: username,
      password: password,
      status: userInfo['status']?.toString() ?? 'unknown',
      expDate: userInfo['exp_date']?.toString() ?? 'unknown',
      maxConnections: int.tryParse(
            userInfo['max_connections']?.toString() ?? '0',
          ) ??
          0,
      activeConnections: int.tryParse(
            userInfo['active_cons']?.toString() ?? '0',
          ) ??
          0,
    );
  }

  // Save to local storage
  Map<String, dynamic> toJson() => {
        'serverUrl': serverUrl,
        'username': username,
        'password': password,
        'status': status,
        'expDate': expDate,
        'maxConnections': maxConnections,
        'activeConnections': activeConnections,
      };
}