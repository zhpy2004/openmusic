/// 同步载荷:两端交换的全量元数据快照。
///
/// 这里的行对象是**纯值对象,不是 drift 行** —— 合并算法要能在完全不碰数据库的
/// 情况下单测(母 spec §9),所以序列化层与存储层解耦。
class PlaylistRow {
  const PlaylistRow({
    required this.uuid,
    required this.name,
    required this.createdAt,
    required this.updatedAt,
    required this.deleted,
  });

  final String uuid;
  final String name;
  final int createdAt;
  final int updatedAt;
  final bool deleted;

  Map<String, dynamic> toJson() => {
    'uuid': uuid,
    'name': name,
    'createdAt': createdAt,
    'updatedAt': updatedAt,
    'deleted': deleted,
  };

  factory PlaylistRow.fromJson(Map<String, dynamic> j) => PlaylistRow(
    uuid: j['uuid'] as String,
    name: j['name'] as String,
    createdAt: j['createdAt'] as int,
    updatedAt: j['updatedAt'] as int,
    deleted: j['deleted'] as bool,
  );

  @override
  bool operator ==(Object other) =>
      other is PlaylistRow &&
      other.uuid == uuid &&
      other.name == name &&
      other.createdAt == createdAt &&
      other.updatedAt == updatedAt &&
      other.deleted == deleted;

  @override
  int get hashCode => Object.hash(uuid, name, createdAt, updatedAt, deleted);
}

class PlaylistItemRow {
  const PlaylistItemRow({
    required this.playlistUuid,
    required this.trackFp,
    required this.position,
    required this.updatedAt,
    required this.deleted,
  });

  final String playlistUuid;
  final String trackFp;
  final int position;
  final int updatedAt;
  final bool deleted;

  /// 合并用的复合键。
  String get key => '$playlistUuid\u0000$trackFp';

  Map<String, dynamic> toJson() => {
    'playlistUuid': playlistUuid,
    'trackFp': trackFp,
    'position': position,
    'updatedAt': updatedAt,
    'deleted': deleted,
  };

  factory PlaylistItemRow.fromJson(Map<String, dynamic> j) => PlaylistItemRow(
    playlistUuid: j['playlistUuid'] as String,
    trackFp: j['trackFp'] as String,
    position: j['position'] as int,
    updatedAt: j['updatedAt'] as int,
    deleted: j['deleted'] as bool,
  );

  PlaylistItemRow copyWith({int? position}) => PlaylistItemRow(
    playlistUuid: playlistUuid,
    trackFp: trackFp,
    position: position ?? this.position,
    updatedAt: updatedAt,
    deleted: deleted,
  );

  @override
  bool operator ==(Object other) =>
      other is PlaylistItemRow &&
      other.playlistUuid == playlistUuid &&
      other.trackFp == trackFp &&
      other.position == position &&
      other.updatedAt == updatedAt &&
      other.deleted == deleted;

  @override
  int get hashCode =>
      Object.hash(playlistUuid, trackFp, position, updatedAt, deleted);
}

class FavoriteRow {
  const FavoriteRow({
    required this.trackFp,
    required this.addedAt,
    required this.updatedAt,
    required this.deleted,
  });

  final String trackFp;
  final int addedAt;
  final int updatedAt;
  final bool deleted;

  Map<String, dynamic> toJson() => {
    'trackFp': trackFp,
    'addedAt': addedAt,
    'updatedAt': updatedAt,
    'deleted': deleted,
  };

  factory FavoriteRow.fromJson(Map<String, dynamic> j) => FavoriteRow(
    trackFp: j['trackFp'] as String,
    addedAt: j['addedAt'] as int,
    updatedAt: j['updatedAt'] as int,
    deleted: j['deleted'] as bool,
  );

  @override
  bool operator ==(Object other) =>
      other is FavoriteRow &&
      other.trackFp == trackFp &&
      other.addedAt == addedAt &&
      other.updatedAt == updatedAt &&
      other.deleted == deleted;

  @override
  int get hashCode => Object.hash(trackFp, addedAt, updatedAt, deleted);
}

class OverrideRow {
  const OverrideRow({
    required this.trackFp,
    required this.title,
    required this.artist,
    required this.album,
    required this.updatedAt,
    required this.deleted,
  });

  final String trackFp;
  final String? title;
  final String? artist;
  final String? album;
  final int updatedAt;
  final bool deleted;

  Map<String, dynamic> toJson() => {
    'trackFp': trackFp,
    'title': title,
    'artist': artist,
    'album': album,
    'updatedAt': updatedAt,
    'deleted': deleted,
  };

