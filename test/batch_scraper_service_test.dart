import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:http/http.dart' as http;
import 'package:openmusic/src/data/database.dart';
import 'package:openmusic/src/scraper/batch_scraper_service.dart';
import 'package:openmusic/src/scraper/metadata_source.dart';
import 'package:openmusic/src/scraper/scraper_service.dart';

// 可控假源:按传入列表返回固定候选。
class FakeMatchSource implements MetadataSource {
  FakeMatchSource(this.result);
  final List<MatchCandidate> result;
  @override
  String get name => 'FakeMatch';
  @override
  Future<List<MatchCandidate>> searchMatches(TrackQuery q) async => result;
}

class FakeLyricsSource implements LyricsSource {
  FakeLyricsSource(this.result);
  final List<LyricsCandidate> result;
  @override
  String get name => 'FakeLyrics';
  @override
  Future<List<LyricsCandidate>> searchLyrics(TrackQuery q) async => result;
}

class ThrowingMatchSource implements MetadataSource {
  @override
  String get name => 'Throwing';
  @override
  Future<List<MatchCandidate>> searchMatches(TrackQuery q) async =>
      throw Exception('boom');
}

late Directory dir;
Track trk(String file, String title, {String artist = 'Eason Chan'}) => Track(
  id: title.hashCode,
  path: '${dir.path}/$file',
  fingerprint: 'fp_$file',
  title: title,
  artist: artist,
  album: '',
  albumArtist: '',
  durationMs: 0,
  trackNumber: null,
  year: null,
  sizeBytes: 1,
  mtimeMs: 1,
  addedAt: DateTime(2026),
);

ScraperService scraperWith({
  List<MatchCandidate> matches = const [],
  List<LyricsCandidate> lyrics = const [],
  MetadataSource? matchSource,
  http.Client? client,
}) => ScraperService(
  matchSources: [matchSource ?? FakeMatchSource(matches)],
  lyricsSources: [FakeLyricsSource(lyrics)],
  httpClient:
      client ?? MockClient((req) async => http.Response.bytes([1, 2, 3], 200)),
);

Future<BatchProgress> runToEnd(
  BatchScraperService svc,
  List<Track> tracks, {
  bool Function()? cancel,
}) async {
  BatchProgress last = const BatchProgress(
    done: 0,
    total: 0,
    appliedCovers: 0,
    appliedLyrics: 0,
    skippedNoMatch: 0,
    finished: true,
  );
  await for (final p in svc.run(tracks, shouldCancel: cancel)) {
    last = p;
  }
  return last;
}

