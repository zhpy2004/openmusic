import 'package:flutter_test/flutter_test.dart';
import 'package:openmusic/src/data/database.dart';
import 'package:openmusic/src/sync/device_identity.dart';

import 'helpers/db.dart';

void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase(testExecutor()));
  tearDown(() => db.close());

  test('首次调用生成身份,再次调用返回同一个 deviceId', () async {
    final first = await loadOrCreateIdentity(db, defaultName: 'PC');
    final second = await loadOrCreateIdentity(db, defaultName: '别的名字');
    expect(second.deviceId, first.deviceId);
    expect(second.deviceName, 'PC');
  });

  test('deviceId 是 32 位小写十六进制(16 字节)', () async {
    final id = await loadOrCreateIdentity(db, defaultName: 'PC');
    expect(id.deviceId, matches(RegExp(r'^[0-9a-f]{32}$')));
  });

  test('1000 次生成互不相同(deviceId 既是主键又是跨设备身份)', () {
    final ids = <String>{};
    for (var i = 0; i < 1000; i++) {
      ids.add(newDeviceId());
    }
    expect(ids.length, 1000);
  });
}
