import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../app/providers.dart';

/// 「从配对设备获取」这一首。歌单详情页与收藏页共用。
///
/// 依次试每台**在线且有这个指纹**的已配对设备 —— 自用场景通常只有一台,
/// 但代码不假设只有一台。
Future<void> fetchSingleTrack(
  BuildContext context,
  WidgetRef ref,
  String fp,
) async {
  final l10n = AppLocalizations.of(context)!;
  final messenger = ScaffoldMessenger.of(context);
  final controller = ref.read(syncControllerProvider);
  final client = controller.client;
  final peers = ref.read(pairedPeersProvider).value ?? const [];
  if (client == null || peers.isEmpty) {
    messenger.showSnackBar(SnackBar(content: Text(l10n.syncFetchFailed)));
    return;
  }

  for (final peer in peers) {
    if (controller.addressOf(peer.deviceId) == null) continue; // 不在线
    try {
      final manifest = await client.fetchFileManifest(
        peerDeviceId: peer.deviceId,
      );
      final match = manifest.where((f) => f.fp == fp).toList();
      if (match.isEmpty) continue; // 这台没有,试下一台
      final result = await controller.syncFilesFor(peer.deviceId, match);
      if (result.downloaded > 0) return; // 成功,直接结束
    } catch (e) {
      debugPrint('[sync] 从 ${peer.deviceName} 取 $fp 出错: $e');
      continue; // 这台不行就试下一台
    }
  }
  messenger.showSnackBar(SnackBar(content: Text(l10n.syncFetchFailed)));
}
