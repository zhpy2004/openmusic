import 'dart:ffi';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:sqlite3/open.dart';

bool _overridden = false;

/// 测试用内存数据库。Windows 上从 tool/sqlite3/ 加载 sqlite3.dll。
///
/// closeStreamsSynchronously：drift 默认在最后一个订阅者取消后用 Timer.run
/// 延迟一轮事件循环再清理流缓存；widget test（FakeAsync）里该 timer 会触发
/// "A Timer is still pending" 断言，且 tearDown 的 db.close() 会永远等待
/// 这个不被推进的假 timer（drift 源码注释即为此场景推荐本选项）。
QueryExecutor testExecutor() {
  if (Platform.isWindows && !_overridden) {
    _overridden = true;
    // 相对路径：假设 CWD 为包根（flutter test 默认从包根运行）。
    open.overrideFor(
      OperatingSystem.windows,
      () => DynamicLibrary.open('tool/sqlite3/sqlite3.dll'),
    );
  }
  return DatabaseConnection(
    NativeDatabase.memory(),
    closeStreamsSynchronously: true,
  );
}

/// 文件型测试库:迁移测试需要"关掉再重新打开同一个库",内存库做不到
/// (关掉即销毁)。与 testExecutor 共用同一份 sqlite3.dll 覆盖逻辑。
QueryExecutor testFileExecutor(String path) {
  if (Platform.isWindows && !_overridden) {
    _overridden = true;
    open.overrideFor(
      OperatingSystem.windows,
      () => DynamicLibrary.open('tool/sqlite3/sqlite3.dll'),
    );
  }
  return DatabaseConnection(
    NativeDatabase(File(path)),
    closeStreamsSynchronously: true,
  );
}
