import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openmusic/src/app/providers.dart';
import 'package:openmusic/src/data/database.dart';
import 'package:openmusic/src/sync/device_identity.dart';
import 'package:openmusic/src/sync/discovery.dart';
import 'package:openmusic/src/sync/sync_controller.dart';
import 'package:openmusic/src/sync/sync_server.dart';
import 'package:openmusic/src/ui/pair_request_prompt.dart';
import 'package:openmusic/src/ui/sync_screen.dart';

import 'helpers/db.dart';
import 'helpers/fake_discovery.dart';
import 'helpers/pump.dart';

/// 不开套接字的控制器替身。
///
/// 真 [SyncController.start] 会 bind 一个 HttpServer,而 `HttpServer.bind` 注册的
/// 周期性 idleTimeout 定时器在 testWidgets 的假时钟下永远不完成(本项目"真实 IO
/// 进 widget 测试必挂"的同一类坑)。同步页只读 identity/serverPort/online/
/// startError/incomingPair 这几个字段,替身把它们直接摆好即可。
/// 真实的网络行为由 sync_loopback_test 覆盖。
class StubSyncController extends SyncController {
  StubSyncController({
    required super.db,
    required super.discovery,
    required super.platform,
  });

  int? stubPort = 52341;

  @override
  int? get serverPort => stubPort;

  @override
  Future<void> start() async {
    identity = const DeviceIdentity(deviceId: 'local-1', deviceName: '台式机');
    notifyListeners();
  }

  @override
  Future<void> stop() async {
    stubPort = null;
    notifyListeners();
  }
}

void main() {
  late AppDatabase db;
  late FakeDiscovery discovery;
  late StubSyncController controller;

  setUp(() async {
    db = AppDatabase(testExecutor());
    discovery = FakeDiscovery();
    controller = StubSyncController(
      db: db,
      discovery: discovery,
      platform: 'windows',
    );
    await controller.start();
  });

  tearDown(() async {
    // 不要 controller.dispose():ChangeNotifierProvider 在 ProviderScope 拆除时
    // 已经 dispose 过一次,再调会触发 ChangeNotifier 的二次 dispose 断言
    // (providers.dart 里 PlaybackController 的同款坑)。
    discovery.dispose();
    await db.close();
  });

  // localizedApp 默认中文 locale —— 下面的中文断言因此有效。裸写 MaterialApp
  // 会让 AppLocalizations.of(context) 返回 null 直接崩。
  Future<void> pumpScreen(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          syncControllerProvider.overrideWith((ref) => controller),
        ],
        child: localizedApp(const SyncScreen()),
      ),
    );
    await tester.pump();
  }

  testWidgets('显示本机设备名与监听端口', (tester) async {
    await pumpScreen(tester);
    expect(find.textContaining('监听中'), findsOneWidget);
    expect(find.text('台式机'), findsOneWidget);
  });

  testWidgets('局域网发现的未配对设备显示「配对」按钮', (tester) async {
    controller.online = const [
      DiscoveredPeer(
        deviceId: 'stranger',
        deviceName: '客厅手机',
        platform: 'android',
        protocolVersion: 1,
        address: '10.0.0.3:2222',
      ),
    ];
    await pumpScreen(tester);

    expect(find.text('客厅手机'), findsOneWidget);
    expect(find.widgetWithText(TextButton, '配对'), findsOneWidget);
  });

  testWidgets('协议版本不兼容的设备提示升级,没有配对按钮', (tester) async {
    controller.online = const [
      DiscoveredPeer(
        deviceId: 'oldie',
        deviceName: '老版本设备',
        platform: 'android',
        protocolVersion: 99,
        address: '10.0.0.4:3333',
      ),
    ];
    await pumpScreen(tester);

    expect(find.textContaining('需要升级'), findsOneWidget);
    expect(find.widgetWithText(TextButton, '配对'), findsNothing);
  });

  testWidgets('已配对设备显示且带解除配对按钮,不在线则显示离线', (tester) async {
    await db.upsertPeer(
      deviceId: 'known',
      deviceName: '卧室平板',
      platform: 'android',
      sharedKey: 'k',
    );
    await pumpScreen(tester);
    await tester.pump(); // 等 pairedPeersProvider 首帧数据

    expect(find.text('卧室平板'), findsOneWidget);
    expect(find.byIcon(Icons.link_off), findsOneWidget);
    expect(find.text('离线'), findsOneWidget);
  });

  testWidgets('配对请求提示:显示 6 位码与两个动作', (tester) async {
    var accepted = false;
    var rejected = false;
    await tester.pumpWidget(
      localizedApp(
        Scaffold(
          body: PairRequestPrompt(
            request: const PairRequest(
              deviceId: 'x',
              deviceName: '书房电脑',
              platform: 'windows',
              code: '048213',
            ),
            onAccept: () => accepted = true,
            onReject: () => rejected = true,
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('048213'), findsOneWidget);
    expect(find.textContaining('书房电脑'), findsWidgets);

    await tester.tap(find.text('两边数字一致'));
    expect(accepted, isTrue);
    await tester.tap(find.text('拒绝'));
    expect(rejected, isTrue);
  });

  testWidgets('服务启动失败时显示错误与重试', (tester) async {
    controller.stubPort = null;
    controller.startError = '绑定端口失败:权限不足';
    await pumpScreen(tester);

    expect(find.textContaining('绑定端口失败'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);
  });
}
