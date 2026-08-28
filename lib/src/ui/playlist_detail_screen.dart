import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../l10n/app_localizations.dart';
import '../app/providers.dart';
import '../library/m3u8.dart';
import 'fetch_single_track.dart';
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
    final l10n = AppLocalizations.of(context)!;
    final db = ref.read(databaseProvider);
    final items = await db.watchPlaylistItems(uuid).first;
    final present = items.where((e) => e.track != null).toList();
    final missing = items.length - present.length;
    if (!context.mounted) return;
    final savePath = await FilePicker.platform.saveFile(
      dialogTitle: l10n.exportPlaylist,
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
          SnackBar(
            content: Text(
              missing > 0 ? l10n.exportedWithMissing(missing) : l10n.exported,
            ),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l10n.exportFailed('$e'))));
      }
    }
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context)!;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.deletePlaylistTitle(name)),
        content: Text(l10n.deletePlaylistBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.delete),
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
    final l10n = AppLocalizations.of(context)!;
    final itemsAsync = ref.watch(playlistItemsProvider(uuid));
    return Scaffold(
      appBar: AppBar(
        title: Text(name),
        actions: [
          IconButton(
            icon: const Icon(Icons.ios_share),
            tooltip: l10n.exportM3u8,
            onPressed: () => _export(context, ref),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: l10n.deletePlaylist,
            onPressed: () => _confirmDelete(context, ref),
          ),
        ],
      ),
      // push 进来的子页自带迷你播放栏(主壳的那份被整页路由盖住了)。
      bottomNavigationBar: const NowPlayingBar(),
      body: itemsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(l10n.loadFailed('$e'))),
        data: (items) => items.isEmpty
            ? Center(child: Text(l10n.playlistEmpty))
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
                      t?.title ?? l10n.fileMissing,
                      style: t == null ? TextStyle(color: disabled) : null,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: t == null ? Text(it.fp) : Text(t.artist),
                    trailing: t == null
                        ? IconButton(
                            icon: const Icon(Icons.download_for_offline),
                            tooltip: l10n.syncFetchThisTrack,
                            onPressed: () => fetchSingleTrack(context, ref, it.fp),
                          )
                        : PopupMenuButton<String>(
                            icon: const Icon(Icons.more_vert),
                            onSelected: (v) {
                              if (v == 'remove') {
                                ref
                                    .read(databaseProvider)
                                    .removeFromPlaylist(uuid, it.fp);
                              }
                              if (v == 'scrape') {
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => ScrapeScreen(track: t),
                                  ),
                                );
                              }
                            },
                            itemBuilder: (_) => [
                              PopupMenuItem(
                                value: 'remove',
                                child: Text(l10n.remove),
                              ),
                              PopupMenuItem(
                                value: 'scrape',
                                child: Text(l10n.scrape),
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
