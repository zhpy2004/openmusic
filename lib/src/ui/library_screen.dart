import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/providers.dart';

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
