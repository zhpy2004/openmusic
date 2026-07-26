import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openmusic/l10n/app_localizations.dart';

void main() {
  testWidgets('中英两种 locale 都能取到文案,且内容不同', (tester) async {
    late AppLocalizations zh;
    late AppLocalizations en;

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh'),
        home: Builder(
          builder: (c) {
            zh = AppLocalizations.of(c)!;
            return const SizedBox();
          },
        ),
      ),
    );
    await tester.pump();

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: Builder(
          builder: (c) {
            en = AppLocalizations.of(c)!;
            return const SizedBox();
          },
        ),
      ),
    );
    await tester.pump();

    expect(zh.tabLibrary, '曲库');
    expect(en.tabLibrary, 'Library');
    expect(zh.scanning(3, 10), contains('3/10'));
    expect(en.scanning(3, 10), contains('3/10'));
    // 复数:英文单复数必须正确
    expect(en.problemFiles(1), '1 problem file');
    expect(en.problemFiles(5), '5 problem files');
  });
}
