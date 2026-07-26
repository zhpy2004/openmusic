import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/providers.dart';
import '../library/library_setup.dart';
import '../ui/library_screen.dart';
import '../ui/now_playing_bar.dart';
import '../ui/playlists_screen.dart';
import '../ui/settings_screen.dart';
import '../ui/setup_wizard.dart';

class OpenMusicApp extends ConsumerStatefulWidget {
  const OpenMusicApp({super.key});

  @override
  ConsumerState<OpenMusicApp> createState() => _OpenMusicAppState();
}

class _OpenMusicAppState extends ConsumerState<OpenMusicApp> {
  int _tab = 0;
  bool _wizardDismissed = false;
  bool _decided = false; // 是否已根据首个 roots 值做出"是否进向导"的一次性决定
  bool _onboarding = false; // 锁存:进入向导后不因期间新增文件夹(roots 变非空)被踢出

  static const _screens = [
    LibraryScreen(),
    PlaylistsScreen(),
    SettingsScreen(),
  ];

  Future<void> _runScan() async {
    final notifier = ref.read(scanProgressProvider.notifier);
    final problemsNotifier = ref.read(lastScanProblemsProvider.notifier);
    await runLibraryScan(
      db: ref.read(databaseProvider),
      scanner: ref.read(scannerProvider),
      onProgress: (p) => notifier.state = p,
      onProblems: (probs) => problemsNotifier.state = probs,
    );
  }

  Widget _buildWizard() {
    final roots = ref.watch(scanRootsProvider).value ?? const <String>[];
    final progress = ref.watch(scanProgressProvider);
    final scanStatus = progress == null
        ? null
        : '扫描中 ${progress.scanned}/${progress.total}';
    return SetupWizard(
      roots: roots,
      scanStatus: scanStatus,
      onAddFolder: () => addScanFolder(ref.read(databaseProvider)),
      onScan: _runScan,
      batchStreamBuilder: (cancel) {
        final db = ref.read(databaseProvider);
        final service = ref.read(batchScraperServiceProvider);
        // 扫描后的全库快照;drift 流首值在真实 async(非 testWidgets)里可靠。
        return Stream.fromFuture(
          db.watchTracks('').first,
        ).asyncExpand((tracks) => service.run(tracks, shouldCancel: cancel));
      },
      onDismiss: () => setState(() => _wizardDismissed = true),
      onFinish: () => setState(() => _wizardDismissed = true),
    );
  }

  Widget _buildHome(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 800; // 桌面=侧栏，手机=底栏（spec §5）
        final body = Column(
          children: [
            // IndexedStack：切 tab 不卸载子树。直接索引会让 LibraryScreen 重建，
            // TextField 清空但全局 searchQueryProvider 仍留旧词（列表被过滤而
            // 搜索框是空的），滚动位置也丢。
            Expanded(
              child: IndexedStack(index: _tab, children: _screens),
            ),
            const NowPlayingBar(),
          ],
        );
        if (wide) {
          return Scaffold(
            body: Row(
              children: [
                NavigationRail(
                  selectedIndex: _tab,
                  onDestinationSelected: (i) => setState(() => _tab = i),
                  labelType: NavigationRailLabelType.all,
                  destinations: const [
                    NavigationRailDestination(
                      icon: Icon(Icons.library_music),
                      label: Text('曲库'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.queue_music),
                      label: Text('歌单'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.settings),
                      label: Text('设置'),
                    ),
                  ],
                ),
                const VerticalDivider(width: 1),
                Expanded(child: body),
              ],
            ),
          );
        }
        return Scaffold(
          body: SafeArea(child: body),
          bottomNavigationBar: NavigationBar(
            selectedIndex: _tab,
            onDestinationSelected: (i) => setState(() => _tab = i),
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.library_music),
                label: '曲库',
              ),
              NavigationDestination(icon: Icon(Icons.queue_music), label: '歌单'),
              NavigationDestination(icon: Icon(Icons.settings), label: '设置'),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final rootsAsync = ref.watch(scanRootsProvider);
    // 首次拿到 roots 值时一次性决定:空则进向导并锁存;此后 roots 变化(如向导内
    // 新增文件夹使其变非空)不再改变是否显示向导——只有跳过/完成能退出。
    if (!_decided && rootsAsync.hasValue) {
      _decided = true;
      _onboarding = rootsAsync.value!.isEmpty;
    }
    final showWizard = _onboarding && !_wizardDismissed;

    return MaterialApp(
      title: 'OpenMusic',
      theme: ThemeData(colorSchemeSeed: Colors.teal, useMaterial3: true),
      darkTheme: ThemeData(
        colorSchemeSeed: Colors.teal,
        brightness: Brightness.dark,
        useMaterial3: true,
      ),
      // roots 未加载完前给中性 loading,避免向导/曲库任一方闪一帧。
      home: !_decided
          ? const Scaffold(body: Center(child: CircularProgressIndicator()))
          : (showWizard ? _buildWizard() : _buildHome(context)),
    );
  }
}
