class Profile {
  final String id;
  final String name;
  final String serverUrl;
  final String username;
  final String password;
  final String? expiryDate;
  final String? avatarLetter;
  final String? lastRefreshAt;

  Profile({
    required this.id,
    required this.name,
    required this.serverUrl,
    required this.username,
    required this.password,
    this.expiryDate,
    this.avatarLetter,
    this.lastRefreshAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'serverUrl': serverUrl,
        'username': username,
        'password': password,
        'expiryDate': expiryDate ?? '',
        'avatarLetter': avatarLetter ?? name[0].toUpperCase(),
        'lastRefreshAt': lastRefreshAt ?? '',
      };

  factory Profile.fromJson(Map<String, dynamic> json) => Profile(
        id: json['id'],
        name: json['name'],
        serverUrl: json['serverUrl'],
        username: json['username'],
        password: json['password'],
        expiryDate: json['expiryDate'],
        avatarLetter: json['avatarLetter'],
        lastRefreshAt: json['lastRefreshAt'],
      );

  Profile copyWith({
    String? id,
    String? name,
    String? serverUrl,
    String? username,
    String? password,
    String? expiryDate,
    String? avatarLetter,
    String? lastRefreshAt,
  }) {
    return Profile(
      id: id ?? this.id,
      name: name ?? this.name,
      serverUrl: serverUrl ?? this.serverUrl,
      username: username ?? this.username,
      password: password ?? this.password,
      expiryDate: expiryDate ?? this.expiryDate,
      avatarLetter: avatarLetter ?? this.avatarLetter,
      lastRefreshAt: lastRefreshAt ?? this.lastRefreshAt,
    );
  }
}
