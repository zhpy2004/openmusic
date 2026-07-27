import 'dart:async';

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../library/library_setup.dart';
import '../scraper/batch_scraper_service.dart';
import 'batch_scrape_runner.dart';

/// 首启建库向导(5 步)。所有副作用通过回调注入,便于测试与复用:
/// - roots:当前扫描根(由调用方 watch 传入,决定"选文件夹"步能否下一步)
/// - onAddFolder / onScan:复用 library_setup 的加文件夹 / 扫描(调用方接线)
/// - batchStreamBuilder:给定取消判定,返回批量进度流(调用方注入 service+全库)
/// - onDismiss:跳过;onFinish:完成
class SetupWizard extends StatefulWidget {
  const SetupWizard({
    super.key,
    required this.roots,
    required this.onAddFolder,
    required this.onScan,
    required this.batchStreamBuilder,
    required this.onDismiss,
    required this.onFinish,
    this.scanStatus,
  });

  final List<String> roots;

  /// 加文件夹。**返回结果必须用起来** —— 早先丢弃返回值,Android 上权限被拒
  /// 时向导毫无提示,用户只看到"加了但没加上"(烟测发现)。
  final Future<AddFolderResult> Function() onAddFolder;

  /// 跑扫描,返回扫完后曲库里的曲目总数(用于告诉用户"扫到了几首")。
  final Future<int> Function() onScan;
  final Stream<BatchProgress> Function(bool Function() shouldCancel)
  batchStreamBuilder;
  final VoidCallback onDismiss;
  final VoidCallback onFinish;

  /// 扫描步的实时状态文案(可选;由调用方从 scanProgressProvider 传入)。
  final String? scanStatus;

  @override
  State<SetupWizard> createState() => _SetupWizardState();
}

class _SetupWizardState extends State<SetupWizard> {
  int _step = 0; // 0 欢迎 1 选文件夹 2 扫描 3 批量 4 完成
  bool _scanning = false;
  bool _cancelBatch = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.wizardTitle),
        actions: [
          if (_step < 4)
            TextButton(onPressed: widget.onDismiss, child: Text(l10n.skip)),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: switch (_step) {
            0 => _welcome(context),
            1 => _pickFolder(context),
            2 => _scan(context),
            3 => _batch(context),
            _ => _done(context),
          },
        ),
      ),
    );
  }

  Widget _welcome(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.library_music, size: 72),
        const SizedBox(height: 16),
        Text(
          l10n.wizardWelcome,
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 8),
        Text(l10n.wizardIntro, textAlign: TextAlign.center),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: () => setState(() => _step = 1),
          child: Text(l10n.start),
        ),
      ],
    );
  }

  Widget _pickFolder(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      children: [
        Text(
          l10n.wizardPickFolder,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 12),
        Expanded(
          child: widget.roots.isEmpty
              ? Center(child: Text(l10n.wizardNoFolders))
              : ListView(
                  children: [
                    for (final r in widget.roots)
                      ListTile(
                        leading: const Icon(Icons.folder),
                        title: Text(r),
                      ),
                  ],
                ),
        ),
        OutlinedButton.icon(
          onPressed: () async {
            // 先取 messenger:await 之后再用传进来的 context 会触发
            // use_build_context_synchronously(State.mounted 管不住它)。
            final messenger = ScaffoldMessenger.of(context);
            final result = await widget.onAddFolder();
            if (result == AddFolderResult.permissionDenied) {
              messenger.showSnackBar(
                SnackBar(content: Text(l10n.needAudioPermission)),
              );
            }
          },
          icon: const Icon(Icons.add),
          label: Text(l10n.addFolder),
        ),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: widget.roots.isEmpty
              ? null
              : () => setState(() => _step = 2),
          child: Text(l10n.next),
        ),
      ],
    );
  }

  Widget _scan(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          l10n.wizardScanTitle,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 16),
        if (_scanning) ...[
          const CircularProgressIndicator(),
          const SizedBox(height: 8),
          Text(widget.scanStatus ?? l10n.wizardScanning),
        ] else
          FilledButton(
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              setState(() => _scanning = true);
              final found = await widget.onScan();
              if (!mounted) return;
              setState(() {
                _scanning = false;
                _step = 3;
              });
              // 扫到 0 首要说出来:选了个没有音乐的文件夹时,原来会一声不响
              // 走到下一步,用户完全不知道发生了什么(烟测发现)。
              messenger.showSnackBar(
                SnackBar(content: Text(l10n.wizardScanFound(found))),
              );
            },
            child: Text(l10n.wizardStartScan),
          ),
      ],
    );
  }

  Widget _batch(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      children: [
        Text(
          l10n.wizardFillTitle,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        Expanded(
          child: BatchScrapeRunner(
            progressStream: widget.batchStreamBuilder(() => _cancelBatch),
            onFinished: (_) {},
            onCancel: () => setState(() => _cancelBatch = true),
          ),
        ),
        FilledButton(
          onPressed: () => setState(() => _step = 4),
          child: Text(l10n.finish),
        ),
        TextButton(
          onPressed: () => setState(() => _step = 4),
          child: Text(l10n.wizardSkipStep),
        ),
      ],
    );
  }

  Widget _done(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.check_circle, size: 72),
        const SizedBox(height: 16),
        Text(
          l10n.wizardComplete,
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: widget.onFinish,
          child: Text(l10n.wizardEnterLibrary),
        ),
      ],
    );
  }
}
