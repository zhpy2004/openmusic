import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:permission_handler/permission_handler.dart';

import '../app/providers.dart';
import '../library/scanner.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  static const _androidDefaultRoot = '/storage/emulated/0/Music';

  /// 归一化扫描根（T3 审查遗留）：p.normalize 收敛分隔符/点段，Windows 盘符统一大写。
  static String _normalizeRoot(String path) {
    var n = p.normalize(path);
    if (Platform.isWindows && n.length >= 2 && n[1] == ':') {
      n = n[0].toUpperCase() + n.substring(1);
    }
    return n;
  }

  Future<void> _addFolder(BuildContext context, WidgetRef ref) async {
    final db = ref.read(databaseProvider);
    if (Platform.isAndroid) {
      // MVP：Android 固定扫描系统音乐目录（SAF 目录选择与 dart:io 不兼容，见 spec 风险）
      // 权限分流（T9 审查裁定 T10 执行）：permission_handler_android 12.1.0 里
      // Permission.audio 在 SDK<33 映射空权限列表，恒 DENIED、不弹窗；
      // Permission.storage 则相反，在 SDK<33 映射 READ_EXTERNAL_STORAGE（真弹窗），
      // 在 SDK33+ 映射空列表恒 DENIED。两者在不同 SDK 上互补，依次请求即可覆盖全版本。
      var status = await Permission.audio.request();
      if (!status.isGranted) {
        status = await Permission.storage.request();
      }
      if (!status.isGranted) {
        if (context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('需要音频读取权限才能扫描')));
        }
        return;
      }
      // Android 13+：媒体通知是运行时权限。不授权则播放时 audio_service 的前台服务
      // 起不来(mAllowStartForeground false)、通知栏/锁屏无媒体控件。best-effort:
      // 拒了也不挡入库,只是没有系统媒体控制。
      await Permission.notification.request();
      await db.addScanRoot(_androidDefaultRoot);
    } else {
      final path = await FilePicker.platform.getDirectoryPath();
      if (path != null) await db.addScanRoot(_normalizeRoot(path));
    }
  }

  Future<void> _scan(BuildContext context, WidgetRef ref) async {
    final db = ref.read(databaseProvider);
    final scanner = ref.read(scannerProvider);
    final notifier = ref.read(scanProgressProvider.notifier); // unmount 后仍安全
    final problemsNotifier = ref.read(lastScanProblemsProvider.notifier);
    problemsNotifier.state = const []; // 开扫清空上次结果
    notifier.state = const ScanProgress(scanned: 0, total: 0); // 立即占位,闭双击重入窗口
    try {
      final roots = await db.watchScanRoots().first;
      await for (final progress in scanner.scan(roots)) {
        if (progress.done) {
          // done 事件携带完整问题清单,持久保留供扫描后查看
          problemsNotifier.state = progress.problems;
        }
        notifier.state = progress.done ? null : progress;
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('扫描出错: $e')));
      }
    } finally {
      notifier.state = null;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rootsAsync = ref.watch(scanRootsProvider);
    final progress = ref.watch(scanProgressProvider);
    final lastProblems = ref.watch(lastScanProblemsProvider);

    return ListView(
      padding: const EdgeInsets.all(8),
      children: [
        const ListTile(
          title: Text('音乐文件夹', style: TextStyle(fontWeight: FontWeight.bold)),
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
          title: Text(Platform.isAndroid ? '添加系统音乐文件夹' : '添加文件夹…'),
          onTap: () => _addFolder(context, ref),
        ),
        const Divider(),
        if (progress == null)
          ListTile(
            leading: const Icon(Icons.refresh),
            title: const Text('扫描曲库'),
            onTap: () => _scan(context, ref),
          )
        else
          ListTile(
            leading: const CircularProgressIndicator(),
            title: Text('扫描中 ${progress.scanned}/${progress.total}'),
            subtitle: Text(
              progress.currentPath ?? '',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        if (progress != null && progress.problems.isNotEmpty)
          ListTile(
            leading: const Icon(Icons.warning_amber),
            title: Text('问题文件 ${progress.problems.length} 个'),
          ),
        if (progress == null && lastProblems.isNotEmpty) ...[
          const Divider(),
          ListTile(
            leading: const Icon(Icons.warning_amber),
            title: Text('上次扫描有 ${lastProblems.length} 个问题'),
            trailing: TextButton(
              onPressed: () =>
                  ref.read(lastScanProblemsProvider.notifier).state = const [],
              child: const Text('清除'),
            ),
          ),
          ...lastProblems.map(
            (msg) => ListTile(
              dense: true,
              leading: const Icon(Icons.error_outline, size: 20),
              title: Text(msg, style: Theme.of(context).textTheme.bodySmall),
            ),
          ),
        ],
      ],
    );
  }
}
