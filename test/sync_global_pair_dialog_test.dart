import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openmusic/src/app/app.dart';
import 'package:openmusic/src/app/providers.dart';
import 'package:openmusic/src/data/database.dart';
import 'package:openmusic/src/sync/sync_controller.dart';
import 'package:openmusic/src/sync/sync_server.dart';

import 'helpers/db.dart';
import 'helpers/fake_discovery.dart';
import 'helpers/fakes.dart';

/// 烟测发现:配对请求原来只在同步页里渲染,用户在听歌/翻歌单时根本看不见。
/// 这组测试锁住"请求到达即全局弹窗、处理完自动收起"。
///
/// 用 [StubSyncController] 而非真 controller:真的 start() 会 bind HttpServer,
/// 其周期定时器在假时钟下永不完成 → widget 测试挂死。
class StubSyncController extends SyncController {
  StubSyncController({
    required super.db,
    required super.discovery,
    required super.platform,
  });

  @override
  Future<void> start() async {}

  @override
  Future<void> stop() async {}

  void receivePair(PairRequest request) {
    incomingPair = request;
    notifyListeners();
  }

  @override
  void acceptIncomingPair() {
    incomingPair = null;
    notifyListeners();
  }

  @override
  void rejectIncomingPair() {
    incomingPair = null;
    notifyListeners();
  }
}

void main() {
  late AppDatabase db;
  late FakeDiscovery discovery;
  late StubSyncController controller;

  setUp(() {
    db = AppDatabase(testExecutor());
    discovery = FakeDiscovery();
    controller = StubSyncController(
      db: db,
      discovery: discovery,
      platform: 'windows',
    );
  });

  tearDown(() async {
    discovery.dispose();
    await db.close();
  });

  // OpenMusicApp 自带 MaterialApp,外部注入不了 locale;测试环境默认英文,
  // 故断言英文文案(与 setup_wizard_test 同一约定)。
  Future<void> pumpApp(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          audioEngineProvider.overrideWithValue(FakeAudioEngine()),
          scanRootsProvider.overrideWith((ref) => Stream.value(const ['/m'])),
          syncControllerProvider.overrideWith((ref) => controller),
        ],
        child: const OpenMusicApp(),
      ),
    );
    await tester.pump();
  }

  testWidgets('用户在曲库页时收到配对请求 → 全局弹窗显示 6 位码', (tester) async {
    await pumpApp(tester);
    expect(find.text('418320'), findsNothing);

    controller.receivePair(
      const PairRequest(
        deviceId: 'x',
        deviceName: 'Study PC',
        platform: 'windows',
        code: '418320',
      ),
    );
    await tester.pump(); // 触发 ref.listen → showDialog
    await tester.pump(); // 弹窗入场

    expect(find.text('418320'), findsOneWidget);
    expect(find.textContaining('Study PC'), findsWidgets);
  });

  testWidgets('确认后弹窗自动收起', (tester) async {
    await pumpApp(tester);
    controller.receivePair(
      const PairRequest(
        deviceId: 'x',
        deviceName: 'Study PC',
        platform: 'windows',
        code: '418320',
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.text('418320'), findsOneWidget);

    await tester.tap(find.text('Numbers match'));
    await tester.pumpAndSettle();

    expect(find.text('418320'), findsNothing);
  });
}
