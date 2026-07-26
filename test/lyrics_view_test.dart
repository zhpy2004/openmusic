import 'dart:async';

import 'package:flutter/gestures.dart';
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
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: LyricsView(
          lyrics: lyrics,
          positionStream: stream,
          initialPosition: initial,
          onSeek: onSeek,
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('synced:焦点行(=当前播放行)显示其时间戳', (tester) async {
    final ctrl = StreamController<Duration>.broadcast();
    addTearDown(ctrl.close);
    await _pump(
      tester,
      lyrics: _synced(),
      stream: ctrl.stream,
      initial: const Duration(seconds: 12), // => line1
      onSeek: (_) {},
    );
    expect(find.text('0:10'), findsOneWidget); // 仅焦点行显示时间戳
  });

  testWidgets('synced:点焦点行 ▶ 触发 onSeek(该行时间)', (tester) async {
    final ctrl = StreamController<Duration>.broadcast();
    addTearDown(ctrl.close);
    Duration? seeked;
    await _pump(
      tester,
      lyrics: _synced(),
      stream: ctrl.stream,
      initial: const Duration(seconds: 12), // => line1 (10s)
      onSeek: (d) => seeked = d,
    );
    await tester.tap(find.byIcon(Icons.play_arrow));
    await tester.pump();
    expect(seeked, const Duration(seconds: 10));
  });

  testWidgets('synced:进度推进使焦点跟随移动', (tester) async {
    final ctrl = StreamController<Duration>.broadcast();
    addTearDown(ctrl.close);
    await _pump(
      tester,
      lyrics: _synced(),
      stream: ctrl.stream,
      initial: Duration.zero, // => line0
      onSeek: (_) {},
    );
    expect(find.text('0:00'), findsOneWidget);
    ctrl.add(const Duration(seconds: 22)); // => line2
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400)); // 让自动滚动动画收尾
    expect(find.text('0:20'), findsOneWidget);
  });

  testWidgets('纯文本:无时间轴提示,无 ▶,不显示时间戳', (tester) async {
    final ctrl = StreamController<Duration>.broadcast();
    addTearDown(ctrl.close);
    await _pump(
      tester,
      lyrics: const Lyrics([
        LrcLine(Duration.zero, 'p1'),
        LrcLine(Duration.zero, 'p2'),
      ], false),
      stream: ctrl.stream,
      initial: Duration.zero,
      onSeek: (_) {},
    );
    expect(find.text('无时间轴歌词'), findsOneWidget);
    expect(find.byIcon(Icons.play_arrow), findsNothing);
    expect(find.text('p1'), findsOneWidget);
  });

  testWidgets('手动滑动:焦点移离当前行,约 4 秒后自动恢复到当前行', (tester) async {
    // 足够长的列表,确保拖动能把视口中心移出当前播放行。
    final lines = [
      for (var i = 0; i < 30; i++) LrcLine(Duration(seconds: i * 10), 'L$i'),
    ];
    final ctrl = StreamController<Duration>.broadcast();
    addTearDown(ctrl.close);
    await _pump(
      tester,
      lyrics: Lyrics(lines, true),
      stream: ctrl.stream,
      initial: const Duration(seconds: 150), // => L15,时间戳 2:30
      onSeek: (_) {},
    );
    // 初始:焦点在 L15,仅焦点行显示时间戳。
    expect(find.text('2:30'), findsOneWidget);
    // 大幅上滑进入浏览态:焦点移到别的行 => L15 不再是焦点 => 2:30 消失。
    await tester.drag(
      find.byType(ScrollablePositionedList),
      const Offset(0, -400),
    );
    await tester.pump();
    expect(find.text('2:30'), findsNothing);
    // 约 4 秒后自动恢复,重新居中当前播放行 L15 => 2:30 复现。
    await tester.pump(const Duration(seconds: 5));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('2:30'), findsOneWidget);
  });

  testWidgets('浏览态中点焦点框 ▶ => seek 并立即退出浏览(不等 4 秒)', (tester) async {
    final lines = [
      for (var i = 0; i < 30; i++) LrcLine(Duration(seconds: i * 10), 'L$i'),
    ];
    final ctrl = StreamController<Duration>.broadcast();
    addTearDown(ctrl.close);
    Duration? seeked;
    await _pump(
      tester,
      lyrics: Lyrics(lines, true),
      stream: ctrl.stream,
      initial: const Duration(seconds: 150), // => L15,时间戳 2:30
      onSeek: (d) => seeked = d,
    );
    // 上滑进入浏览态:焦点框移到视口中心的行
    await tester.drag(
      find.byType(ScrollablePositionedList),
      const Offset(0, -400),
    );
    await tester.pump(); // 帧1:布局更新 itemPositions → 焦点 setState
    await tester.pump(); // 帧2:以中心行焦点重建
    expect(find.text('2:30'), findsNothing); // 焦点已离开播放行
    // 点焦点框的 ▶:seek 到该行,并立即退出浏览、该行成为焦点
    await tester.tap(find.byIcon(Icons.play_arrow));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400)); // 居中动画
    expect(seeked, isNotNull);
    // 焦点框立即落在 seek 的那一行(显示其时间戳),无需等 4 秒恢复
    final m = seeked!.inMinutes, s = seeked!.inSeconds % 60;
    expect(find.text('$m:${s.toString().padLeft(2, '0')}'), findsOneWidget);
  });

  testWidgets('桌面滚轮滚动进入浏览态:焦点框跟随视口中心,播放行保持全亮', (tester) async {
    final lines = [
      for (var i = 0; i < 30; i++) LrcLine(Duration(seconds: i * 10), 'L$i'),
    ];
    final ctrl = StreamController<Duration>.broadcast();
    addTearDown(ctrl.close);
    await _pump(
      tester,
      lyrics: Lyrics(lines, true),
      stream: ctrl.stream,
      initial: const Duration(seconds: 150), // 播放行 L15,时间戳 2:30
      onSeek: (_) {},
    );
    expect(find.text('2:30'), findsOneWidget);
    // 模拟鼠标滚轮向下滚(桌面浏览方式;不产生带 dragDetails 的 ScrollStart)
    final mouse = TestPointer(1, PointerDeviceKind.mouse);
    final center = tester.getCenter(find.byType(ScrollablePositionedList));
    await tester.sendEventToBinding(mouse.hover(center));
    await tester.sendEventToBinding(mouse.scroll(const Offset(0, 200)));
    await tester.pump(); // 帧1:应用滚动偏移,布局阶段更新 itemPositions→焦点 setState
    await tester.pump(); // 帧2:以新焦点重建行
    // 浏览态生效:焦点框离开播放行(2:30 消失),落在中心行(仍有一个 ▶ 框)
    expect(find.text('2:30'), findsNothing);
    expect(find.byIcon(Icons.play_arrow), findsOneWidget);
    // 播放行 L15 仍在视口内且保持全亮(非 0.4 淡化),滚开也能看到唱到哪句
    final style = tester.widget<Text>(find.text('L15')).style;
    expect(style?.color?.a, closeTo(1.0, 0.01));
  });

  testWidgets('浏览可达头尾:第一句与最后一句都能滚到焦点位', (tester) async {
    final lines = [
      for (var i = 0; i < 12; i++) LrcLine(Duration(seconds: i * 10), 'L$i'),
    ];
    final ctrl = StreamController<Duration>.broadcast();
    addTearDown(ctrl.close);
    await _pump(
      tester,
      lyrics: Lyrics(lines, true),
      stream: ctrl.stream,
      initial: const Duration(seconds: 60), // 播放行 L6
      onSeek: (_) {},
    );
    // 向下拉到底(看开头):第一句 L0 应能进入焦点位(显示 0:00)
    await tester.drag(
      find.byType(ScrollablePositionedList),
      const Offset(0, 2000),
    );
    await tester.pump();
    await tester.pump();
    expect(find.text('0:00'), findsOneWidget);
    // 向上拉到底(看结尾):最后一句 L11 应能进入焦点位(显示 1:50)
    await tester.drag(
      find.byType(ScrollablePositionedList),
      const Offset(0, -4000),
    );
    await tester.pump();
    await tester.pump();
    expect(find.text('1:50'), findsOneWidget);
  });
}
