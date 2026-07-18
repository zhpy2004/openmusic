import 'package:flutter/material.dart';

import '../ui/library_screen.dart';
import '../ui/now_playing_bar.dart';
import '../ui/settings_screen.dart';

class OpenMusicApp extends StatefulWidget {
  const OpenMusicApp({super.key});

  @override
  State<OpenMusicApp> createState() => _OpenMusicAppState();
}

class _OpenMusicAppState extends State<OpenMusicApp> {
  int _tab = 0;
  static const _screens = [LibraryScreen(), SettingsScreen()];

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'OpenMusic',
      theme: ThemeData(colorSchemeSeed: Colors.teal, useMaterial3: true),
      darkTheme: ThemeData(
        colorSchemeSeed: Colors.teal,
        brightness: Brightness.dark,
        useMaterial3: true,
      ),
      home: LayoutBuilder(
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
                NavigationDestination(icon: Icon(Icons.settings), label: '设置'),
              ],
            ),
          );
        },
      ),
    );
  }
}
