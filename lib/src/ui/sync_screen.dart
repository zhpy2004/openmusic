import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../l10n/app_localizations.dart';
import '../app/providers.dart';
import '../data/database.dart';
import '../sync/discovery.dart';
import '../sync/sync_client.dart';
import '../sync/sync_controller.dart';

/// Android 13+ 的 mDNS 发现需要 NEARBY_WIFI_DEVICES 运行时权限。
/// 非 Android 平台直接放行(桌面没有这个权限概念)。
///
/// 刻意做成 [SyncScreen] 之外的独立外壳:permission_handler 是插件,
/// 在 flutter_test 里调用会抛 MissingPluginException;分开后同步页的
/// widget 测试完全不碰它。
class SyncPermissionGate extends StatefulWidget {
  const SyncPermissionGate({super.key, required this.child});
  final Widget child;

  @override
  State<SyncPermissionGate> createState() => _SyncPermissionGateState();
}

class _SyncPermissionGateState extends State<SyncPermissionGate> {
  bool _granted = true;
  bool _asked = false;

  @override
  void initState() {
    super.initState();
    if (Platform.isAndroid) _request();
  }

  Future<void> _request() async {
    final status = await Permission.nearbyWifiDevices.request();
    if (!mounted) return;
    setState(() {
      _granted = status.isGranted;
      _asked = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_granted) return widget.child;
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.syncTitle)),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.wifi_off, size: 48),
              const SizedBox(height: 16),
              Text(l10n.syncPermissionNeeded, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              TextButton(
                onPressed: _asked ? openAppSettings : _request,
                child: Text(
                  _asked ? l10n.syncOpenSettings : l10n.syncGrantPermission,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class SyncScreen extends ConsumerWidget {
  const SyncScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final controller = ref.watch(syncControllerProvider);
    final peersAsync = ref.watch(pairedPeersProvider);

    // 收到的配对请求不在这里渲染 —— 它由 app.dart 的全局弹窗接管,
    // 因为请求可能在用户正在听歌、翻歌单时到达。

    final paired = peersAsync.value ?? const <Peer>[];
    return Scaffold(
      appBar: AppBar(title: Text(l10n.syncTitle)),
      body: ListView(
        children: [
          _localCard(context, l10n, controller),
          const Divider(),
          ListTile(
            dense: true,
            title: Text(
              l10n.syncPairedSection,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          if (paired.isEmpty)
            ListTile(dense: true, title: Text(l10n.syncNoPaired))
          else
            ...paired.map((p) => _pairedTile(context, l10n, ref, controller, p)),
          const Divider(),
          ListTile(
            dense: true,
            title: Text(
              l10n.syncDiscoveredSection,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          ..._discoveredTiles(context, l10n, controller, paired),
        ],
      ),
    );
  }

  Widget _localCard(
    BuildContext context,
    AppLocalizations l10n,
    SyncController controller,
  ) {
    final port = controller.serverPort;
    final error = controller.startError;
    return Card(
      margin: const EdgeInsets.all(12),
      child: ListTile(
        leading: const Icon(Icons.devices),
        title: Text(controller.identity?.deviceName ?? '—'),
        subtitle: Text(
          error != null
              ? l10n.syncStartFailed(error)
              : port != null
              ? l10n.syncListening(port)
              : l10n.syncNotStarted,
        ),
        trailing: error != null
            ? TextButton(
                onPressed: controller.start,
                child: Text(l10n.syncRetry),
              )
            : IconButton(
                icon: const Icon(Icons.edit),
                tooltip: l10n.syncRenameDevice,
                onPressed: () => _renameDialog(context, l10n, controller),
              ),
      ),
    );
  }

  Widget _pairedTile(
    BuildContext context,
    AppLocalizations l10n,
    WidgetRef ref,
    SyncController controller,
    Peer peer,
  ) {
    final address = controller.addressOf(peer.deviceId);
    return ListTile(
      leading: Icon(_platformIcon(peer.platform)),
      title: Text(peer.deviceName),
      subtitle: Text(
        address != null ? l10n.syncOnlineAt(address) : l10n.syncOffline,
      ),
      trailing: Wrap(
        spacing: 4,
        children: [
          TextButton(
            onPressed: address == null
                ? null
                : () => _syncNow(context, l10n, controller, peer),
            child: Text(l10n.syncNow),
          ),
          TextButton(
            onPressed: address == null
                ? null
                : () => _testConnection(context, l10n, controller, peer),
            child: Text(l10n.syncTestConnection),
          ),
          IconButton(
            icon: const Icon(Icons.link_off),
            tooltip: l10n.syncUnpair,
            onPressed: () => _unpair(context, l10n, ref, peer),
          ),
        ],
      ),
    );
  }

  List<Widget> _discoveredTiles(
    BuildContext context,
    AppLocalizations l10n,
    SyncController controller,
    List<Peer> paired,
  ) {
    final pairedIds = paired.map((p) => p.deviceId).toSet();
    final list = controller.online
        .where((p) => !pairedIds.contains(p.deviceId))
        .toList();
    if (list.isEmpty) {
      return [
        ListTile(
          dense: true,
          title: Text(l10n.syncNothingFound),
          subtitle: Text(l10n.syncNothingFoundHint),
        ),
      ];
    }
    return list
        .map(
          (peer) => ListTile(
            leading: Icon(_platformIcon(peer.platform)),
            title: Text(peer.deviceName),
            subtitle: Text(
              peer.isCompatible ? peer.address : l10n.syncIncompatible,
            ),
            trailing: peer.isCompatible
                ? TextButton(
                    onPressed: () =>
                        _startPairing(context, l10n, controller, peer),
                    child: Text(l10n.syncPair),
                  )
                : null,
          ),
        )
        .toList();
  }

  IconData _platformIcon(String platform) =>
      platform == 'windows' ? Icons.desktop_windows : Icons.smartphone;

  Future<void> _renameDialog(
    BuildContext context,
    AppLocalizations l10n,
    SyncController controller,
  ) async {
    final ctrl = TextEditingController(
      text: controller.identity?.deviceName ?? '',
    );
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.syncRenameDevice),
        content: TextField(controller: ctrl, autofocus: true),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(ctrl.text.trim()),
            child: Text(l10n.save),
          ),
        ],
      ),
    );
    if (name != null && name.isNotEmpty) {
      await controller.renameLocalDevice(name);
    }
  }

  /// 发起配对:弹窗显示 6 位码,用户目测与对端一致后由对端确认。
  Future<void> _startPairing(
    BuildContext context,
    AppLocalizations l10n,
    SyncController controller,
    DiscoveredPeer peer,
  ) async {
    final client = controller.client;
    if (client == null) return;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final codeNotifier = ValueNotifier<String?>(null);
    final future = client.pair(
      address: peer.address,
      onCode: (code) => codeNotifier.value = code,
    );

    // 故意不 await 这个弹窗:await 的话要等用户手动关掉才会往下走,
    // 配对早就成功了却还停在"等待对方确认"(烟测发现)。改成配对一有结果
    // 就由下面把它收起来,用户手动关也行(dialogOpen 兜住重复 pop)。
    var dialogOpen = true;
    unawaited(
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: Text(l10n.syncPairingWith(peer.deviceName)),
          content: ValueListenableBuilder<String?>(
            valueListenable: codeNotifier,
            builder: (ctx, code, _) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (code == null) ...[
                  const CircularProgressIndicator(),
                  const SizedBox(height: 12),
                  Text(l10n.syncNegotiating),
                ] else ...[
                  Text(l10n.syncCompareCodes),
                  const SizedBox(height: 16),
                  Text(
                    code,
                    style: Theme.of(
                      ctx,
                    ).textTheme.displaySmall?.copyWith(letterSpacing: 8),
                  ),
                  const SizedBox(height: 12),
                  Text(l10n.syncWaitingPeer),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(l10n.close),
            ),
          ],
        ),
      ).then((_) => dialogOpen = false),
    );

    final outcome = await future;
    codeNotifier.dispose();
    if (dialogOpen && navigator.mounted) navigator.pop();
    messenger.showSnackBar(
      SnackBar(
        content: Text(switch (outcome) {
          PairOutcome.paired => l10n.syncPairedWith(peer.deviceName),
          PairOutcome.rejected => l10n.syncPairRejected,
          PairOutcome.timedOut => l10n.syncPairTimedOut,
          PairOutcome.failed => l10n.syncPairFailed,
        }),
      ),
    );
  }

  Future<void> _testConnection(
    BuildContext context,
    AppLocalizations l10n,
    SyncController controller,
    Peer peer,
  ) async {
    final client = controller.client;
    if (client == null) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final res = await controller.runWithPeer(
        peer.deviceId,
        (address) =>
            client.hello(peerDeviceId: peer.deviceId, address: address),
      );
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            l10n.syncHelloResult(
              res.deviceName,
              res.platform,
              res.trackCount,
              res.protocolVersion,
            ),
          ),
        ),
      );
    } on SyncAuthException catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(switch (e.reason) {
            'unknown_device' => l10n.syncAuthUnknownDevice,
            'clock_skew' => l10n.syncAuthClockSkew,
            _ => l10n.syncAuthOther(e.reason),
          }),
        ),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.syncConnectFailed('$e'))),
      );
    }
  }

  Future<void> _syncNow(
    BuildContext context,
    AppLocalizations l10n,
    SyncController controller,
    Peer peer,
  ) async {
    final client = controller.client;
    if (client == null) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final s = await controller.runWithPeer(
        peer.deviceId,
        (address) =>
            client.syncMetadata(peerDeviceId: peer.deviceId, address: address),
      );
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            s.isEmpty
                ? l10n.syncAlreadyUpToDate
                : l10n.syncSummary(s.playlists, s.favorites, s.playEvents),
          ),
        ),
      );
    } on SyncUnsupportedException {
      messenger.showSnackBar(SnackBar(content: Text(l10n.syncPeerTooOld)));
    } on SyncAuthException catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(switch (e.reason) {
            'unknown_device' => l10n.syncAuthUnknownDevice,
            'clock_skew' => l10n.syncAuthClockSkew,
            _ => l10n.syncAuthOther(e.reason),
          }),
        ),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.syncConnectFailed('$e'))),
      );
    }
  }

  Future<void> _unpair(
    BuildContext context,
    AppLocalizations l10n,
    WidgetRef ref,
    Peer peer,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.syncUnpairTitle(peer.deviceName)),
        content: Text(l10n.syncUnpairBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l10n.syncUnpair),
          ),
        ],
      ),
    );
    if (ok == true) {
      await ref.read(databaseProvider).deletePeer(peer.deviceId);
    }
  }
}
