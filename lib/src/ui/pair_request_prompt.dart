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
            // 用 bodyLarge(w400)而非 titleMedium(w500):设备名多是拉丁文、
            // 其余是中文,非常规字重更容易暴露字体回退差异。字体族本身已在
            // app.dart 为 Windows 钉死,这里只是不再自找麻烦。
            style: Theme.of(context).textTheme.bodyLarge,
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
