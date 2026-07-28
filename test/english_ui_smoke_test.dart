import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openmusic/src/app/providers.dart';
import 'package:openmusic/src/data/database.dart';
import 'package:openmusic/src/library/library_setup.dart';
import 'package:openmusic/src/ui/favorites_screen.dart';
import 'package:openmusic/src/ui/setup_wizard.dart';

import 'helpers/db.dart';
import 'helpers/fakes.dart';
import 'helpers/pump.dart';

void main() {
  testWidgets('英文 locale:收藏页标题与空态为英文', (tester) async {
    final db = AppDatabase(testExecutor());
    addTearDown(db.close);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          audioEngineProvider.overrideWithValue(FakeAudioEngine()),
        ],
        child: localizedApp(
          const FavoritesScreen(),
          locale: const Locale('en'),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Favorites'), findsOneWidget);
  });

  testWidgets('英文 locale:向导欢迎页为英文', (tester) async {
    await tester.pumpWidget(
      localizedApp(
        SetupWizard(
          roots: const [],
          onAddFolder: () async => AddFolderResult.added,
          onScan: () async => 0,
          batchStreamBuilder: (_) => const Stream.empty(),
          onDismiss: () {},
          onFinish: () {},
        ),
        locale: const Locale('en'),
      ),
    );
    await tester.pump();
    expect(find.text('Welcome to OpenMusic'), findsOneWidget);
    expect(find.text('Skip'), findsOneWidget);
    expect(find.text('Start'), findsOneWidget);
  });

  testWidgets('中文 locale:同一个向导显示中文', (tester) async {
    await tester.pumpWidget(
      localizedApp(
        SetupWizard(
          roots: const [],
          onAddFolder: () async => AddFolderResult.added,
          onScan: () async => 0,
          batchStreamBuilder: (_) => const Stream.empty(),
          onDismiss: () {},
          onFinish: () {},
        ),
      ),
    );
    await tester.pump();
    expect(find.text('欢迎使用 OpenMusic'), findsOneWidget);
    expect(find.text('跳过'), findsOneWidget);
  });
}
