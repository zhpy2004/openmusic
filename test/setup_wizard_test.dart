import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openmusic/src/app/app.dart';
import 'package:openmusic/src/app/providers.dart';
import 'package:openmusic/src/data/database.dart';
import 'package:openmusic/src/library/library_setup.dart';
import 'package:openmusic/src/scraper/batch_scraper_service.dart';
import 'package:openmusic/src/ui/batch_scrape_runner.dart';
import 'package:openmusic/src/ui/setup_wizard.dart';

import 'helpers/db.dart';
import 'helpers/fakes.dart';
import 'helpers/pump.dart';

BatchProgress prog({
  int done = 0,
  int total = 3,
  String? title,
  int covers = 0,
  int lyrics = 0,
  int skipped = 0,
  bool finished = false,
}) => BatchProgress(
  done: done,
  total: total,
  currentTitle: title,
  appliedCovers: covers,
  appliedLyrics: lyrics,
  skippedNoMatch: skipped,
  finished: finished,
);

void main() {
  testWidgets('进行中显示 done/total 与当前曲名;完成回调带最终小结', (tester) async {
    final ctrl = StreamController<BatchProgress>();
    addTearDown(ctrl.close);
    BatchProgress? summary;

    await tester.pumpWidget(
      localizedApp(
        Scaffold(
          body: BatchScrapeRunner(
            progressStream: ctrl.stream,
            onFinished: (s) => summary = s,
          ),
        ),
      ),
    );

    ctrl.add(prog(done: 1, total: 3, title: '浮夸', covers: 1));
    await tester.pump();
    expect(find.textContaining('1/3'), findsOneWidget);
    expect(find.textContaining('浮夸'), findsOneWidget);

    ctrl.add(prog(done: 3, total: 3, covers: 2, lyrics: 1, finished: true));
    await tester.pump();
    expect(summary, isNotNull);
    expect(summary!.appliedCovers, 2);
    expect(summary!.appliedLyrics, 1);
    // 完成后显示小结文案
    expect(find.textContaining('封面'), findsWidgets);
  });

  testWidgets('点取消触发 onCancel', (tester) async {
    final ctrl = StreamController<BatchProgress>();
    addTearDown(ctrl.close);
    var cancelled = false;

    await tester.pumpWidget(
      localizedApp(
        Scaffold(
          body: BatchScrapeRunner(
            progressStream: ctrl.stream,
            onFinished: (_) {},
            onCancel: () => cancelled = true,
          ),
        ),
      ),
    );
    ctrl.add(prog(done: 1, total: 3));
    await tester.pump();
    await tester.tap(find.text('取消'));
    await tester.pump();
    expect(cancelled, true);
  });

  testWidgets('欢迎页:点开始进选文件夹步;点跳过触发 onDismiss', (tester) async {
    var dismissed = false;
    await tester.pumpWidget(
      localizedApp(
        SetupWizard(
          roots: const [],
          onAddFolder: () async => AddFolderResult.added,
          onScan: () async => 0,
          batchStreamBuilder: (_) => const Stream.empty(),
          onDismiss: () => dismissed = true,
          onFinish: () {},
        ),
      ),
    );
    expect(find.text('欢迎使用 OpenMusic'), findsOneWidget);
    await tester.tap(find.text('跳过'));
    await tester.pump();
    expect(dismissed, true);
  });

  // 真实流程:空着进向导 → 加文件夹 → roots 变非空 → 下一步可用。
  // (不能"挂载时就带着根"来测:那种情况向导会直接跳到扫描步,见下一条。)
  testWidgets('选文件夹步:加了根之后下一步可用', (tester) async {
    Widget wizard(List<String> roots) => localizedApp(
      SetupWizard(
        roots: roots,
        onAddFolder: () async => AddFolderResult.added,
        onScan: () async => 0,
        batchStreamBuilder: (_) => const Stream.empty(),
        onDismiss: () {},
        onFinish: () {},
      ),
    );

    await tester.pumpWidget(wizard(const []));
    await tester.tap(find.text('开始'));
    await tester.pump();
    expect(find.text('下一步'), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.widgetWithText(FilledButton, '下一步')).onPressed,
      isNull, // 没有根:下一步禁用
    );

    await tester.pumpWidget(wizard(const ['/music'])); // 加好了根
    await tester.pump();
    expect(find.text('/music'), findsOneWidget); // 列出已加的根
    expect(
      tester.widget<FilledButton>(find.widgetWithText(FilledButton, '下一步')).onPressed,
      isNotNull,
    );
  });

  testWidgets('已有扫描根时挂载:直接从扫描步开始,不再问选文件夹', (tester) async {
    await tester.pumpWidget(
      localizedApp(
        SetupWizard(
          roots: const ['/music'],
          onAddFolder: () async => AddFolderResult.added,
          onScan: () async => 0,
          batchStreamBuilder: (_) => const Stream.empty(),
          onDismiss: () {},
          onFinish: () {},
        ),
      ),
    );
    expect(find.text('扫描曲库'), findsOneWidget);
    expect(find.text('开始扫描'), findsOneWidget);
    expect(find.text('欢迎使用 OpenMusic'), findsNothing);
  });

  testWidgets('扫描根为空 => 显示向导欢迎页', (tester) async {
    final db = AppDatabase(testExecutor());
    addTearDown(db.close);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          scanRootsProvider.overrideWith(
            (ref) => Stream.value(const <String>[]),
          ),
        ],
        child: const OpenMusicApp(),
      ),
    );
    await tester.pump();
    // OpenMusicApp 自带 MaterialApp,测试里无法从外部注入 locale;
    // 测试环境默认英文,故断言英文文案。
    expect(find.text('Welcome to OpenMusic'), findsOneWidget);
  });

  testWidgets('已有扫描根 => 直接显示曲库(无向导)', (tester) async {
    final db = AppDatabase(testExecutor());
    addTearDown(db.close);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          // 首页会挂 NowPlayingBar → playbackControllerProvider → audioEngineProvider,
          // 默认抛 UnimplementedError,必须注入假引擎。
          audioEngineProvider.overrideWithValue(FakeAudioEngine()),
          scanRootsProvider.overrideWith(
            (ref) => Stream.value(const ['/music']),
          ),
        ],
        child: const OpenMusicApp(),
      ),
    );
    await tester.pump();
    expect(find.text('Welcome to OpenMusic'), findsNothing);
    expect(find.text('Library'), findsWidgets); // 导航项(宽屏 NavigationRail 标签)
  });

  testWidgets('向导中新增文件夹(roots 变非空)不被踢回曲库', (tester) async {
    final db = AppDatabase(testExecutor());
    addTearDown(db.close);
    final rootsCtrl = StreamController<List<String>>();
    addTearDown(rootsCtrl.close);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          audioEngineProvider.overrideWithValue(FakeAudioEngine()),
          scanRootsProvider.overrideWith((ref) => rootsCtrl.stream),
        ],
        child: const OpenMusicApp(),
      ),
    );
    rootsCtrl.add(const <String>[]); // 空 => 进向导
    await tester.pump();
    expect(find.text('Welcome to OpenMusic'), findsOneWidget);
    rootsCtrl.add(const ['/music']); // 向导中新增文件夹
    await tester.pump();
    expect(find.text('Welcome to OpenMusic'), findsOneWidget); // 仍在向导,没被踢回
  });
}
