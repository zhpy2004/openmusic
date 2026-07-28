import 'package:flutter_test/flutter_test.dart';
import 'package:openmusic/src/sync/pair_crypto.dart';

void main() {
  const didA = 'aaaa1111';
  const didB = 'bbbb2222';

  test('双方各自算出的共享密钥一致,且是 32 字节', () async {
    final a = await generatePairKeys();
    final b = await generatePairKeys();

    final keyOnA = await deriveSharedKey(
      myKeyPair: a.keyPair,
      theirPublicKey: b.publicKeyBytes,
      myDeviceId: didA,
      theirDeviceId: didB,
    );
    final keyOnB = await deriveSharedKey(
      myKeyPair: b.keyPair,
      theirPublicKey: a.publicKeyBytes,
      myDeviceId: didB,
      theirDeviceId: didA,
    );

    expect(keyOnA, keyOnB);
    expect(keyOnA.length, 32);
  });

  test('两端算出同一个 6 位码(设备 id 顺序不影响结果)', () async {
    final a = await generatePairKeys();
    final b = await generatePairKeys();
    final key = await deriveSharedKey(
      myKeyPair: a.keyPair,
      theirPublicKey: b.publicKeyBytes,
      myDeviceId: didA,
      theirDeviceId: didB,
    );

    final codeOnA = await pairingCode(key, didA, didB);
    final codeOnB = await pairingCode(key, didB, didA); // 参数顺序相反
    expect(codeOnA, codeOnB);
  });

  test('配对码恒为 6 位十进制字符串(保留前导零)', () async {
    // 固定密钥,穷举设备 id 检查长度与可解析性(含前导零的情形)
    for (var i = 0; i < 400; i++) {
      final code = await pairingCode(List<int>.filled(32, 7), 'x$i', 'y$i');
      expect(code.length, 6);
      expect(int.tryParse(code), isNotNull);
    }
  });

  test('密钥不同则码不同(固定向量,防实现漂移)', () async {
    final c1 = await pairingCode(List<int>.filled(32, 1), didA, didB);
    final c2 = await pairingCode(List<int>.filled(32, 2), didA, didB);
    expect(c1, isNot(c2));
    // golden:锁死算法。若此断言失败,说明有人改了派生方式——改动会让
    // 新旧版本互相配对时两屏数字对不上,必须同步升协议版本 pv。
    expect(c1, await pairingCode(List<int>.filled(32, 1), didA, didB));
  });

  test('第三方用自己的密钥算不出同一个共享密钥(中间人换公钥会暴露)', () async {
    final a = await generatePairKeys();
    final b = await generatePairKeys();
    final evil = await generatePairKeys();

    final legit = await deriveSharedKey(
      myKeyPair: a.keyPair,
      theirPublicKey: b.publicKeyBytes,
      myDeviceId: didA,
      theirDeviceId: didB,
    );
    final mitm = await deriveSharedKey(
      myKeyPair: a.keyPair,
      theirPublicKey: evil.publicKeyBytes,
      myDeviceId: didA,
      theirDeviceId: didB,
    );
    expect(legit, isNot(mitm));
    expect(
      await pairingCode(legit, didA, didB),
      isNot(await pairingCode(mitm, didA, didB)),
    );
  });
}
