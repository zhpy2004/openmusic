import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:openmusic/src/data/database.dart';
import 'package:openmusic/src/scraper/metadata_source.dart';
import 'package:openmusic/src/scraper/scraper_service.dart';

import 'helpers/db.dart';

class _FakeMatchSource implements MetadataSource {
  _FakeMatchSource(this.name, this.out, {this.fail = false});
  @override
  final String name;
  final List<MatchCandidate> out;
  final bool fail;
  @override
  Future<List<MatchCandidate>> searchMatches(TrackQuery q) async {
    if (fail) throw Exception('down');
    return out;
  }
}

class _FakeLyricsSource implements LyricsSource {
  _FakeLyricsSource(this.name, this.out, {this.fail = false});
  @override
  final String name;
  final List<LyricsCandidate> out;
  final bool fail;
  @override
  Future<List<LyricsCandidate>> searchLyrics(TrackQuery q) async {
    if (fail) throw Exception('down');
    return out;
  }
}

void main() {
  const q = TrackQuery(title: '晴天', artist: '周杰倫');
  const c1 = MatchCandidate(source: 'A', title: '晴天', artist: '周杰倫', album: '');
  const c2 = MatchCandidate(source: 'B', title: '别的', artist: '别人', album: '');
  const l1 = LyricsCandidate(
    source: 'L',
    title: '晴天',
    artist: '周杰倫',
    syncedLrc: '[00:01.00]hi',
  );

  test('聚合多源候选并按相似度排序', () async {
    final svc = ScraperService(
      matchSources: [
        _FakeMatchSource('A', const [c2]),
        _FakeMatchSource('B', const [c1]),
      ],
      lyricsSources: [
        _FakeLyricsSource('L', const [l1]),
      ],
    );
    final r = await svc.search(q);
    expect(r.matches.length, 2);
    expect(r.matches.first.title, '晴天'); // 更像的排前
    expect(r.lyrics.single.source, 'L');
    expect(r.failedSources, isEmpty);
  });

  test('单源失败被隔离:其余结果照常返回,失败源被记名', () async {
    final svc = ScraperService(
      matchSources: [
        _FakeMatchSource('A', const [], fail: true),
        _FakeMatchSource('B', const [c1]),
      ],
      lyricsSources: [_FakeLyricsSource('L', const [], fail: true)],
    );
    final r = await svc.search(q);
    expect(r.matches.single.title, '晴天');
    expect(r.lyrics, isEmpty);
    expect(r.failedSources, containsAll(<String>['A', 'L']));
  });

  test('全部源无结果时返回空,不抛异常', () async {
    final svc = ScraperService(
      matchSources: [_FakeMatchSource('A', const [])],
      lyricsSources: [_FakeLyricsSource('L', const [])],
    );
    final r = await svc.search(q);
    expect(r.matches, isEmpty);
    expect(r.lyrics, isEmpty);
    expect(r.failedSources, isEmpty);
  });

  group('apply/undo', () {
    late AppDatabase db;
    late Directory dir;

    setUp(() async {
      db = AppDatabase(testExecutor());
      dir = await Directory.systemTemp.createTemp('om_scrape');
    });
    tearDown(() async {
      await db.close();
      await dir.delete(recursive: true);
    });

    Future<Track> seedTrack() async {
      final path = '${dir.path}/song.mp3';
      await File(path).writeAsBytes(List.filled(16, 1));
      await db.upsertTrack(
        TracksCompanion.insert(
          path: path,
          fingerprint: 'fpA',
          title: '原标题',
          artist: const Value('原歌手'),
          album: const Value('原专辑'),
          sizeBytes: 16,
          mtimeMs: 1,
        ),
      );
      return (await db.select(db.tracks).get()).single;
    }

    ScraperService svcWithCover(List<int> bytes) => ScraperService(
      matchSources: const [],
      lyricsSources: const [],
      db: db,
      httpClient: MockClient((_) async => http.Response.bytes(bytes, 200)),
    );

    test('应用封面:下载写成同名 .jpg,不碰音频文件', () async {
      final t = await seedTrack();
      final audioBefore = await File(t.path).readAsBytes();
      await svcWithCover(const [9, 9, 9]).apply(
        t,
        const ScrapeSelection(
          match: MatchCandidate(
            source: 'A',
            title: '晴天',
            artist: '周杰倫',
            album: '葉惠美',
            coverUrl: 'http://x/c.jpg',
          ),
          applyCover: true,
          applyText: false,
        ),
      );
      expect(await File('${dir.path}/song.jpg').readAsBytes(), [9, 9, 9]);
      // 红线:音频字节必须一字未改(改了指纹就变,歌单/收藏关联会断)
      expect(await File(t.path).readAsBytes(), audioBefore);
      expect(await db.getTrackOverride('fpA'), isNull); // 没勾文本就不写覆盖
    });

    test('应用文本:写 override 并物化回 tracks', () async {
      final t = await seedTrack();
      await svcWithCover(const []).apply(
        t,
        const ScrapeSelection(
          match: MatchCandidate(
            source: 'A',
            title: '晴天',
            artist: '周杰倫',
            album: '葉惠美',
          ),
          applyCover: false,
          applyText: true,
        ),
      );
      expect((await db.select(db.tracks).get()).single.title, '晴天');
      expect((await db.getTrackOverride('fpA'))!.artist, '周杰倫');
    });

    test('应用歌词:写成同名 .lrc', () async {
      final t = await seedTrack();
      await svcWithCover(const []).apply(
        t,
        const ScrapeSelection(
          lyrics: LyricsCandidate(
            source: 'L',
            title: '晴天',
            artist: '周杰倫',
            syncedLrc: '[00:01.00]hi',
          ),
        ),
      );
      expect(await File('${dir.path}/song.lrc').readAsString(), '[00:01.00]hi');
    });

    test('撤销:删 sidecar + 删 override,文本回落到文件标签', () async {
      final t = await seedTrack();
      final svc = svcWithCover(const [9]);
      await svc.apply(
        t,
        const ScrapeSelection(
          match: MatchCandidate(
            source: 'A',
            title: '晴天',
            artist: '周杰倫',
            album: '葉惠美',
            coverUrl: 'http://x/c.jpg',
          ),
          applyCover: true,
          applyText: true,
          lyrics: LyricsCandidate(
            source: 'L',
            title: '晴天',
            artist: '周杰倫',
            syncedLrc: '[00:01.00]hi',
          ),
        ),
      );
      expect(await File('${dir.path}/song.jpg').exists(), isTrue);

      await svc.undo(t, fileTitle: '原标题', fileArtist: '原歌手', fileAlbum: '原专辑');

      expect(await File('${dir.path}/song.jpg').exists(), isFalse);
      expect(await File('${dir.path}/song.lrc').exists(), isFalse);
      expect(await db.getTrackOverride('fpA'), isNull);
      expect((await db.select(db.tracks).get()).single.title, '原标题');
    });

    test('撤销可重复调用(幂等)', () async {
      final t = await seedTrack();
      final svc = svcWithCover(const []);
      await svc.undo(t, fileTitle: '原标题', fileArtist: '原歌手', fileAlbum: '原专辑');
      await svc.undo(t, fileTitle: '原标题', fileArtist: '原歌手', fileAlbum: '原专辑');
      expect((await db.select(db.tracks).get()).single.title, '原标题');
    });
  });
}