  factory OverrideRow.fromJson(Map<String, dynamic> j) => OverrideRow(
    trackFp: j['trackFp'] as String,
    title: j['title'] as String?,
    artist: j['artist'] as String?,
    album: j['album'] as String?,
    updatedAt: j['updatedAt'] as int,
    deleted: j['deleted'] as bool,
  );

  @override
  bool operator ==(Object other) =>
      other is OverrideRow &&
      other.trackFp == trackFp &&
      other.title == title &&
      other.artist == artist &&
      other.album == album &&
      other.updatedAt == updatedAt &&
      other.deleted == deleted;

  @override
  int get hashCode =>
      Object.hash(trackFp, title, artist, album, updatedAt, deleted);
}

class PlayEventRow {
  const PlayEventRow({
    required this.trackFp,
    required this.playedAt,
    required this.eventType,
  });

  final String trackFp;
  final int playedAt;
  final String eventType;

  /// 自然键 —— 跨设备去重靠它(本地自增 id 无跨设备意义)。
  String get key => '$trackFp\u0000$playedAt\u0000$eventType';

  Map<String, dynamic> toJson() => {
    'trackFp': trackFp,
    'playedAt': playedAt,
    'eventType': eventType,
  };

  factory PlayEventRow.fromJson(Map<String, dynamic> j) => PlayEventRow(
    trackFp: j['trackFp'] as String,
    playedAt: j['playedAt'] as int,
    eventType: j['eventType'] as String,
  );

  @override
  bool operator ==(Object other) =>
      other is PlayEventRow &&
      other.trackFp == trackFp &&
      other.playedAt == playedAt &&
      other.eventType == eventType;

  @override
  int get hashCode => Object.hash(trackFp, playedAt, eventType);
}

class MetadataSnapshot {
  const MetadataSnapshot({
    required this.deviceId,
    required this.playlists,
    required this.playlistItems,
    required this.favorites,
    required this.overrides,
    required this.playEvents,
  });

  /// 快照来源设备 —— 平局时按它的字典序决胜(见 metadata_merge.dart)。
  final String deviceId;
  final List<PlaylistRow> playlists;
  final List<PlaylistItemRow> playlistItems;
  final List<FavoriteRow> favorites;
  final List<OverrideRow> overrides;
  final List<PlayEventRow> playEvents;

  Map<String, dynamic> toJson() => {
    'deviceId': deviceId,
    'playlists': playlists.map((e) => e.toJson()).toList(),
    'playlistItems': playlistItems.map((e) => e.toJson()).toList(),
    'favorites': favorites.map((e) => e.toJson()).toList(),
    'overrides': overrides.map((e) => e.toJson()).toList(),
    'playEvents': playEvents.map((e) => e.toJson()).toList(),
  };

  /// 字段缺失/类型不对时**直接抛**,由调用方整轮失败 —— 半懂的数据比不同步更危险。
  factory MetadataSnapshot.fromJson(Map<String, dynamic> j) => MetadataSnapshot(
    deviceId: j['deviceId'] as String,
    playlists: (j['playlists'] as List)
        .map((e) => PlaylistRow.fromJson(e as Map<String, dynamic>))
        .toList(),
    playlistItems: (j['playlistItems'] as List)
        .map((e) => PlaylistItemRow.fromJson(e as Map<String, dynamic>))
        .toList(),
    favorites: (j['favorites'] as List)
        .map((e) => FavoriteRow.fromJson(e as Map<String, dynamic>))
        .toList(),
    overrides: (j['overrides'] as List)
        .map((e) => OverrideRow.fromJson(e as Map<String, dynamic>))
        .toList(),
    playEvents: (j['playEvents'] as List)
        .map((e) => PlayEventRow.fromJson(e as Map<String, dynamic>))
        .toList(),
  );

  @override
  bool operator ==(Object other) =>
      other is MetadataSnapshot &&
      other.deviceId == deviceId &&
      _listEq(other.playlists, playlists) &&
      _listEq(other.playlistItems, playlistItems) &&
      _listEq(other.favorites, favorites) &&
      _listEq(other.overrides, overrides) &&
      _listEq(other.playEvents, playEvents);

  @override
  int get hashCode => Object.hash(
    deviceId,
    Object.hashAll(playlists),
    Object.hashAll(playlistItems),
    Object.hashAll(favorites),
    Object.hashAll(overrides),
    Object.hashAll(playEvents),
  );
}

bool _listEq<T>(List<T> a, List<T> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
