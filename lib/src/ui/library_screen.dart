import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/providers.dart';
import '../data/database.dart';

class LibraryScreen extends ConsumerWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tracksAsync = ref.watch(trackListProvider);

    return Material(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8),
            child: TextField(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: '搜索标题 / 歌手 / 专辑',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (v) =>
                  ref.read(searchQueryProvider.notifier).state = v,
            ),
          ),
          Expanded(
            child: tracksAsync.when(
              // 每次击键 searchQueryProvider 变更会让 AsyncValue 过一帧
              // AsyncLoading；跳过它以保留旧列表，避免列表区闪 spinner。
              skipLoadingOnReload: true,
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('加载失败: $e')),
              data: (tracks) => tracks.isEmpty
                  ? const Center(child: Text('曲库为空——到设置里添加文件夹并扫描'))
                  : ListView.builder(
                      itemCount: tracks.length,
                      itemBuilder: (context, i) {
                        final t = tracks[i];
                        return ListTile(
                          leading: const Icon(Icons.music_note),
                          title: Text(
                            t.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            t.artist,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: _TrackMenu(track: t),
                          onTap: () => ref
                              .read(playbackControllerProvider.notifier)
                              .playTracks(tracks, startIndex: i),
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 曲目行尾:红心(收藏切换)+ ⋮ 菜单(加入歌单)。
class _TrackMenu extends ConsumerWidget {
  const _TrackMenu({required this.track});
  final Track track;

  // playlists 由调用方从已 watch 的 playlistsProvider 同步传入——避免在回调里
  // await drift 流首值(fake-async 窗口里不可靠,弹不出 sheet)。
  Future<void> _addToPlaylist(
    BuildContext context,
    WidgetRef ref,
    List<Playlist> playlists,
  ) async {
    final uuid = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final pl in playlists)
              ListTile(
                leading: const Icon(Icons.queue_music),
                title: Text(pl.name),
                onTap: () => Navigator.pop(ctx, pl.uuid),
              ),
            if (playlists.isEmpty)
              const ListTile(title: Text('还没有歌单,去「歌单」页新建')),
          ],
        ),
      ),
    );
    if (uuid != null) {
      await ref.read(databaseProvider).addToPlaylist(uuid, track.fingerprint);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isFav =
        ref.watch(isFavoriteProvider(track.fingerprint)).value == true;
    final playlists = ref.watch(playlistsProvider).value ?? const <Playlist>[];
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: Icon(
            isFav ? Icons.favorite : Icons.favorite_border,
            color: isFav ? Colors.pink : null,
          ),
          tooltip: isFav ? '取消收藏' : '收藏',
          onPressed: () =>
              ref.read(databaseProvider).toggleFavorite(track.fingerprint),
        ),
        PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert),
          onSelected: (v) {
            if (v == 'add') _addToPlaylist(context, ref, playlists);
          },
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'add', child: Text('加入歌单')),
          ],
        ),
      ],
    );
  }
}
