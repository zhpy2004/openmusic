import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openmusic/src/lyrics/lrc.dart';
import 'package:openmusic/src/ui/lyrics_view.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

Lyrics _synced() => const Lyrics([
      LrcLine(Duration(seconds: 0), 'line0'),
      LrcLine(Duration(seconds: 10), 'line1'),
      LrcLine(Duration(seconds: 20), 'line2'),
    ], true);

Future<void> _pump(
  WidgetTester tester, {
  required Lyrics lyrics,
  required Stream<Duration> stream,
  required Duration initial,
  required ValueChanged<Duration> onSeek,
}) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: LyricsView(
        lyrics: lyrics,
        positionStream: stream,
        initialPosition: initial,
        onSeek: onSeek,
      ),
    ),
  ));
  await tester.pump();
}

void main() {
  testWidgets('synced:焦点行(=当前播放行)显示其时间戳', (tester) async {
    final ctrl = StreamController<Duration>.broadcast();
    addTearDown(ctrl.close);
    await _pump(tester,
        lyrics: _synced(),
        stream: ctrl.stream,
        initial: const Duration(seconds: 12), // => line1
        onSeek: (_) {});
    expect(find.text('0:10'), findsOneWidget); // 仅焦点行显示时间戳
  });

  testWidgets('synced:点焦点行 ▶ 触发 onSeek(该行时间)', (tester) async {
    final ctrl = StreamController<Duration>.broadcast();
    addTearDown(ctrl.close);
    Duration? seeked;
    await _pump(tester,
        lyrics: _synced(),
        stream: ctrl.stream,
        initial: const Duration(seconds: 12), // => line1 (10s)
        onSeek: (d) => seeked = d);
    await tester.tap(find.byIcon(Icons.play_arrow));
    await tester.pump();
    expect(seeked, const Duration(seconds: 10));
  });

  testWidgets('synced:进度推进使焦点跟随移动', (tester) async {
    final ctrl = StreamController<Duration>.broadcast();
    addTearDown(ctrl.close);
    await _pump(tester,
        lyrics: _synced(),
        stream: ctrl.stream,
        initial: Duration.zero, // => line0
        onSeek: (_) {});
    expect(find.text('0:00'), findsOneWidget);
    ctrl.add(const Duration(seconds: 22)); // => line2
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400)); // 让自动滚动动画收尾
    expect(find.text('0:20'), findsOneWidget);
  });

  testWidgets('纯文本:无时间轴提示,无 ▶,不显示时间戳', (tester) async {
    final ctrl = StreamController<Duration>.broadcast();
    addTearDown(ctrl.close);
    await _pump(tester,
        lyrics: const Lyrics(
            [LrcLine(Duration.zero, 'p1'), LrcLine(Duration.zero, 'p2')],
            false),
        stream: ctrl.stream,
        initial: Duration.zero,
        onSeek: (_) {});
    expect(find.text('无时间轴歌词'), findsOneWidget);
    expect(find.byIcon(Icons.play_arrow), findsNothing);
    expect(find.text('p1'), findsOneWidget);
  });

  testWidgets('手动滑动:焦点移离当前行,约 4 秒后自动恢复到当前行', (tester) async {
    // 足够长的列表,确保拖动能把视口中心移出当前播放行。
    final lines = [
      for (var i = 0; i < 30; i++)
        LrcLine(Duration(seconds: i * 10), 'L$i'),
    ];
    final ctrl = StreamController<Duration>.broadcast();
    addTearDown(ctrl.close);
    await _pump(tester,
        lyrics: Lyrics(lines, true),
        stream: ctrl.stream,
        initial: const Duration(seconds: 150), // => L15,时间戳 2:30
        onSeek: (_) {});
    // 初始:焦点在 L15,仅焦点行显示时间戳。
    expect(find.text('2:30'), findsOneWidget);
    // 大幅上滑进入浏览态:焦点移到别的行 => L15 不再是焦点 => 2:30 消失。
    await tester.drag(
        find.byType(ScrollablePositionedList), const Offset(0, -400));
    await tester.pump();
    expect(find.text('2:30'), findsNothing);
    // 约 4 秒后自动恢复,重新居中当前播放行 L15 => 2:30 复现。
    await tester.pump(const Duration(seconds: 5));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('2:30'), findsOneWidget);
  });
}
