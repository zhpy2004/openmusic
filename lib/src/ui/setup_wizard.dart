import 'dart:async';

import 'package:flutter/material.dart';

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
  final Future<void> Function() onAddFolder;
  final Future<void> Function() onScan;
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('建库向导'),
        actions: [
          if (_step < 4)
            TextButton(onPressed: widget.onDismiss, child: const Text('跳过')),
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

  Widget _welcome(BuildContext context) => Column(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      const Icon(Icons.library_music, size: 72),
      const SizedBox(height: 16),
      Text('欢迎使用 OpenMusic', style: Theme.of(context).textTheme.headlineSmall),
      const SizedBox(height: 8),
      const Text('3 步建好曲库:选文件夹 → 扫描 → 补全封面/歌词', textAlign: TextAlign.center),
      const SizedBox(height: 24),
      FilledButton(
        onPressed: () => setState(() => _step = 1),
        child: const Text('开始'),
      ),
    ],
  );

  Widget _pickFolder(BuildContext context) => Column(
    children: [
      Text('选择音乐文件夹', style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 12),
      Expanded(
        child: widget.roots.isEmpty
            ? const Center(child: Text('还没有文件夹,点下面添加'))
            : ListView(
                children: [
                  for (final r in widget.roots)
                    ListTile(leading: const Icon(Icons.folder), title: Text(r)),
                ],
              ),
      ),
      OutlinedButton.icon(
        onPressed: () async => widget.onAddFolder(),
        icon: const Icon(Icons.add),
        label: const Text('添加文件夹…'),
      ),
      const SizedBox(height: 12),
      FilledButton(
        onPressed: widget.roots.isEmpty
            ? null
            : () => setState(() => _step = 2),
        child: const Text('下一步'),
      ),
    ],
  );

  Widget _scan(BuildContext context) => Column(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      Text('扫描曲库', style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 16),
      if (_scanning) ...[
        const CircularProgressIndicator(),
        const SizedBox(height: 8),
        Text(widget.scanStatus ?? '扫描中…'),
      ] else
        FilledButton(
          onPressed: () async {
            setState(() => _scanning = true);
            await widget.onScan();
            if (mounted) {
              setState(() {
                _scanning = false;
                _step = 3;
              });
            }
          },
          child: const Text('开始扫描'),
        ),
    ],
  );

  Widget _batch(BuildContext context) => Column(
    children: [
      Text('补全封面/歌词', style: Theme.of(context).textTheme.titleLarge),
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
        child: const Text('完成'),
      ),
      TextButton(
        onPressed: () => setState(() => _step = 4),
        child: const Text('跳过此步'),
      ),
    ],
  );

  Widget _done(BuildContext context) => Column(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      const Icon(Icons.check_circle, size: 72),
      const SizedBox(height: 16),
      Text('建库完成', style: Theme.of(context).textTheme.headlineSmall),
      const SizedBox(height: 24),
      FilledButton(onPressed: widget.onFinish, child: const Text('进入曲库')),
    ],
  );
}
