import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../app/providers.dart';
import '../library/m3u8.dart';
import 'now_playing_bar.dart';
import 'scrape_screen.dart';

class PlaylistDetailScreen extends ConsumerWidget {
  const PlaylistDetailScreen({
    super.key,
    required this.uuid,
    required this.name,
  });
  final String uuid;
  final String name;

  Future<void> _export(BuildContext context, WidgetRef ref) async {
    final db = ref.read(databaseProvider);
    final items = await db.watchPlaylistItems(uuid).first;
    final present = items.where((e) => e.track != null).toList();
    final missing = items.length - present.length;
    if (!context.mounted) return;
    final savePath = await FilePicker.platform.saveFile(
      dialogTitle: '导出歌单',
      fileName: '$name.m3u8',
    );
    if (savePath == null) return;
    final baseDir = p.dirname(savePath);
    final text = serializeM3u8(
      baseDir: baseDir,
      entries: present
          .map(
            (e) => M3u8Entry(
              absPath: e.track!.path,
              artist: e.track!.artist,
              title: e.track!.title,
              durationSec: (e.track!.durationMs / 1000).round(),
            ),
          )
          .toList(),
    );
    try {
      await File(savePath).writeAsString(text);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(missing > 0 ? '已导出($missing 首缺失未含)' : '已导出')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('导出失败: $e')));
      }
    }
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('删除歌单「$name」?'),
        content: const Text('歌单定义会被删除(曲目文件不受影响)。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await ref.read(databaseProvider).deletePlaylist(uuid);
      if (context.mounted) Navigator.of(context).maybePop();
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final itemsAsync = ref.watch(playlistItemsProvider(uuid));
    return Scaffold(
      appBar: AppBar(
        title: Text(name),
        actions: [
          IconButton(
            icon: const Icon(Icons.ios_share),
            tooltip: '导出 M3U8',
            onPressed: () => _export(context, ref),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: '删除歌单',
            onPressed: () => _confirmDelete(context, ref),
          ),
        ],
      ),
      // push 进来的子页自带迷你播放栏(主壳的那份被整页路由盖住了)。
      bottomNavigationBar: const NowPlayingBar(),
      body: itemsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('加载失败: $e')),
        data: (items) => items.isEmpty
            ? const Center(child: Text('空歌单——从曲库长按曲目加入'))
            : ListView.builder(
                itemCount: items.length,
                itemBuilder: (context, i) {
                  final it = items[i];
                  final t = it.track;
                  final disabled = Theme.of(context).disabledColor;
                  return ListTile(
                    leading: Icon(
                      Icons.music_note,
                      color: t == null ? disabled : null,
                    ),
                    title: Text(
                      t?.title ?? '文件缺失',
                      style: t == null ? TextStyle(color: disabled) : null,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: t == null ? Text(it.fp) : Text(t.artist),
                    trailing: PopupMenuButton<String>(
                      icon: const Icon(Icons.more_vert),
                      onSelected: (v) {
                        if (v == 'remove') {
                          ref
                              .read(databaseProvider)
                              .removeFromPlaylist(uuid, it.fp);
                        }
                        if (v == 'scrape' && t != null) {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => ScrapeScreen(track: t),
                            ),
                          );
                        }
                      },
                      itemBuilder: (_) => [
                        const PopupMenuItem(value: 'remove', child: Text('移除')),
                        // 缺失曲目没有 tracks 行,无从刮削
                        if (t != null)
                          const PopupMenuItem(
                            value: 'scrape',
                            child: Text('刮削'),
                          ),
                      ],
                    ),
                    onTap: t == null
                        ? null
                        : () {
                            final playable = items
                                .where((e) => e.track != null)
                                .map((e) => e.track!)
                                .toList();
                            final start = playable.indexWhere(
                              (e) => e.fingerprint == it.fp,
                            );
                            ref
                                .read(playbackControllerProvider.notifier)
                                .playTracks(
                                  playable,
                                  startIndex: start < 0 ? 0 : start,
                                );
                          },
                  );
                },
              ),
      ),
    );
  }
}
