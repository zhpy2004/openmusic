import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import '../data/database.dart';
import '../library/scanner.dart';
import '../library/tag_reader.dart';
import '../lyrics/lrc.dart';
import '../playback/audio_engine.dart';
import '../playback/playback_controller.dart';
import '../scraper/batch_scraper_service.dart';
import '../scraper/itunes_source.dart';
import '../scraper/lrclib_source.dart';
import '../scraper/musicbrainz_source.dart';
import '../scraper/scraper_service.dart';
import '../sync/bonsoir_discovery.dart';
import '../sync/device_identity.dart';
import '../sync/sync_controller.dart';

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
final lastScanProblemsProvider = StateProvider<List<ScanProblem>>(
  (ref) => const [],
);

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

/// 解析曲目封面的伴随文件路径:同名 .jpg 优先,其次 .png;都没有返回 null。
/// (内嵌封面的读取留到后续增强——M2-B 的封面来源是刮削写下的伴随文件。)
Future<String?> resolveCoverPath(String audioPath) async {
  for (final ext in const ['.jpg', '.png']) {
    final candidate = p.setExtension(audioPath, ext);
    if (await File(candidate).exists()) return candidate;
  }
  return null;
}

/// 单曲封面路径;autoDispose.family:列表滚动/页面关闭即释放。
final coverArtProvider = FutureProvider.autoDispose.family<String?, String>(
  (ref, audioPath) => resolveCoverPath(audioPath),
);

/// 读取并解析曲目歌词 sidecar:同名 .lrc 存在则解析,否则 null。
/// allowMalformed 防个别坏字节令整篇解码失败;解析后无有效行也返回 null。
Future<Lyrics?> resolveLyrics(String audioPath) async {
  final path = p.setExtension(audioPath, '.lrc');
  final f = File(path);
  if (!await f.exists()) return null;
  final raw = utf8.decode(await f.readAsBytes(), allowMalformed: true);
  final lyrics = parseLrc(raw);
  return lyrics.isEmpty ? null : lyrics;
}

/// 单曲歌词;autoDispose.family:切歌/关页即释放(同 coverArtProvider)。
final lyricsProvider = FutureProvider.autoDispose.family<Lyrics?, String>(
  (ref, audioPath) => resolveLyrics(audioPath),
);

/// 三源刮削服务。http.Client 在此统一注入,便于测试替换。
final scraperServiceProvider = Provider<ScraperService>((ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return ScraperService(
    matchSources: [ITunesSource(client), MusicBrainzSource(client)],
    lyricsSources: [LrclibSource(client)],
    db: ref.watch(databaseProvider),
    httpClient: client,
  );
});

/// 批量刮削服务:复用同一个 scraperServiceProvider(其 MusicBrainz 源自带
/// 1req/s 限流,批量顺序调用自动受限)。
final batchScraperServiceProvider = Provider<BatchScraperService>(
  (ref) => BatchScraperService(ref.watch(scraperServiceProvider)),
);

/// 是否让 App 在前台自动启动同步服务。
///
/// **默认 false,只有 main.dart 打开它。** 原因:`HttpServer.bind` 会注册一个
/// 周期性的 idleTimeout 定时器,在 `testWidgets` 的假时钟下就成了"永远未完成的
/// timer",任何 pump 了 OpenMusicApp 的 widget 测试都会因此断言失败。默认关掉
/// 意味着测试永远不会意外开套接字;真实启动路径由 main.dart 显式打开。
final syncAutoStartProvider = Provider<bool>((ref) => false);

/// 同步控制器。生命周期跟随 App 前台(见 app.dart 的 AppLifecycleListener)。
final syncControllerProvider = ChangeNotifierProvider<SyncController>(
  (ref) => SyncController(
    db: ref.watch(databaseProvider),
    discovery: BonsoirNetworkDiscovery(),
    platform: localPlatform(),
  ),
);

/// 已配对设备列表。
final pairedPeersProvider = StreamProvider<List<Peer>>(
  (ref) => ref.watch(databaseProvider).watchPeers(),
);

/// 已勾选「在本机保留文件」的歌单 uuid。
final mirroredPlaylistsProvider = StreamProvider<Set<String>>(
  (ref) => ref.watch(databaseProvider).watchMirroredPlaylistUuids(),
);

/// 语言偏好的存储键。取值:'system'(默认)/ 'zh' / 'en'。
const kLocalePrefKey = 'locale';

/// 把偏好字符串翻译成 MaterialApp.locale:
/// null / 'system' / 无法识别的值 → null(交给 Flutter 跟随系统)。
Locale? localeFromPreference(String? pref) => switch (pref) {
  'zh' => const Locale('zh'),
  'en' => const Locale('en'),
  _ => null,
};

/// 当前语言偏好(原始字符串),随数据库变化即时更新。
final localePreferenceProvider = StreamProvider<String?>(
  (ref) => ref.watch(databaseProvider).watchSetting(kLocalePrefKey),
);
