import 'dart:convert';

import 'package:http/http.dart' as http;

import 'metadata_source.dart';
import 'rate_limiter.dart';

/// MusicBrainz(开放元数据库)+ Cover Art Archive(开放封面库)。
///
/// MB 的两条硬性要求全封在本适配器内,对上层透明:
///  1. ≤1 req/秒 —— 由注入的 RateLimiter 串行限流;
///  2. 必须带可识别的 User-Agent,否则会被拒。
///
/// 封面不额外发请求:Cover Art Archive 提供按 release MBID 直达的 front 地址,
/// 直接拼 URL 交给图片加载器(该地址可能 404,由显示层当作无封面处理)。
class MusicBrainzSource implements MetadataSource {
  MusicBrainzSource(this._client, {RateLimiter? limiter, this.limit = 10})
    : _limiter = limiter ?? RateLimiter(const Duration(seconds: 1));

  final http.Client _client;
  final RateLimiter _limiter;
  final int limit;

  static const _userAgent = 'OpenMusic/0.2 (https://github.com/openmusic)';

  @override
  String get name => 'MusicBrainz';

  @override
  Future<List<MatchCandidate>> searchMatches(TrackQuery q) async {
    await _limiter.acquire();
    final lucene = [
      'recording:"${q.title}"',
      if (q.artist.isNotEmpty) 'artist:"${q.artist}"',
    ].join(' AND ');
    final uri = Uri.https('musicbrainz.org', '/ws/2/recording', {
      'query': lucene,
      'fmt': 'json',
      'limit': '$limit',
    });
    final res = await _client.get(uri, headers: {'User-Agent': _userAgent});
    if (res.statusCode != 200) {
      throw Exception('MusicBrainz HTTP ${res.statusCode}');
    }
    final json = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    final recs = (json['recordings'] as List<dynamic>? ?? const []);
    return recs.map((r) {
      final m = r as Map<String, dynamic>;
      final credits = m['artist-credit'] as List<dynamic>? ?? const [];
      final artist = credits.isEmpty
          ? ''
          : ((credits.first as Map<String, dynamic>)['name'] as String? ?? '');
      final releases = m['releases'] as List<dynamic>? ?? const [];
      final rel = releases.isEmpty
          ? null
          : releases.first as Map<String, dynamic>;
      final relId = rel?['id'] as String?;
      return MatchCandidate(
        source: name,
        title: (m['title'] as String?) ?? '',
        artist: artist,
        album: (rel?['title'] as String?) ?? '',
        year: _year(rel?['date'] as String?),
        coverUrl: relId == null
            ? null
            : 'https://coverartarchive.org/release/$relId/front-500',
      );
    }).toList();
  }

  int? _year(String? date) {
    if (date == null || date.length < 4) return null;
    return int.tryParse(date.substring(0, 4));
  }
}
