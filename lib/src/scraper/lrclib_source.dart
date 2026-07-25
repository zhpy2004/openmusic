import 'dart:convert';

import 'package:http/http.dart' as http;

import 'metadata_source.dart';

/// LRCLIB(开放歌词库,无鉴权)。返回带 [mm:ss.xx] 时间轴的 syncedLyrics
/// 与纯文本 plainLyrics。已知局限:中文覆盖有限(母 spec §11 已登记风险)。
class LrclibSource implements LyricsSource {
  LrclibSource(this._client);

  final http.Client _client;

  @override
  String get name => 'LRCLIB';

  @override
  Future<List<LyricsCandidate>> searchLyrics(TrackQuery q) async {
    final params = <String, String>{'track_name': q.title};
    if (q.artist.isNotEmpty) params['artist_name'] = q.artist;
    if (q.album.isNotEmpty) params['album_name'] = q.album;
    final uri = Uri.https('lrclib.net', '/api/search', params);
    final res = await _client.get(uri);
    if (res.statusCode != 200) {
      throw Exception('LRCLIB HTTP ${res.statusCode}');
    }
    final list = jsonDecode(utf8.decode(res.bodyBytes)) as List<dynamic>;
    return list
        .map((r) {
          final m = r as Map<String, dynamic>;
          return LyricsCandidate(
            source: name,
            title: (m['trackName'] as String?) ?? '',
            artist: (m['artistName'] as String?) ?? '',
            syncedLrc: m['syncedLyrics'] as String?,
            plainLrc: m['plainLyrics'] as String?,
          );
        })
        // 两者皆空的条目对用户无意义,过滤掉。
        .where((c) => c.best != null)
        .toList();
  }
}