void main() {
  setUp(() async => dir = await Directory.systemTemp.createTemp('om_batch'));
  tearDown(() async => dir.delete(recursive: true));

  test('缺封面缺歌词 + 可信匹配 => 两样都补,计数 1/1,文件落地', () async {
    final t = trk('a.mp3', '浮夸');
    await File(t.path).writeAsBytes(const [0]);
    final svc = BatchScraperService(
      scraperWith(
        matches: [
          const MatchCandidate(
            source: 's',
            title: '浮夸',
            artist: 'Eason Chan',
            album: '',
            coverUrl: 'http://x/cover.jpg',
          ),
        ],
        lyrics: [
          const LyricsCandidate(
            source: 'L',
            title: '浮夸',
            artist: 'Eason Chan',
            syncedLrc: '[00:01.00]hi',
          ),
        ],
      ),
    );
    final last = await runToEnd(svc, [t]);
    expect(last.finished, true);
    expect(last.appliedCovers, 1);
    expect(last.appliedLyrics, 1);
    expect(await File('${dir.path}/a.jpg').exists(), true);
    expect(await File('${dir.path}/a.lrc').exists(), true);
  });

  test('已有封面和歌词 => 不入待处理(total 0)', () async {
    final t = trk('b.mp3', '浮夸');
    await File(t.path).writeAsBytes(const [0]);
    await File('${dir.path}/b.jpg').writeAsBytes(const [9]);
    await File('${dir.path}/b.lrc').writeAsString('x');
    final svc = BatchScraperService(
      scraperWith(
        matches: [
          const MatchCandidate(
            source: 's',
            title: '浮夸',
            artist: 'Eason Chan',
            album: '',
            coverUrl: 'http://x/c.jpg',
          ),
        ],
      ),
    );
    final last = await runToEnd(svc, [t]);
    expect(last.total, 0);
    expect(last.appliedCovers, 0);
  });

  test('弱匹配 => 保守规则挡下封面,但仍补歌词', () async {
    final t = trk('c.mp3', '浮夸');
    await File(t.path).writeAsBytes(const [0]);
    final svc = BatchScraperService(
      scraperWith(
        matches: [
          const MatchCandidate(
            source: 's',
            title: 'K歌之王',
            artist: 'Eason Chan',
            album: '',
            coverUrl: 'http://x/c.jpg',
          ),
        ],
        lyrics: [
          const LyricsCandidate(
            source: 'L',
            title: '浮夸',
            artist: 'Eason Chan',
            syncedLrc: '[00:01.00]hi',
          ),
        ],
      ),
    );
    final last = await runToEnd(svc, [t]);
    expect(last.appliedCovers, 0);
    expect(last.appliedLyrics, 1);
    expect(await File('${dir.path}/c.jpg').exists(), false);
    expect(await File('${dir.path}/c.lrc').exists(), true);
  });

  test('无任何可应用结果 => skippedNoMatch 计数', () async {
    final t = trk('d.mp3', '浮夸');
    await File(t.path).writeAsBytes(const [0]);
    final svc = BatchScraperService(scraperWith()); // 无 match 无 lyrics
    final last = await runToEnd(svc, [t]);
    expect(last.skippedNoMatch, 1);
    expect(last.appliedCovers, 0);
    expect(last.appliedLyrics, 0);
  });

  test('搜索源抛异常 => 隔离,该首计 skippedNoMatch,不中断', () async {
    final t = trk('e.mp3', '浮夸');
    await File(t.path).writeAsBytes(const [0]);
    final svc = BatchScraperService(
      scraperWith(matchSource: ThrowingMatchSource()),
    );
    final last = await runToEnd(svc, [t]);
    expect(last.finished, true);
    expect(last.skippedNoMatch, 1);
  });

  test('shouldCancel 首次即真 => 不处理,直接收尾', () async {
    final t = trk('f.mp3', '浮夸');
    await File(t.path).writeAsBytes(const [0]);
    final svc = BatchScraperService(
      scraperWith(
        matches: [
          const MatchCandidate(
            source: 's',
            title: '浮夸',
            artist: 'Eason Chan',
            album: '',
            coverUrl: 'http://x/c.jpg',
          ),
        ],
      ),
    );
    final last = await runToEnd(svc, [t], cancel: () => true);
    expect(last.finished, true);
    expect(last.done, 0);
    expect(await File('${dir.path}/f.jpg').exists(), false);
  });

  test('空曲目列表 => 立即收尾 total 0', () async {
    final svc = BatchScraperService(scraperWith());
    final last = await runToEnd(svc, const []);
    expect(last.finished, true);
    expect(last.total, 0);
  });

  test('封面下载失败 => 只封面跳过,歌词仍补,批量继续', () async {
    final t = trk('g.mp3', '浮夸');
    await File(t.path).writeAsBytes(const [0]);
    // 封面 URL 返回 500,apply 写封面时抛异常;歌词是本地写,应成功。
    final svc = BatchScraperService(
      scraperWith(
        matches: [
          const MatchCandidate(
            source: 's',
            title: '浮夸',
            artist: 'Eason Chan',
            album: '',
            coverUrl: 'http://x/c.jpg',
          ),
        ],
        lyrics: [
          const LyricsCandidate(
            source: 'L',
            title: '浮夸',
            artist: 'Eason Chan',
            syncedLrc: '[00:01.00]hi',
          ),
        ],
        client: MockClient((req) async => http.Response('err', 500)),
      ),
    );
    final last = await runToEnd(svc, [t]);
    expect(last.appliedCovers, 0);
    expect(last.appliedLyrics, 1);
    expect(await File('${dir.path}/g.jpg').exists(), false);
    expect(await File('${dir.path}/g.lrc').exists(), true);
    expect(last.skippedNoMatch, 0); // 补了歌词,不算 skip
  });
}
