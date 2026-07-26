import 'package:flutter_test/flutter_test.dart';
import 'package:openmusic/src/scraper/metadata_source.dart';

MatchCandidate _c(String title, String artist) =>
    MatchCandidate(source: 's', title: title, artist: artist, album: '');

void main() {
  test('标题与歌手都相等 => 可信', () {
    const q = TrackQuery(title: '浮夸', artist: 'Eason Chan');
    expect(isConfidentMatch(q, _c('浮夸', 'Eason Chan')), true);
  });

  test('标题相等、歌手大小写/空格差异(归一化后相等) => 可信', () {
    const q = TrackQuery(title: 'Hello', artist: 'Adele');
    expect(isConfidentMatch(q, _c('hello', 'adele')), true);
  });

  test('原歌手为空 => 只看标题', () {
    const q = TrackQuery(title: '晴天', artist: '');
    expect(isConfidentMatch(q, _c('晴天', '周杰伦')), true);
  });

  test('标题差很多 => 不可信', () {
    const q = TrackQuery(title: '浮夸', artist: 'Eason Chan');
    expect(isConfidentMatch(q, _c('K歌之王', 'Eason Chan')), false);
  });

  test('标题像但歌手不同 => 不可信', () {
    const q = TrackQuery(title: '演员', artist: '薛之谦');
    expect(isConfidentMatch(q, _c('演员', '其他歌手XYZ')), false);
  });

  test('similarityScore:相等=1、包含=0.8、无关偏低', () {
    expect(similarityScore('abc', 'abc'), 1);
    expect(similarityScore('abcdef', 'abc'), 0.8);
    expect(similarityScore('abc', 'xyz') < 0.8, true);
  });
}
