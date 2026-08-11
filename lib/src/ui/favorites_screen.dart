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
                // 本机没有的曲目**置灰保留,不丢弃**(与歌单详情页一致)。
                // 丢弃的话,同步过来的收藏会整个"人间蒸发"——M3-B 之后这是常态
                // 而非边缘情况:元数据先到、文件要等 M3-C 才搬过来。
                final favFpList = favFps.value!;
                final playable = [
                  for (final fp in favFpList)
                    if (byFp[fp] != null) byFp[fp]!,
                ];
                if (favFpList.isEmpty) {
                  return Center(child: Text(l10n.favoritesEmpty));
                }
                return ListView.builder(
                  itemCount: favFpList.length,
                  itemBuilder: (context, i) {
                    final t = byFp[favFpList[i]];
                    final missing = t == null;
                    return ListTile(
                      enabled: !missing,
                      leading: Icon(
                        Icons.favorite,
                        color: missing ? Theme.of(context).disabledColor : Colors.pink,
                      ),
                      title: Text(
                        t?.title ?? l10n.fileMissing,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        t?.artist ?? '',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onTap: missing
                          ? null
                          : () => ref
                                .read(playbackControllerProvider.notifier)
                                .playTracks(
                                  playable,
                                  startIndex: playable.indexOf(t),
                                ),
                    );
                  },
                );
              },
            ),
    );
  }
}
