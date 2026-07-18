// hide RepeatMode：Flutter material 也导出了同名 RepeatMode
//（repeating_animation_builder），与 audio_engine.dart 的枚举 ambiguous。
import 'package:flutter/material.dart' hide RepeatMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/providers.dart';
import '../playback/audio_engine.dart';

class NowPlayingScreen extends ConsumerWidget {
  const NowPlayingScreen({super.key});

  String _fmt(Duration d) {
    final m = d.inMinutes, s = d.inSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.album, size: 160),
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
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
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
                        onPressed: () =>
                            controller.playing ? engine.pause() : engine.play(),
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
}
