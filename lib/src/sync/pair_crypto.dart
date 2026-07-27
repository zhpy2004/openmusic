import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// 一次配对用的临时密钥对(每次配对新生成,不持久化)。
class PairKeys {
  const PairKeys({required this.keyPair, required this.publicKeyBytes});
  final SimpleKeyPair keyPair;
  final List<int> publicKeyBytes;
}

final _x25519 = X25519();
final _hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);

Future<PairKeys> generatePairKeys() async {
  final keyPair = await _x25519.newKeyPair();
  final pub = await keyPair.extractPublicKey();
  return PairKeys(keyPair: keyPair, publicKeyBytes: pub.bytes);
}

/// 设备 id 排序后拼接 —— 两端各自代入自己的视角,必须得到同一个串。
String _sortedIds(String a, String b) {
  final ids = [a, b]..sort();
  return ids.join(':');
}

/// X25519 协商 + HKDF-SHA256 派生 32 字节长期 HMAC 密钥。
///
/// salt 绑定两端设备 id:同一对设备重复配对得到不同密钥(临时密钥对每次新生成),
/// 但换一对设备即使协商出相同原始密钥也派生不出同一把 key。
Future<List<int>> deriveSharedKey({
  required SimpleKeyPair myKeyPair,
  required List<int> theirPublicKey,
  required String myDeviceId,
  required String theirDeviceId,
}) async {
  final shared = await _x25519.sharedSecretKey(
    keyPair: myKeyPair,
    remotePublicKey: SimplePublicKey(theirPublicKey, type: KeyPairType.x25519),
  );
  final derived = await _hkdf.deriveKey(
    secretKey: shared,
    nonce: utf8.encode(_sortedIds(myDeviceId, theirDeviceId)),
    info: utf8.encode('openmusic-pair-v1'),
  );
  return derived.extractBytes();
}

/// 人工比对用的 6 位十进制码。
///
/// 取 SHA-256 的**前 4 字节**按大端读成无符号 32 位整数再 mod 10^6:
/// 取 8 字节会溢出 Dart 的有符号 64 位 int;32 位对 10^6 取模的偏差
/// (约 0.02%)对"人工目测比对"这个用途完全无关紧要。
Future<String> pairingCode(
  List<int> sharedKey,
  String deviceIdA,
  String deviceIdB,
) async {
  final material = <int>[
    ...sharedKey,
    ...utf8.encode(_sortedIds(deviceIdA, deviceIdB)),
  ];
  final digest = await Sha256().hash(material);
  final n = ByteData.sublistView(
    Uint8List.fromList(digest.bytes.sublist(0, 4)),
  ).getUint32(0, Endian.big);
  return (n % 1000000).toString().padLeft(6, '0');
}
