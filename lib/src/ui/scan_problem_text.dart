import 'package:flutter/widgets.dart';

import '../../l10n/app_localizations.dart';
import '../library/scanner.dart';

/// 把扫描问题渲染成当前语言的一行文案。
String scanProblemText(BuildContext context, ScanProblem p) {
  final l10n = AppLocalizations.of(context)!;
  return switch (p) {
    RootUnreachable(:final path) => l10n.problemRootUnreachable(path),
    FileFailed(:final path, :final error) => l10n.problemFileFailed(
      path,
      error,
    ),
    BatchWriteFailed(:final count, :final error) =>
      l10n.problemBatchWriteFailed(count, error),
  };
}
