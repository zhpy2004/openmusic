import 'dart:io';
import 'dart:math';

import '../data/database.dart';

/// 本机设备身份。deviceId 是跨设备身份,一旦生成永不改写;deviceName 用户可改。
class DeviceIdentity {
  const DeviceIdentity({required this.deviceId, required this.deviceName});
  final String deviceId;
  final String deviceName;
}

final _rnd = Random.secure();

/// 16 字节密码学随机数的小写十六进制。
///
/// **不复用 `AppDatabase._newUuid()`**:那个的后缀是毫秒派生的,零熵,在 Windows
/// 粗时钟下会大量碰撞(M2-A 的 Critical)。deviceId 同样既是主键又是同步身份,
/// 必须每一位都来自 Random.secure()。
String newDeviceId() {
  final bytes = List<int>.generate(16, (_) => _rnd.nextInt(256));
  return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}

/// 默认设备名 = 主机名;取不到时退回平台名。
String defaultDeviceName() {
  final host = Platform.localHostname;
  if (host.trim().isNotEmpty) return host;
  return Platform.isWindows ? 'Windows' : 'Android';
}

/// 本机平台标识,进 mDNS TXT 与 /v1/hello 响应。
String localPlatform() => Platform.isWindows ? 'windows' : 'android';

/// 读取本机身份,不存在则生成并落库(幂等:并发首启只会留下第一条)。
Future<DeviceIdentity> loadOrCreateIdentity(
  AppDatabase db, {
  String? defaultName,
}) async {
  await db.ensureLocalDevice(
    deviceId: newDeviceId(),
    deviceName: defaultName ?? defaultDeviceName(),
  );
  final row = (await db.getLocalDevice())!;
  return DeviceIdentity(deviceId: row.deviceId, deviceName: row.deviceName);
}
