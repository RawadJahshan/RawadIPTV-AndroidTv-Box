class Channel {
  final int id;
  final String name;
  final String streamUrl;
  final String streamUrlM3u8;
  final String logoUrl;
  final String epgChannelId;
  final String? resolution;

  Channel({
    required this.id,
    required this.name,
    required this.streamUrl,
    required this.streamUrlM3u8,
    required this.logoUrl,
    required this.epgChannelId,
    this.resolution,
  });

  factory Channel.fromJson(
    Map<String, dynamic> json,
    String serverUrl,
    String username,
    String password,
  ) {
    final streamId = json['stream_id'].toString();
    return Channel(
      id: int.parse(streamId),
      name: json['name'].toString(),
      streamUrl: '$serverUrl/live/$username/$password/$streamId.ts',
      streamUrlM3u8: '$serverUrl/live/$username/$password/$streamId.m3u8',
      logoUrl: json['stream_icon']?.toString() ?? '',
      epgChannelId: json['epg_channel_id']?.toString() ?? '',
      resolution: json['container_extension']?.toString(),
    );
  }
}