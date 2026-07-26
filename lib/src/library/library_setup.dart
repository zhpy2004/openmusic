import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:permission_handler/permission_handler.dart';

import '../data/database.dart';
import 'scanner.dart';

const _androidDefaultRoot = '/storage/emulated/0/Music';

/// 归一化扫描根:p.normalize 收敛分隔符/点段,Windows 盘符统一大写。
String normalizeRoot(String path) {
  var n = p.normalize(path);
  if (Platform.isWindows && n.length >= 2 && n[1] == ':') {
    n = n[0].toUpperCase() + n.substring(1);
  }
  return n;
}

enum AddFolderResult { added, permissionDenied, cancelled }

/// 加扫描根(平台分流)。Android:权限流 + 固定系统音乐目录;桌面:目录选择器。
/// 返回结果由调用方决定是否提示。
Future<AddFolderResult> addScanFolder(AppDatabase db) async {
  if (Platform.isAndroid) {
    // permission_handler_android 12.1.0:audio 在 SDK<33 恒 DENIED、storage 在
    // SDK<33 才真弹窗;两者在不同 SDK 互补,依次请求覆盖全版本。
    var status = await Permission.audio.request();
    if (!status.isGranted) status = await Permission.storage.request();
    if (!status.isGranted) return AddFolderResult.permissionDenied;
    // Android 13+ 媒体通知是运行时权限;拒了不挡入库,只是没系统媒体控制。
    await Permission.notification.request();
    await db.addScanRoot(_androidDefaultRoot);
    return AddFolderResult.added;
  } else {
    final path = await FilePicker.platform.getDirectoryPath();
    if (path == null) return AddFolderResult.cancelled;
    await db.addScanRoot(normalizeRoot(path));
    return AddFolderResult.added;
  }
}

/// 跑一次全库扫描。进度/问题通过回调上报(设置页/向导各接自己的 state)。
/// 立即发占位(闭双击重入窗口);done 事件携带完整问题清单;finally 清进度。
/// 异常向上抛,由调用方提示。
Future<void> runLibraryScan({
  required AppDatabase db,
  required LibraryScanner scanner,
  required void Function(ScanProgress?) onProgress,
  required void Function(List<ScanProblem>) onProblems,
}) async {
  onProblems(const []);
  onProgress(const ScanProgress(scanned: 0, total: 0));
  try {
    final roots = await db.watchScanRoots().first;
    await for (final progress in scanner.scan(roots)) {
      if (progress.done) onProblems(progress.problems);
      onProgress(progress.done ? null : progress);
    }
  } finally {
    onProgress(null);
  }
}
