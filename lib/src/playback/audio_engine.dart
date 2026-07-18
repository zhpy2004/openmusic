enum RepeatMode { off, all, one }

/// 播放内核抽象（spec §4/§5）：实现持有内部播放列表以保证 gapless。
/// index 语义：当前曲目在"原始入队顺序"中的下标（shuffle 由实现内部处理，
/// index 始终指向原始列表位置——MediaKitEngine 通过内部下标翻译兑现此契约）。
abstract class AudioEngine {
  Future<void> setQueue(
    List<String> paths, {
    int startIndex = 0,
    bool play = true,
  });
  Future<void> play();
  Future<void> pause();
  Future<void> next();
  Future<void> previous();
  Future<void> jump(int index);
  Future<void> seek(Duration position);
  Future<void> setShuffle(bool enabled);
  Future<void> setRepeatMode(RepeatMode mode);

  Stream<int> get indexStream;
  Stream<bool> get playingStream;
  Stream<Duration> get positionStream;
  Stream<Duration?> get durationStream;

  /// 当前播放位置/时长的同步快照。position/durationStream 是 broadcast 流、
  /// 不回放,UI 中途订阅（如打开正在播放页）会拿不到已发生的时长事件——用这两个
  /// getter 播种 StreamBuilder.initialData,让中途打开也能立刻显示正确总时长。
  Duration get position;
  Duration? get duration;

  Future<void> dispose();
}
