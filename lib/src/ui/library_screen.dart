import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../app/providers.dart';
import '../data/database.dart';
import 'scrape_screen.dart';

class LibraryScreen extends ConsumerWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final tracksAsync = ref.watch(trackListProvider);
    final searching = ref.watch(searchQueryProvider).trim().isNotEmpty;

    return Material(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8),
            child: TextField(
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: l10n.searchHint,
                border: const OutlineInputBorder(),
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
              error: (e, _) => Center(child: Text(l10n.loadFailed('$e'))),
              data: (tracks) => tracks.isEmpty
                  // 搜索无匹配 ≠ 曲库为空:后者提示去加文件夹,前者只说没搜到。
                  ? Center(
                      child: Text(
                        searching ? l10n.searchNoResults : l10n.libraryEmpty,
                      ),
                    )
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
              ListTile(title: Text(AppLocalizations.of(ctx)!.noPlaylistsYet)),
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
    final l10n = AppLocalizations.of(context)!;
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
          tooltip: isFav ? l10n.unfavorite : l10n.favorite,
          onPressed: () =>
              ref.read(databaseProvider).toggleFavorite(track.fingerprint),
        ),
        PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert),
          onSelected: (v) {
            if (v == 'add') _addToPlaylist(context, ref, playlists);
            if (v == 'scrape') {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => ScrapeScreen(track: track)),
              );
            }
          },
          itemBuilder: (_) => [
            PopupMenuItem(value: 'add', child: Text(l10n.addToPlaylist)),
            PopupMenuItem(value: 'scrape', child: Text(l10n.scrape)),
          ],
        ),
      ],
    );
  }
}
