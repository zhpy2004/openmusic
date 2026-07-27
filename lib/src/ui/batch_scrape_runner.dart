import 'dart:async';

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../scraper/batch_scraper_service.dart';

/// 订阅一条 BatchProgress 流,渲染进度条 + 当前曲名 + 计数 + 取消,
/// 收到 finished 事件时回调 onFinished 并显示小结。UI 无状态耦合,便于测试:
/// 由调用方(设置/向导)构造好 progressStream 传入。
class BatchScrapeRunner extends StatefulWidget {
  const BatchScrapeRunner({
    super.key,
    required this.progressStream,
    required this.onFinished,
    this.onCancel,
  });

  final Stream<BatchProgress> progressStream;
  final ValueChanged<BatchProgress> onFinished;
  final VoidCallback? onCancel;

  @override
  State<BatchScrapeRunner> createState() => _BatchScrapeRunnerState();
}

class _BatchScrapeRunnerState extends State<BatchScrapeRunner> {
  StreamSubscription<BatchProgress>? _sub;
  BatchProgress? _p;

  @override
  void initState() {
    super.initState();
    _sub = widget.progressStream.listen((p) {
      setState(() => _p = p);
      if (p.finished) widget.onFinished(p);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final p = _p;
    if (p == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (p.finished) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            p.total == 0
                ? l10n.batchNothingToFill
                : l10n.batchDone(
                    p.appliedCovers,
                    p.appliedLyrics,
                    p.skippedNoMatch,
                  ),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
      );
    }
    final frac = p.total == 0 ? 0.0 : p.done / p.total;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(l10n.batchProgress(p.done, p.total)),
          const SizedBox(height: 8),
          LinearProgressIndicator(value: frac),
          const SizedBox(height: 8),
          Text(
            p.currentTitle ?? '',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          Text(
            l10n.batchFilledSoFar(p.appliedCovers, p.appliedLyrics),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (widget.onCancel != null)
            TextButton(onPressed: widget.onCancel, child: Text(l10n.cancel)),
        ],
      ),
    );
  }
}
