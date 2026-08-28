/// 对端清单里的一条:它有文件的某个曲目。
class RemoteFile {
  const RemoteFile({
    required this.fp,
    required this.name,
    required this.size,
    required this.hasCover,
    required this.hasLyrics,
  });

  final String fp;

  /// 对端的文件名(不含目录)。落盘时用它,撞名再加后缀。
  final String name;
  final int size;
  final bool hasCover;
  final bool hasLyrics;

  Map<String, dynamic> toJson() => {
    'fp': fp,
    'name': name,
    'size': size,
    'hasCover': hasCover,
    'hasLyrics': hasLyrics,
  };

  factory RemoteFile.fromJson(Map<String, dynamic> j) => RemoteFile(
    fp: j['fp'] as String,
    name: j['name'] as String,
    size: j['size'] as int,
    hasCover: j['hasCover'] as bool,
    hasLyrics: j['hasLyrics'] as bool,
  );

  @override
  bool operator ==(Object other) =>
      other is RemoteFile &&
      other.fp == fp &&
      other.name == name &&
      other.size == size &&
      other.hasCover == hasCover &&
      other.hasLyrics == hasLyrics;

  @override
  int get hashCode => Object.hash(fp, name, size, hasCover, hasLyrics);
}

/// 一次文件同步要做什么。
class FileSyncPlan {
  const FileSyncPlan({
    required this.toDownload,
    required this.alreadyHave,
    required this.peerMissing,
  });

  final List<RemoteFile> toDownload;

  /// 镜像歌单要、但本机已经有文件的数量(跳过,不重复下载)。
  final int alreadyHave;

  /// 镜像歌单要、本机没有、**对端也没有**的数量。不是失败,只是双方都缺。
  final int peerMissing;

  bool get isEmpty => toDownload.isEmpty;
}

/// 纯函数差集:不碰网络、不碰磁盘、不看时钟。
///
/// [mirroredTrackFps] 已勾选镜像的歌单里的全部曲目指纹
/// [localFps] 本机**已有文件**的曲目指纹
/// [remote] 对端清单
FileSyncPlan planFileSync({
  required Set<String> mirroredTrackFps,
  required Set<String> localFps,
  required List<RemoteFile> remote,
}) {
  final remoteByFp = <String, RemoteFile>{};
  for (final f in remote) {
    remoteByFp[f.fp] = f; // 对端清单若有重复,后者覆盖,天然去重
  }

  final toDownload = <RemoteFile>[];
  var alreadyHave = 0;
  var peerMissing = 0;

  for (final fp in mirroredTrackFps) {
    if (localFps.contains(fp)) {
      alreadyHave++;
      continue;
    }
    final f = remoteByFp[fp];
    if (f == null) {
      peerMissing++;
      continue;
    }
    toDownload.add(f);
  }

  return FileSyncPlan(
    toDownload: toDownload,
    alreadyHave: alreadyHave,
    peerMissing: peerMissing,
  );
}
