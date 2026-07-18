import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';

import 'audio_engine.dart';

/// media_kit(mpv) 实现：内部 Playlist 提供 gapless；shuffle/repeat 交给 mpv。
///
/// mpv 的 playlist-shuffle 会**物理重排** playlist（media_kit 随后按重排后的
/// 顺序重建 state.playlist，index 为重排后位置）。而 AudioEngine 契约要求
/// index 始终指向"原始入队顺序"下标，因此本实现负责双向翻译：
/// - [indexStream]：物理下标 → 原始入队下标（按 uri 查表）；
/// - [jump]：原始入队下标 → 当前物理位置（shuffle off 时二者相同）。
///
/// 假设队列内路径唯一（DB 以 path 为唯一键保证）；重复 uri 会使映射互相覆盖。
///
/// 薄封装不做单元测试，行为由 M1 烟测清单人工验证（spec §9）。
class MediaKitEngine implements AudioEngine {
  MediaKitEngine() : _player = Player();

  final Player _player;

  /// 原始入队顺序的 Media 列表（与 setQueue 的 paths 一一对应）。
  List<Media> _original = [];

  /// _key(uri) → 原始入队下标。
  Map<String, int> _indexByUri = {};

  /// mpv 回程的 uri 在 Windows 带 \\?\ 长路径前缀（safe_local_storage
  /// addPrefix），与入队侧 normalizeURI 产物失配；比较前统一剥前缀并归一
  /// 分隔符。两种形态都处理：原始 `\\?\` 与经 normalizeURI 斜杠化后的 `//?/`。
  static String _key(String uri) =>
      uri.replaceFirst(RegExp(r'^(\\\\\?\\|//\?/)'), '').replaceAll(r'\', '/');

  @override
  Future<void> setQueue(
    List<String> paths, {
    int startIndex = 0,
    bool play = true,
  }) async {
    _original = paths.map(Media.new).toList();
    _indexByUri = {
      for (var i = 0; i < _original.length; i++) _key(_original[i].uri): i,
    };
    await _player.open(Playlist(_original, index: startIndex), play: play);
  }

  @override
  Future<void> play() => _player.play();
  @override
  Future<void> pause() => _player.pause();
  @override
  Future<void> next() => _player.next();
  @override
  Future<void> previous() => _player.previous();

  /// [index] 是原始入队下标；翻译成当前（可能已 shuffle 的）物理位置再跳。
  @override
  Future<void> jump(int index) {
    final medias = _player.state.playlist.medias;
    var phys = -1;
    if (index >= 0 && index < _original.length) {
      final key = _key(_original[index].uri);
      phys = medias.indexWhere((m) => _key(m.uri) == key);
    }
    assert(() {
      if (phys < 0) {
        debugPrint('MediaKitEngine: jump($index) 未命中当前物理列表，回退按物理下标跳转');
      }
      return true;
    }());
    return _player.jump(phys >= 0 ? phys : index);
  }

  @override
  Future<void> seek(Duration position) => _player.seek(position);
  @override
  Future<void> setShuffle(bool enabled) => _player.setShuffle(enabled);

  @override
  Future<void> setRepeatMode(RepeatMode mode) =>
      _player.setPlaylistMode(switch (mode) {
        RepeatMode.off => PlaylistMode.none,
        RepeatMode.all => PlaylistMode.loop,
        RepeatMode.one => PlaylistMode.single,
      });

  /// 把物理下标翻译回原始入队下标以兑现 AudioEngine 契约。
  @override
  Stream<int> get indexStream => _player.stream.playlist.map((p) {
    if (p.index >= 0 && p.index < p.medias.length) {
      final uri = p.medias[p.index].uri;
      final original = _indexByUri[_key(uri)];
      if (original != null) return original;
      assert(() {
        debugPrint('MediaKitEngine: uri 未命中原始映射，回退物理下标: $uri');
        return true;
      }());
    }
    return p.index;
  }).distinct();
  @override
  Stream<bool> get playingStream => _player.stream.playing;
  @override
  Stream<Duration> get positionStream => _player.stream.position;
  @override
  Stream<Duration?> get durationStream => _player.stream.duration;

  @override
  Duration get position => _player.state.position;
  @override
  Duration? get duration => _player.state.duration;

  @override
  Future<void> dispose() => _player.dispose();
}
