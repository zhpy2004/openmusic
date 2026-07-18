import 'package:drift/drift.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openmusic/src/app/providers.dart';
import 'package:openmusic/src/data/database.dart';
import 'package:openmusic/src/ui/library_screen.dart';

import 'helpers/db.dart';
import 'helpers/fakes.dart';

void main() {
  late AppDatabase db;
  late FakeAudioEngine engine;

  setUp(() async {
    db = AppDatabase(testExecutor());
    engine = FakeAudioEngine();
    await db.upsertTrack(
      TracksCompanion.insert(
        path: '/m/a.mp3',
        fingerprint: 'fp1',
        title: 'Alpha',
        artist: const Value('Artist A'),
        sizeBytes: 1,
        mtimeMs: 1,
      ),
    );
    await db.upsertTrack(
      TracksCompanion.insert(
        path: '/m/b.mp3',
        fingerprint: 'fp2',
        title: 'Beta',
        artist: const Value('Artist B'),
        sizeBytes: 1,
        mtimeMs: 1,
      ),
    );
  });
  tearDown(() => db.close());

  Widget app() => ProviderScope(
    overrides: [
      databaseProvider.overrideWithValue(db),
      audioEngineProvider.overrideWithValue(engine),
    ],
    child: const MaterialApp(home: LibraryScreen()),
  );

  testWidgets('列表展示曲目标题与歌手', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect(find.text('Alpha'), findsOneWidget);
    expect(find.text('Artist B'), findsOneWidget);
  });

  testWidgets('点击曲目 → 引擎收到整队列并从该曲开始', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Beta'));
    await tester.pumpAndSettle();
    expect(engine.calls, contains('setQueue(2, start:1, play:true)'));
  });

  testWidgets('搜索过滤列表', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Alp');
    await tester.pumpAndSettle();
    expect(find.text('Alpha'), findsOneWidget);
    expect(find.text('Beta'), findsNothing);
  });
}
