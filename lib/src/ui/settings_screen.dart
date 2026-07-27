import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../app/providers.dart';
import '../library/library_setup.dart';
import 'batch_scrape_runner.dart';
import 'scan_problem_text.dart';
import 'sync_screen.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  Future<void> _addFolder(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context)!;
    final result = await addScanFolder(ref.read(databaseProvider));
    if (result == AddFolderResult.permissionDenied && context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.needAudioPermission)));
    }
  }

  Future<void> _scan(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context)!;
    final notifier = ref.read(scanProgressProvider.notifier);
    final problemsNotifier = ref.read(lastScanProblemsProvider.notifier);
    try {
      await runLibraryScan(
        db: ref.read(databaseProvider),
        scanner: ref.read(scannerProvider),
        onProgress: (p) => notifier.state = p,
        onProblems: (probs) => problemsNotifier.state = probs,
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l10n.scanFailed('$e'))));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final rootsAsync = ref.watch(scanRootsProvider);
    final progress = ref.watch(scanProgressProvider);
    final lastProblems = ref.watch(lastScanProblemsProvider);

    return ListView(
      padding: const EdgeInsets.all(8),
      children: [
        Consumer(
          builder: (context, ref, _) {
            final pref = ref.watch(localePreferenceProvider).value ?? 'system';
            final l10n = AppLocalizations.of(context)!;
            return ListTile(
              leading: const Icon(Icons.language),
              title: Text(l10n.language),
              trailing: DropdownButton<String>(
                value: pref,
                onChanged: (v) {
                  if (v != null) {
                    ref.read(databaseProvider).setSetting(kLocalePrefKey, v);
                  }
                },
                items: [
                  DropdownMenuItem(
                    value: 'system',
                    child: Text(l10n.languageSystem),
                  ),
                  // 语言名按惯例用该语言自身书写,不随界面语言变化
                  const DropdownMenuItem(value: 'zh', child: Text('简体中文')),
                  const DropdownMenuItem(value: 'en', child: Text('English')),
                ],
              ),
            );
          },
        ),
        const Divider(),
        ListTile(
          title: Text(
            l10n.musicFolders,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
        ...?rootsAsync.value?.map(
          (root) => ListTile(
            leading: const Icon(Icons.folder),
            title: Text(root),
            trailing: IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: () => ref.read(databaseProvider).removeScanRoot(root),
            ),
          ),
        ),
        ListTile(
          leading: const Icon(Icons.add),
          title: Text(
            Platform.isAndroid ? l10n.addSystemMusicFolder : l10n.addFolder,
          ),
          onTap: () => _addFolder(context, ref),
        ),
        const Divider(),
        if (progress == null)
          ListTile(
            leading: const Icon(Icons.refresh),
            title: Text(l10n.scanLibrary),
            onTap: () => _scan(context, ref),
          )
        else
          ListTile(
            leading: const CircularProgressIndicator(),
            title: Text(l10n.scanning(progress.scanned, progress.total)),
            subtitle: Text(
              progress.currentPath ?? '',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        if (progress != null && progress.problems.isNotEmpty)
          ListTile(
            leading: const Icon(Icons.warning_amber),
            title: Text(l10n.problemFiles(progress.problems.length)),
          ),
        if (progress == null && lastProblems.isNotEmpty) ...[
          const Divider(),
          ListTile(
            leading: const Icon(Icons.warning_amber),
            title: Text(l10n.lastScanProblems(lastProblems.length)),
            trailing: TextButton(
              onPressed: () =>
                  ref.read(lastScanProblemsProvider.notifier).state = const [],
              child: Text(l10n.clear),
            ),
          ),
          ...lastProblems.map(
            (p) => ListTile(
              dense: true,
              leading: const Icon(Icons.error_outline, size: 20),
              title: Text(
                scanProblemText(context, p),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ),
        ],
        const Divider(),
        ListTile(
          leading: const Icon(Icons.auto_fix_high),
          title: Text(l10n.batchFill),
          subtitle: Text(l10n.batchFillSubtitle),
          onTap: () => _batchScrape(context, ref),
        ),
        const Divider(),
        ListTile(
          leading: const Icon(Icons.sync),
          title: Text(l10n.syncTitle),
          subtitle: Text(l10n.syncSubtitle),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => const SyncPermissionGate(child: SyncScreen()),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _batchScrape(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context)!;
    final db = ref.read(databaseProvider);
    final service = ref.read(batchScraperServiceProvider);
    final tracks = await db.watchTracks('').first; // 全库快照
    if (!context.mounted) return;
    var cancelled = false;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        content: BatchScrapeRunner(
          progressStream: service.run(tracks, shouldCancel: () => cancelled),
          onFinished: (_) {},
          onCancel: () {
            cancelled = true;
            Navigator.of(ctx).pop();
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(l10n.close),
          ),
        ],
      ),
    );
  }
}
