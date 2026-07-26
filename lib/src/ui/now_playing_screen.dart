import 'dart:io';

// hide RepeatMode：Flutter material 也导出了同名 RepeatMode
//（repeating_animation_builder），与 audio_engine.dart 的枚举 ambiguous。
import 'package:flutter/material.dart' hide RepeatMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/providers.dart';
import '../playback/audio_engine.dart';
import 'lyrics_view.dart';

class NowPlayingScreen extends ConsumerStatefulWidget {
  const NowPlayingScreen({super.key});

  @override
  ConsumerState<NowPlayingScreen> createState() => _NowPlayingScreenState();
}

class _NowPlayingScreenState extends ConsumerState<NowPlayingScreen> {
  bool _showLyrics = false;

  String _fmt(Duration d) {
    final m = d.inMinutes, s = d.inSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.watch(playbackControllerProvider);
    final track = controller.currentTrack;
    final engine = controller.engine;

    return Scaffold(
      appBar: AppBar(title: const Text('正在播放')),
      body: track == null
          ? const Center(child: Text('没有正在播放的曲目'))
          : Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  // 中央区:点一下在封面↔歌词间原地翻面。控制键/进度条不动。
                  Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () =>
                          setState(() => _showLyrics = !_showLyrics),
                      child: _showLyrics
                          ? _lyricsArea(track.path, engine)
                          : _coverArea(track.path),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    track.title,
                    style: Theme.of(context).textTheme.headlineSmall,
                    textAlign: TextAlign.center,
                  ),
                  Text(
                    track.artist,
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                  const SizedBox(height: 16),
                  StreamBuilder<Duration>(
                    stream: engine.positionStream,
                    initialData: engine.position,
                    builder: (context, posSnap) => StreamBuilder<Duration?>(
                      stream: engine.durationStream,
                      initialData: engine.duration,
                      builder: (context, durSnap) {
                        final pos = posSnap.data ?? Duration.zero;
                        final dur = durSnap.data ?? Duration.zero;
                        return Column(
                          children: [
                            Slider(
                              value: pos.inMilliseconds
                                  .clamp(0, dur.inMilliseconds)
                                  .toDouble(),
                              max: dur.inMilliseconds
                                  .clamp(1, 1 << 62)
                                  .toDouble(),
                              onChanged: (v) => engine.seek(
                                Duration(milliseconds: v.round()),
                              ),
                            ),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [Text(_fmt(pos)), Text(_fmt(dur))],
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                  // 6 个控制键在窄屏(手机 ~360dp)会横向溢出。用 Wrap 而非
                  // FittedBox:放不下时换行,保持按钮 48dp 触控目标(a11y),
                  // 不缩小成难点的小图标;放得下(桌面/平板)仍是一行。
                  Wrap(
                    alignment: WrapAlignment.center,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Consumer(
                        builder: (context, ref, _) {
                          final fp = track.fingerprint;
                          final isFav =
                              ref.watch(isFavoriteProvider(fp)).value == true;
                          return IconButton(
                            icon: Icon(
                              isFav ? Icons.favorite : Icons.favorite_border,
                              color: isFav ? Colors.pink : null,
                            ),
                            tooltip: isFav ? '取消收藏' : '收藏',
                            onPressed: () =>
                                ref.read(databaseProvider).toggleFavorite(fp),
                          );
                        },
                      ),
                      IconButton(
                        icon: Icon(
                          Icons.shuffle,
                          color: controller.shuffle
                              ? Theme.of(context).colorScheme.primary
                              : null,
                        ),
                        onPressed: controller.toggleShuffle,
                      ),
                      IconButton(
                        iconSize: 48,
                        icon: const Icon(Icons.skip_previous),
                        onPressed: engine.previous,
                      ),
                      IconButton(
                        iconSize: 64,
                        icon: Icon(
                          controller.playing
                              ? Icons.pause_circle
                              : Icons.play_circle,
                        ),
                        onPressed: () => controller.playing
                            ? engine.pause()
                            : engine.play(),
                      ),
                      IconButton(
                        iconSize: 48,
                        icon: const Icon(Icons.skip_next),
                        onPressed: engine.next,
                      ),
                      IconButton(
                        icon: Icon(switch (controller.repeatMode) {
                          RepeatMode.off => Icons.repeat,
                          RepeatMode.all => Icons.repeat_on,
                          RepeatMode.one => Icons.repeat_one_on,
                        }),
                        onPressed: controller.cycleRepeatMode,
                      ),
                    ],
                  ),
                ],
              ),
            ),
    );
  }

  Widget _coverArea(String path) {
    return Center(
      child: Consumer(
        builder: (context, ref, _) {
          final cover = ref.watch(coverArtProvider(path)).value;
          if (cover == null) {
            return const Icon(Icons.album, size: 160);
          }
          return ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.file(
              File(cover),
              width: 160,
              height: 160,
              fit: BoxFit.cover,
              // 封面文件被删/损坏时不崩,回落占位图
              errorBuilder: (_, _, _) => const Icon(Icons.album, size: 160),
            ),
          );
        },
      ),
    );
  }

  Widget _lyricsArea(String path, AudioEngine engine) {
    return Consumer(
      builder: (context, ref, _) {
        final async = ref.watch(lyricsProvider(path));
        return async.when(
          loading: () => const SizedBox.shrink(),
          error: (_, _) => const Center(child: Text('暂无歌词')),
          data: (lyrics) => lyrics == null
              ? const Center(child: Text('暂无歌词'))
              : LyricsView(
                  // 按曲目 path 挂 key:切歌时强制重建 State,避免复用旧
                  // State 导致 _playingIndex/订阅停留在上一首。
                  key: ValueKey(path),
                  lyrics: lyrics,
                  positionStream: engine.positionStream,
                  initialPosition: engine.position,
                  onSeek: engine.seek,
                ),
        );
      },
    );
  }
}
