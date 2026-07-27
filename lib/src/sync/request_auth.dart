import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
// constantTimeBytesEquality 不在主库导出里,它在 helpers 子库。
import 'package:cryptography/helpers.dart';

/// 验签失败原因。响应体 `{"reason": "..."}` 用 [wireName]。
enum AuthFailure {
  unknownDevice('unknown_device'),
  clockSkew('clock_skew'),
  replay('replay'),
  badSignature('bad_signature');

  const AuthFailure(this.wireName);
  final String wireName;
}

const headerDevice = 'x-om-device';
const headerTimestamp = 'x-om-timestamp';
const headerNonce = 'x-om-nonce';
const headerSignature = 'x-om-sig';

/// 允许的两端时钟偏差。超出即 clockSkew(母 spec §8 要求提示用户校准)。
const clockSkewTolerance = Duration(minutes: 5);

final _rnd = Random.secure();
final _hmac = Hmac.sha256();

String newNonce() {
  final bytes = List<int>.generate(16, (_) => _rnd.nextInt(256));
  return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}

String _hex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

/// 规范化串:METHOD \n PATH \n timestamp \n nonce \n hex(sha256(body))
/// 两端必须逐字节一致地构造它,任何一项被篡改都会让签名对不上。
Future<String> canonicalString({
  required String method,
  required String path,
  required int timestampMs,
  required String nonce,
  required List<int> body,
}) async {
  final digest = await Sha256().hash(body);
  return [
    method.toUpperCase(),
    path,
    '$timestampMs',
    nonce,
    _hex(digest.bytes),
  ].join('\n');
}

Future<String> _sign({
  required List<int> sharedKey,
  required String canonical,
}) async {
  final mac = await _hmac.calculateMac(
    utf8.encode(canonical),
    secretKey: SecretKey(sharedKey),
  );
  return base64.encode(mac.bytes);
}

/// 生成一个请求的全部签名头。
Future<Map<String, String>> signHeaders({
  required String deviceId,
  required List<int> sharedKey,
  required String method,
  required String path,
  required List<int> body,
  DateTime? now,
  String? nonce,
}) async {
  final ts = (now ?? DateTime.now()).millisecondsSinceEpoch;
  final n = nonce ?? newNonce();
  final canonical = await canonicalString(
    method: method,
    path: path,
    timestampMs: ts,
    nonce: n,
    body: body,
  );
  return {
    headerDevice: deviceId,
    headerTimestamp: '$ts',
    headerNonce: n,
    headerSignature: await _sign(sharedKey: sharedKey, canonical: canonical),
  };
}

/// 进程内的 nonce 记忆,只保留时间窗内的条目。
/// 进程重启即清空:可以接受,时间戳窗口本身已挡住旧报文重放。
class ReplayGuard {
  final Map<String, int> _seen = {};

  int get size => _seen.length;

  /// 记住并判定:true = 首次出现(放行),false = 重放。
  bool checkAndRemember(String nonce, int timestampMs, {DateTime? now}) {
    final nowMs = (now ?? DateTime.now()).millisecondsSinceEpoch;
    _seen.removeWhere(
      (_, ts) => (nowMs - ts).abs() > clockSkewTolerance.inMilliseconds,
    );
    if (_seen.containsKey(nonce)) return false;
    _seen[nonce] = timestampMs;
    return true;
  }
}

/// 验签。返回 null = 通过,否则是失败原因。
///
/// [keyLookup] 按 deviceId 取共享密钥,返回 null 表示未配对。
Future<AuthFailure?> verifyRequest({
  required Map<String, String> headers,
  required String method,
  required String path,
  required List<int> body,
  required Future<List<int>?> Function(String deviceId) keyLookup,
  required ReplayGuard guard,
  DateTime? now,
}) async {
  final deviceId = headers[headerDevice];
  final tsRaw = headers[headerTimestamp];
  final nonce = headers[headerNonce];
  final sig = headers[headerSignature];
  if (deviceId == null || tsRaw == null || nonce == null || sig == null) {
    return AuthFailure.badSignature;
  }
  final ts = int.tryParse(tsRaw);
  if (ts == null) return AuthFailure.badSignature;

  final key = await keyLookup(deviceId);
  if (key == null) return AuthFailure.unknownDevice;

  final nowMs = (now ?? DateTime.now()).millisecondsSinceEpoch;
  if ((nowMs - ts).abs() > clockSkewTolerance.inMilliseconds) {
    return AuthFailure.clockSkew;
  }

  final canonical = await canonicalString(
    method: method,
    path: path,
    timestampMs: ts,
    nonce: nonce,
    body: body,
  );
  final expected = await _sign(sharedKey: key, canonical: canonical);
  // 常数时间比较:普通 == 的提前返回会泄漏"前缀对了几个字节"。
  if (!constantTimeBytesEquality.equals(
    utf8.encode(expected),
    utf8.encode(sig),
  )) {
    return AuthFailure.badSignature;
  }

  // 重放检查放在验签之后:未通过验签的请求不该污染 nonce 表
  // (否则任何人发一堆伪造请求就能把合法 nonce 提前"用掉")。
  if (!guard.checkAndRemember(nonce, ts, now: now)) return AuthFailure.replay;
  return null;
}
