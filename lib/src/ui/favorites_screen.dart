import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../app/providers.dart';
import 'now_playing_bar.dart';

class FavoritesScreen extends ConsumerWidget {
  const FavoritesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final favFps = ref.watch(favoritesProvider);
    final tracksAsync = ref.watch(trackListProvider);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.favoritesTitle)),
      // 主壳的迷你播放栏只在 tab 页显示;push 进来的子页要自带一份,否则播放栏消失。
      bottomNavigationBar: const NowPlayingBar(),
      body: (favFps.value == null || tracksAsync.value == null)
          ? const Center(child: CircularProgressIndicator())
          : Builder(
              builder: (context) {
                // favorites 按 addedAt 倒序;按该顺序渲染,而不是曲库顺序。
                final byFp = {
                  for (final t in tracksAsync.value!) t.fingerprint: t,
                };
                final favTracks = [
                  for (final fp in favFps.value!)
                    if (byFp[fp] != null) byFp[fp]!,
                ];
                if (favTracks.isEmpty) {
                  return Center(child: Text(l10n.favoritesEmpty));
                }
                return ListView.builder(
                  itemCount: favTracks.length,
                  itemBuilder: (context, i) {
                    final t = favTracks[i];
                    return ListTile(
                      leading: const Icon(Icons.favorite, color: Colors.pink),
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
                      onTap: () => ref
                          .read(playbackControllerProvider.notifier)
                          .playTracks(favTracks, startIndex: i),
                    );
                  },
                );
              },
            ),
    );
  }
}
