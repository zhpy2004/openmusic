import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../data/database.dart';
import '../library/library_setup.dart';

/// 同步下载目录的解析。**本文件是 M3-C 唯一碰平台差异的地方。**
///
/// **Android 为什么不用 `/storage/emulated/0/Music`**:本项目 targetSdk 36,
/// 分区存储下 App 不能用普通 File API 往公共音乐目录**写**(读可以,靠
/// READ_MEDIA_AUDIO),除非申请"所有文件访问"那种敏感权限。App 外部私有目录
/// (`Android/data/<pkg>/files/Music`)无需任何权限即可读写,是唯一干净的落点。
/// 代价:卸载 App 会一并删除这些副本(它们本就是副本,原件在对端)。
Future<Directory> defaultSyncDir() async {
  if (Platform.isAndroid) {
    // getExternalStorageDirectory() → /storage/emulated/0/Android/data/<pkg>/files
    final base = await getExternalStorageDirectory();
    if (base != null) return Directory(p.join(base.path, 'Music'));
  }
  final docs = await getApplicationDocumentsDirectory();
  return Directory(p.join(docs.path, 'OpenMusic', 'Synced'));
}

/// 确保同步目录存在并登记为扫描根,返回归一化后的目录路径。幂等。
///
/// **登记为扫描根是关键一环**:文件落盘后要被扫进 tracks 表、指纹对上,
/// 歌单里的灰条目才会变可播。
///
/// [resolveDir] 仅供测试注入,生产调用不传。
Future<String> ensureSyncRoot(
  AppDatabase db, {
  Future<Directory> Function()? resolveDir,
}) async {
  final dir = await (resolveDir ?? defaultSyncDir)();
  if (!await dir.exists()) {
    await dir.create(recursive: true);
  }
  final root = normalizeRoot(dir.path);
  // addScanRoot 是 insertOrIgnore,重复调用不会重复登记。
  await db.addScanRoot(root);
  return root;
}
