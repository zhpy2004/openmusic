import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:openmusic/src/scraper/itunes_source.dart';
import 'package:openmusic/src/scraper/lrclib_source.dart';
import 'package:openmusic/src/scraper/metadata_source.dart';
import 'package:openmusic/src/scraper/musicbrainz_source.dart';
import 'package:openmusic/src/scraper/rate_limiter.dart';

void main() {
  test('rankMatches:标题歌手更接近的候选排前', () {
    const q = TrackQuery(title: '晴天', artist: '周杰伦');
    const a = MatchCandidate(
      source: 'X',
      title: '完全不相干',
      artist: '别人',
      album: '',
    );
    const b = MatchCandidate(
      source: 'Y',
      title: '晴天',
      artist: '周杰伦',
      album: '叶惠美',
    );
    final ranked = rankMatches(q, const [a, b]);
    expect(ranked.first.title, '晴天');
  });

  test('rankMatches:同等相似度下有封面的排前', () {
    const q = TrackQuery(title: '晴天', artist: '周杰伦');
    const noCover = MatchCandidate(
      source: 'X',
      title: '晴天',
      artist: '周杰伦',
      album: '',
    );
    const withCover = MatchCandidate(
      source: 'Y',
      title: '晴天',
      artist: '周杰伦',
      album: '',
      coverUrl: 'http://x/1.jpg',
    );
    final ranked = rankMatches(q, const [noCover, withCover]);
    expect(ranked.first.coverUrl, isNotNull);
  });

  test('iTunes:解析结果为候选,artwork 换成高分辨率', () async {
    final client = MockClient((req) async {
      expect(req.url.host, 'itunes.apple.com');
      return http.Response(
        jsonEncode({
          'resultCount': 1,
          'results': [
            {
              'trackName': '晴天',
              'artistName': '周杰倫',
              'collectionName': '葉惠美',
              'artworkUrl100': 'https://is1.mzstatic.com/image/a/100x100bb.jpg',
              'releaseDate': '2003-07-31T07:00:00Z',
            },
          ],
        }),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });
    final src = ITunesSource(client);
    final out = await src.searchMatches(
      const TrackQuery(title: '晴天', artist: '周杰倫'),
    );
    expect(out.single.title, '晴天');
    expect(out.single.artist, '周杰倫');
    expect(out.single.album, '葉惠美');
    expect(out.single.year, 2003);
    expect(out.single.coverUrl, contains('600x600bb.jpg'));
    expect(out.single.source, 'iTunes');
  });

  test('iTunes:非 200 抛异常(由上层隔离)', () async {
    final client = MockClient((_) async => http.Response('nope', 503));
    final src = ITunesSource(client);
    expect(
      () => src.searchMatches(const TrackQuery(title: 'x')),
      throwsA(isA<Exception>()),
    );
  });

  test('LRCLIB:解析歌词候选,带时间轴优先', () async {
    final client = MockClient((req) async {
      expect(req.url.host, 'lrclib.net');
      return http.Response(
        jsonEncode([
          {
            'trackName': '晴天',
            'artistName': '周杰倫',
            'albumName': '葉惠美',
            'duration': 269,
            'plainLyrics': '故事的小黄花',
            'syncedLyrics': '[00:12.00]故事的小黄花',
          },
        ]),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });
    final src = LrclibSource(client);
    final out = await src.searchLyrics(
      const TrackQuery(title: '晴天', artist: '周杰倫', durationMs: 269000),
    );
    expect(out.single.hasSynced, isTrue);
    expect(out.single.best, startsWith('[00:12.00]'));
    expect(out.single.source, 'LRCLIB');
  });

  test('LRCLIB:无同步歌词时退回纯文本', () async {
    final client = MockClient(
      (_) async => http.Response(
        jsonEncode([
          {
            'trackName': 'x',
            'artistName': 'y',
            'plainLyrics': '纯文本歌词',
            'syncedLyrics': null,
          },
        ]),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      ),
    );
    final out = await LrclibSource(
      client,
    ).searchLyrics(const TrackQuery(title: 'x'));
    expect(out.single.hasSynced, isFalse);
    expect(out.single.best, '纯文本歌词');
  });

  test('MusicBrainz:解析 recording 并带 release 的 CoverArt 封面 URL', () async {
    final seen = <String>[];
    final client = MockClient((req) async {
      seen.add(req.url.host);
      expect(req.headers['User-Agent'], isNotNull); // MB 强制要求 UA
      return http.Response(
        jsonEncode({
          'recordings': [
            {
              'id': 'rec-1',
              'title': '晴天',
              'artist-credit': [
                {'name': '周杰倫'},
              ],
              'releases': [
                {'id': 'rel-1', 'title': '葉惠美', 'date': '2003-07-31'},
              ],
            },
          ],
        }),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });
    final src = MusicBrainzSource(
      client,
      limiter: RateLimiter(Duration.zero), // 测试不等真限流
    );
    final out = await src.searchMatches(
      const TrackQuery(title: '晴天', artist: '周杰倫'),
    );
    expect(out.single.title, '晴天');
    expect(out.single.artist, '周杰倫');
    expect(out.single.album, '葉惠美');
    expect(out.single.year, 2003);
    // 封面直接拼 Cover Art Archive 的 front 地址(不再多打一次请求)
    expect(out.single.coverUrl, contains('coverartarchive.org/release/rel-1'));
    expect(out.single.source, 'MusicBrainz');
    expect(seen, ['musicbrainz.org']);
  });

  test('MusicBrainz:无 release 时 coverUrl 为 null', () async {
    final client = MockClient(
      (_) async => http.Response(
        jsonEncode({
          'recordings': [
            {
              'id': 'rec-2',
              'title': 'x',
              'artist-credit': [
                {'name': 'y'},
              ],
            },
          ],
        }),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      ),
    );
    final out = await MusicBrainzSource(
      client,
      limiter: RateLimiter(Duration.zero),
    ).searchMatches(const TrackQuery(title: 'x'));
    expect(out.single.coverUrl, isNull);
    expect(out.single.album, '');
  });
}
