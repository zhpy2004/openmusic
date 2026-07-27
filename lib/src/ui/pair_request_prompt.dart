import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../sync/sync_server.dart';

/// 对方发起配对时给用户看的确认内容:大字 6 位码 + 一致/拒绝。
///
/// 抽成独立组件是因为它由 **App 根部的全局弹窗** 使用 —— 配对请求可能在用户
/// 正在听歌、翻歌单时到达,不能只在同步页里才看得见。
class PairRequestPrompt extends StatelessWidget {
  const PairRequestPrompt({
    super.key,
    required this.request,
    required this.onAccept,
    required this.onReject,
  });

  final PairRequest request;
  final VoidCallback onAccept;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return AlertDialog(
      title: Text(l10n.syncPairRequestTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            l10n.syncPairRequestFrom(request.deviceName),
            textAlign: TextAlign.center,
            // 明确用常规字重:Windows 上中文由回退字体渲染,若这里用 w500
            // (titleMedium 默认),拉丁文部分会明显比中文粗,同一行字重不一。
            style: Theme.of(
              context,
            ).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w400),
          ),
          const SizedBox(height: 12),
          Text(l10n.syncCompareCodes, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          Text(
            request.code,
            style: Theme.of(
              context,
            ).textTheme.displaySmall?.copyWith(letterSpacing: 8),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: onReject, child: Text(l10n.syncRejectPair)),
        FilledButton(onPressed: onAccept, child: Text(l10n.syncCodesMatch)),
      ],
    );
  }
}
