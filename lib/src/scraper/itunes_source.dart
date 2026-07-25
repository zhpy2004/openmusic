import 'dart:convert';

import 'package:http/http.dart' as http;

import 'metadata_source.dart';

/// iTunes Search API(官方公开接口,无鉴权、无严格限流)。
/// 一次请求即返回封面 URL + 标题/歌手/专辑/年份。
class ITunesSource implements MetadataSource {
  ITunesSource(this._client, {this.limit = 10});

  final http.Client _client;
  final int limit;

  @override
  String get name => 'iTunes';

  @override
  Future<List<MatchCandidate>> searchMatches(TrackQuery q) async {
    final term = [q.title, q.artist].where((s) => s.isNotEmpty).join(' ');
    final uri = Uri.https('itunes.apple.com', '/search', {
      'term': term,
      'media': 'music',
      'entity': 'song',
      'limit': '$limit',
    });
    final res = await _client.get(uri);
    if (res.statusCode != 200) {
      throw Exception('iTunes HTTP ${res.statusCode}');
    }
    // 用 bodyBytes + utf8.decode:iTunes 返回 UTF-8,若依赖 res.body 的
    // 字符集推断,中文可能乱码。
    final json = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    final results = (json['results'] as List<dynamic>? ?? const []);
    return results.map((r) {
      final m = r as Map<String, dynamic>;
      final art = m['artworkUrl100'] as String?;
      return MatchCandidate(
        source: name,
        title: (m['trackName'] as String?) ?? '',
        artist: (m['artistName'] as String?) ?? '',
        album: (m['collectionName'] as String?) ?? '',
        year: _year(m['releaseDate'] as String?),
        // 100x100 是缩略图;换成 600x600 拿高清封面(iTunes 约定的 URL 变体)。
        coverUrl: art?.replaceAll('100x100bb', '600x600bb'),
      );
    }).toList();
  }

  int? _year(String? iso) {
    if (iso == null || iso.length < 4) return null;
    return int.tryParse(iso.substring(0, 4));
  }
}
