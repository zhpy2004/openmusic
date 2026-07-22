import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/database.dart';
import '../library/scanner.dart';
import '../library/tag_reader.dart';
import '../playback/audio_engine.dart';
import '../playback/playback_controller.dart';

/// database 与 engine 在 main() 里用 overrideWithValue 注入（测试同理）。
final databaseProvider = Provider<AppDatabase>(
  (ref) => throw UnimplementedError(),
);
final audioEngineProvider = Provider<AudioEngine>(
  (ref) => throw UnimplementedError(),
);

final playbackControllerProvider = ChangeNotifierProvider<PlaybackController>((
  ref,
) {
  // 不要 ref.onDispose(controller.dispose)：ChangeNotifierProvider 销毁时
  // 自己会调 notifier.dispose()（ChangeNotifierProviderElement.runOnDispose），
  // 再注册一次会二次 dispose 触发 ChangeNotifier 断言。
  return PlaybackController(ref.watch(audioEngineProvider));
});

final scannerProvider = Provider<LibraryScanner>(
  (ref) =>
      LibraryScanner(ref.watch(databaseProvider), AudioMetadataTagReader()),
);

final searchQueryProvider = StateProvider<String>((ref) => '');

final trackListProvider = StreamProvider<List<Track>>(
  (ref) =>
      ref.watch(databaseProvider).watchTracks(ref.watch(searchQueryProvider)),
);

final scanRootsProvider = StreamProvider<List<String>>(
  (ref) => ref.watch(databaseProvider).watchScanRoots(),
);

/// 扫描进度；null = 未在扫描。
final scanProgressProvider = StateProvider<ScanProgress?>((ref) => null);

/// 上次扫描的问题清单（损坏文件、不可达根）。scanProgress 在 done 事件即置 null、
/// 无法承载事后可见的问题报告，故单列此 provider：扫描开始清空，done 后保留供
/// 用户在设置页查看，点“清除”或下次扫描开始时重置。
final lastScanProblemsProvider = StateProvider<List<String>>((ref) => const []);

/// 歌单列表(按 updatedAt 倒序)。
final playlistsProvider = StreamProvider<List<Playlist>>(
  (ref) => ref.watch(databaseProvider).watchPlaylists(),
);

/// 某歌单的成员(含指纹关联到的曲目;track 为 null = 文件缺失)。
/// autoDispose:family 按 uuid 生成实例,详情页关闭后须释放对应 watch 订阅,
/// 否则浏览多个歌单会累积永不关闭的 SQLite 查询流。
final playlistItemsProvider = StreamProvider.autoDispose
    .family<List<PlaylistEntry>, String>(
      (ref, uuid) => ref.watch(databaseProvider).watchPlaylistItems(uuid),
    );

/// 收藏的曲目指纹(按 addedAt 倒序)。
final favoritesProvider = StreamProvider<List<String>>(
  (ref) => ref.watch(databaseProvider).watchFavorites(),
);

/// 单曲收藏状态(红心按钮实时反映)。autoDispose.family:每曲一个,列表项/播放页
/// 卸载即释放。用具名 provider 而非在 build 里 new StreamProvider——后者每次重建
/// 都造新 provider、永不释放,是 Riverpod 常见泄漏坑。
final isFavoriteProvider = StreamProvider.autoDispose.family<bool, String>(
  (ref, fp) => ref.watch(databaseProvider).watchIsFavorite(fp),
);
