import 'package:flutter_test/flutter_test.dart';
import 'package:openmusic/src/sync/file_transfer_plan.dart';

RemoteFile rf(String fp, {String? name, int size = 100}) => RemoteFile(
  fp: fp,
  name: name ?? '$fp.mp3',
  size: size,
  hasCover: false,
  hasLyrics: false,
);

void main() {
  test('只拉镜像歌单里、本机没有、对端有的曲目', () {
    final plan = planFileSync(
      mirroredTrackFps: {'a', 'b', 'c'},
      localFps: {'a'}, // a 本机已有
      remote: [rf('a'), rf('b'), rf('d')], // d 不在镜像歌单里
    );
    expect(plan.toDownload.map((f) => f.fp), ['b']);
  });

  test('本机已有的计入 alreadyHave,不重复下载', () {
    final plan = planFileSync(
      mirroredTrackFps: {'a', 'b'},
      localFps: {'a', 'b'},
      remote: [rf('a'), rf('b')],
    );
    expect(plan.toDownload, isEmpty);
    expect(plan.alreadyHave, 2);
  });

  test('镜像歌单要、但对端也没有的计入 peerMissing', () {
    final plan = planFileSync(
      mirroredTrackFps: {'a', 'x'},
      localFps: <String>{},
      remote: [rf('a')],
    );
    expect(plan.toDownload.map((f) => f.fp), ['a']);
    expect(plan.peerMissing, 1); // x 对端也没有
  });

  test('对端清单里有重复条目也只下一次', () {
    final plan = planFileSync(
      mirroredTrackFps: {'a'},
      localFps: <String>{},
      remote: [rf('a'), rf('a')],
    );
    expect(plan.toDownload.length, 1);
  });

  test('没有勾选任何歌单 → 空计划', () {
    final plan = planFileSync(
      mirroredTrackFps: <String>{},
      localFps: <String>{},
      remote: [rf('a'), rf('b')],
    );
    expect(plan.toDownload, isEmpty);
    expect(plan.peerMissing, 0);
    expect(plan.isEmpty, isTrue);
  });

  test('计划保留对端给的文件名与大小(下载时要用)', () {
    final plan = planFileSync(
      mirroredTrackFps: {'a'},
      localFps: <String>{},
      remote: [rf('a', name: '及时雨.mp3', size: 8421376)],
    );
    expect(plan.toDownload.single.name, '及时雨.mp3');
    expect(plan.toDownload.single.size, 8421376);
  });
}
