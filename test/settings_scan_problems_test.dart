import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openmusic/src/app/providers.dart';
import 'package:openmusic/src/data/database.dart';
import 'package:openmusic/src/ui/settings_screen.dart';
import 'package:path/path.dart' as p;

import 'helpers/db.dart';
import 'helpers/pump.dart';

void main() {
  late AppDatabase db;
  late String absentRoot;

  setUp(() async {
    db = AppDatabase(testExecutor());
    absentRoot = p.join(
      Directory.systemTemp.path,
      'openmusic_absent_scanroot_${DateTime.now().microsecondsSinceEpoch}',
    );
    // 确保该目录不存在——测试的是"不可达根"路径，不能真的创建它。
    await db.addScanRoot(absentRoot);
  });
  tearDown(() => db.close());

  Widget app() => ProviderScope(
    overrides: [databaseProvider.overrideWithValue(db)],
    child: localizedApp(const Scaffold(body: SettingsScreen())),
  );

  testWidgets('扫描结束后问题清单持久显示（不可达根）', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    await tester.tap(find.text('扫描曲库'));
    await tester.pump();
    // scan() 的 await 链（drift 查询/文件系统）跑在真实事件循环上，
    // AutomatedTestWidgetsFlutterBinding 的假时钟 pump(duration) 不会推进
    // 它——用 runAsync 让出到真实事件循环把它排空，再 pump 一帧看新状态。
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();

    expect(find.textContaining('不可达'), findsOneWidget);
    expect(find.textContaining('1 个问题'), findsOneWidget);
  });

  testWidgets('点击清除后持久问题区消失', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    await tester.tap(find.text('扫描曲库'));
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();

    expect(find.textContaining('不可达'), findsOneWidget);

    await tester.tap(find.text('清除'));
    await tester.pump();

    expect(find.textContaining('不可达'), findsNothing);
  });
}
