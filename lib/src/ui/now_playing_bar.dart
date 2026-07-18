import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/providers.dart';
import 'now_playing_screen.dart';

class NowPlayingBar extends ConsumerWidget {
  const NowPlayingBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(playbackControllerProvider);
    final track = controller.currentTrack;
    if (track == null) return const SizedBox.shrink();

    return Material(
      elevation: 8,
      child: ListTile(
        leading: const Icon(Icons.album),
        title: Text(track.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          track.artist,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        onTap: () => Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const NowPlayingScreen())),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.skip_previous),
              onPressed: controller.engine.previous,
            ),
            IconButton(
              icon: Icon(controller.playing ? Icons.pause : Icons.play_arrow),
              onPressed: () => controller.playing
                  ? controller.engine.pause()
                  : controller.engine.play(),
            ),
            IconButton(
              icon: const Icon(Icons.skip_next),
              onPressed: controller.engine.next,
            ),
          ],
        ),
      ),
    );
  }
}
