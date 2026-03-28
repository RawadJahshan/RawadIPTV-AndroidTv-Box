class Profile {
  final String id;
  final String name;
  final String serverUrl;
  final String username;
  final String password;
  final String? expiryDate;
  final String? avatarLetter;

  Profile({
    required this.id,
    required this.name,
    required this.serverUrl,
    required this.username,
    required this.password,
    this.expiryDate,
    this.avatarLetter,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'serverUrl': serverUrl,
        'username': username,
        'password': password,
        'expiryDate': expiryDate ?? '',
        'avatarLetter': avatarLetter ?? name[0].toUpperCase(),
      };

  factory Profile.fromJson(Map<String, dynamic> json) => Profile(
        id: json['id'],
        name: json['name'],
        serverUrl: json['serverUrl'],
        username: json['username'],
        password: json['password'],
        expiryDate: json['expiryDate'],
        avatarLetter: json['avatarLetter'],
      );
}