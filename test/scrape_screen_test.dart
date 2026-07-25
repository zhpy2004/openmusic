import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openmusic/src/app/providers.dart';
import 'package:openmusic/src/data/database.dart';
import 'package:openmusic/src/scraper/metadata_source.dart';
import 'package:openmusic/src/scraper/scraper_service.dart';
import 'package:openmusic/src/ui/scrape_screen.dart';

import 'helpers/db.dart';

/// 不发网络的假服务:直接返回预置候选。
class _FakeScraper extends ScraperService {
  _FakeScraper(this._results, {super.db})
    : super(matchSources: const [], lyricsSources: const []);

  final ScrapeResults _results;

  @override
  Future<ScrapeResults> search(TrackQuery q) async => _results;
}

void main() {
  late AppDatabase db;
  late Directory dir;
  late Track seeded;

  // 所有真实文件 IO 与建库都放在 setUp:setUp 跑在真实异步里。
  // 若放进 testWidgets 体内,fake-async 冻结时钟不推进真实 IO 完成回调,
  // File().writeAsBytes() 会永久挂死(drift 内存库靠 microtask 完成,不受影响)。
  setUp(() async {
    db = AppDatabase(testExecutor());
    dir = await Directory.systemTemp.createTemp('om_scrape_ui');
    final path = '${dir.path}/song.mp3';
    await File(path).writeAsBytes(const [1]);
    await db.upsertTrack(
      TracksCompanion.insert(
        path: path,
        fingerprint: 'fpA',
        title: '原标题',
        artist: const Value('原歌手'),
        sizeBytes: 1,
        mtimeMs: 1,
      ),
    );
    seeded = (await db.select(db.tracks).get()).single;
  });
  tearDown(() async {
    await db.close();
    await dir.delete(recursive: true);
  });

  Widget app(Track t, ScraperService svc) => ProviderScope(
    overrides: [
      databaseProvider.overrideWithValue(db),
      scraperServiceProvider.overrideWithValue(svc),
    ],
    child: MaterialApp(home: ScrapeScreen(track: t)),
  );

  testWidgets('展示匹配候选与歌词候选', (tester) async {
    final svc = _FakeScraper(
      const ScrapeResults(
        matches: [
          MatchCandidate(
            source: 'iTunes',
            title: '晴天',
            artist: '周杰倫',
            album: '葉惠美',
          ),
        ],
        lyrics: [
          LyricsCandidate(
            source: 'LRCLIB',
            title: '晴天',
            artist: '周杰倫',
            syncedLrc: '[00:01.00]hi',
          ),
        ],
        failedSources: [],
      ),
      db: db,
    );
    await tester.pumpWidget(app(seeded, svc));
    await tester.pumpAndSettle();
    expect(find.text('葉惠美'), findsOneWidget);
    expect(find.textContaining('LRCLIB'), findsWidgets);
  });

  testWidgets('无结果时显示空态', (tester) async {
    final svc = _FakeScraper(
      const ScrapeResults(matches: [], lyrics: [], failedSources: []),
      db: db,
    );
    await tester.pumpWidget(app(seeded, svc));
    await tester.pumpAndSettle();
    expect(find.text('无匹配结果,可重试'), findsOneWidget);
  });

  testWidgets('有源失败时提示不可用', (tester) async {
    final svc = _FakeScraper(
      const ScrapeResults(
        matches: [],
        lyrics: [],
        failedSources: ['MusicBrainz'],
      ),
      db: db,
    );
    await tester.pumpWidget(app(seeded, svc));
    await tester.pumpAndSettle();
    expect(find.textContaining('MusicBrainz'), findsOneWidget);
  });

  testWidgets('选中候选并应用 → 写 override 到库', (tester) async {
    final svc = _FakeScraper(
      const ScrapeResults(
        matches: [
          MatchCandidate(
            source: 'iTunes',
            title: '晴天',
            artist: '周杰倫',
            album: '葉惠美',
          ),
        ],
        lyrics: [],
        failedSources: [],
      ),
      db: db,
    );
    await tester.pumpWidget(app(seeded, svc));
    await tester.pumpAndSettle();
    await tester.tap(find.text('葉惠美')); // 点候选行选中
    await tester.pumpAndSettle();
    await tester.tap(find.text('应用文本修正')); // 文本修正默认关,显式勾上才写 override
    await tester.pumpAndSettle();
    await tester.tap(find.text('应用'));
    await tester.pumpAndSettle();

    // fake-async 冻结,读 DB 终态必须走 runAsync
    final o = await tester.runAsync(() => db.getTrackOverride('fpA'));
    expect(o!.title, '晴天');
  });
}
