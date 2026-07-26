import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openmusic/src/library/scanner.dart';
import 'package:openmusic/src/ui/scan_problem_text.dart';

import 'helpers/pump.dart';

void main() {
  testWidgets('三种问题在中英 locale 下都渲染成对应语言', (tester) async {
    const problems = <ScanProblem>[
      RootUnreachable('/music'),
      FileFailed('/music/a.mp3', 'boom'),
      BatchWriteFailed(7, 'db locked'),
    ];

    late List<String> zh;
    await tester.pumpWidget(
      localizedApp(
        Builder(
          builder: (c) {
            zh = problems.map((p) => scanProblemText(c, p)).toList();
            return const SizedBox();
          },
        ),
      ),
    );
    await tester.pump();

    expect(zh[0], contains('/music'));
    expect(zh[0], contains('不可达'));
    expect(zh[1], contains('a.mp3'));
    expect(zh[1], contains('boom'));
    expect(zh[2], contains('7'));

    late List<String> en;
    await tester.pumpWidget(
      localizedApp(
        Builder(
          builder: (c) {
            en = problems.map((p) => scanProblemText(c, p)).toList();
            return const SizedBox();
          },
        ),
        locale: const Locale('en'),
      ),
    );
    await tester.pump();

    expect(en[0], contains('unreachable'));
    expect(en[2], contains('Batch write failed'));
  });
}
