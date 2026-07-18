import 'dart:io';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';

/// 从音频文件读出的最小元数据集（M1 只读不写；写回是 M2 刮削的事）。
class TrackMetadata {
  const TrackMetadata({
    required this.title,
    this.artist = '',
    this.album = '',
    this.albumArtist = '',
    this.durationMs = 0,
    this.trackNumber,
    this.year,
  });

  final String title;
  final String artist;
  final String album;
  final String albumArtist;
  final int durationMs;
  final int? trackNumber;
  final int? year;
}

abstract class TagReader {
  /// 读取失败（损坏/不支持）抛异常，由 Scanner 捕获记入问题清单。
  Future<TrackMetadata> read(String path);
}

class AudioMetadataTagReader implements TagReader {
  @override
  Future<TrackMetadata> read(String path) async {
    // readMetadata 是同步 API（package:audio_metadata_reader 1.6.0，见
    // lib/src/parser.dart），这里包一层 async 只是为了满足 TagReader 接口形状。
    final meta = readMetadata(File(path), getImage: false);
    final fallbackTitle = path.split(RegExp(r'[\\/]')).last;
    final title = meta.title?.trim() ?? '';
    return TrackMetadata(
      title: title.isNotEmpty ? title : fallbackTitle,
      artist: meta.artist ?? '',
      album: meta.album ?? '',
      // 包的 AudioMetadata 无 albumArtist 字段，留空。
      durationMs: meta.duration?.inMilliseconds ?? 0,
      trackNumber: meta.trackNumber,
      year: meta.year?.year,
    );
  }
}
