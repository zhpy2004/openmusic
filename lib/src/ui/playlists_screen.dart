import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../app/providers.dart';
import '../library/m3u8.dart';
import 'favorites_screen.dart';
import 'playlist_detail_screen.dart';

class PlaylistsScreen extends ConsumerWidget {
  const PlaylistsScreen({super.key});

  Future<void> _create(BuildContext context, WidgetRef ref) async {
    final ctrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('新建歌单'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(hintText: '歌单名'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('创建'),
          ),
        ],
      ),
    );
    if (name != null && name.isNotEmpty) {
      await ref.read(databaseProvider).createPlaylist(name);
    }
  }

  Future<void> _import(BuildContext context, WidgetRef ref) async {
    final res = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['m3u8', 'm3u'],
      withData: true,
    );
    if (res == null || res.files.isEmpty) return;
    final f = res.files.single;
    final db = ref.read(databaseProvider);
    try {
      // withData:true 时走 bytes 分支。m3u8 是 UTF-8,必须 utf8.decode——
      // String.fromCharCodes 把每个字节当一个码元,会毁掉中文路径的多字节序列。
      final text = f.bytes != null
          ? utf8.decode(f.bytes!, allowMalformed: true)
          : await File(f.path!).readAsString();
      final baseDir = f.path != null ? p.dirname(f.path!) : '';
      // 曲库"绝对路径→指纹"表(正斜杠归一,与 parseM3u8 输出对齐)。
      final rows = await db.select(db.tracks).get();
      final map = {
        for (final t in rows) t.path.replaceAll(r'\', '/'): t.fingerprint,
      };
      final parsed = parseM3u8(text: text, baseDir: baseDir);
      final match = matchPaths(
        paths: parsed.paths,
        libraryPathToFp: map,
        caseInsensitive: Platform.isWindows,
      );
      if (!context.mounted) return;
      if (match.matchedFps.isEmpty) {
        // 零匹配不建空歌单(路径全对不上/曲库为空);只提示。
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('未匹配到曲库中的曲目(${match.unmatched} 首未匹配)')),
        );
        return;
      }
      final base = f.name.replaceAll(RegExp(r'\.m3u8?$'), '');
      final u = await db.createPlaylist(base.isEmpty ? '导入歌单' : base);
      for (final fp in match.matchedFps) {
        await db.addToPlaylist(u, fp);
      }
      if (context.mounted) {
        final suffix = match.unmatched > 0 ? '(${match.unmatched} 首未匹配)' : '';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已导入 ${match.matchedFps.length} 首$suffix')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('导入失败: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playlists = ref.watch(playlistsProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('歌单'),
        actions: [
          IconButton(
            icon: const Icon(Icons.file_download),
            tooltip: '导入 M3U8',
            onPressed: () => _import(context, ref),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _create(context, ref),
        child: const Icon(Icons.add),
      ),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.favorite, color: Colors.pink),
            title: const Text('我喜欢的'),
            onTap: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const FavoritesScreen())),
          ),
          const Divider(height: 1),
          ...?playlists.value?.map(
            (pl) => ListTile(
              leading: const Icon(Icons.queue_music),
              title: Text(pl.name),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) =>
                      PlaylistDetailScreen(uuid: pl.uuid, name: pl.name),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
