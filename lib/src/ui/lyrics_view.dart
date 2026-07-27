import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../../l10n/app_localizations.dart';
import '../lyrics/lrc.dart';

/// 滚轮式行级歌词。synced:当前行居中高亮 + 左时间戳 + 右 ▶ seek,随进度滚动。
/// 纯文本:静态可滚动文本,不高亮/不 seek。
class LyricsView extends StatefulWidget {
  const LyricsView({
    super.key,
    required this.lyrics,
    required this.positionStream,
    required this.initialPosition,
    required this.onSeek,
  });

  final Lyrics lyrics;
  final Stream<Duration> positionStream;
  final Duration initialPosition;
  final ValueChanged<Duration> onSeek;

  @override
  State<LyricsView> createState() => _LyricsViewState();
}

class _LyricsViewState extends State<LyricsView> {
  /// 焦点位:行首对齐到视口的这个比例(略高于正中,给下方留几行预览空间)。
  /// 滚动定位与浏览态焦点判定共用,保证按 ▶ 后居中的行就是拿到框的行。
  static const _kAlignment = 0.4;

  final _itemScroll = ItemScrollController();
  final _positions = ItemPositionsListener.create();
  StreamSubscription<Duration>? _sub;
  int _playingIndex = 0;
  bool _browsing = false;
  int? _browseFocus;
  Timer? _resumeTimer;

  @override
  void initState() {
    super.initState();
    _playingIndex = currentIndexAt(widget.lyrics.lines, widget.initialPosition);
    if (widget.lyrics.synced) {
      _sub = widget.positionStream.listen(_onPosition);
    }
    _positions.itemPositions.addListener(_syncBrowseFocus);
  }

  void _onPosition(Duration pos) {
    final idx = currentIndexAt(widget.lyrics.lines, pos);
    if (idx == _playingIndex) return;
    setState(() => _playingIndex = idx);
    if (!_browsing) _centerOn(idx);
  }

  /// SPL 把 padding 折进"定位目标"所在的 center sliver:目标是第 0 行时,
  /// 顶部 padding(半个视口,即 0.5)会被算进定位块,行被推低半个视口。
  /// 定位到第 0 行时把对齐补偿回来(负对齐 = 定位块顶伸出视口上沿)。
  double _alignmentFor(int index) =>
      index == 0 ? _kAlignment - 0.5 : _kAlignment;

  void _centerOn(int index) {
    if (_itemScroll.isAttached) {
      _itemScroll.scrollTo(
        index: index,
        alignment: _alignmentFor(index),
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  // 浏览态下,把焦点同步到"焦点位"的那一行:取行首离 _kAlignment 最近的行,
  // 与 _centerOn 的滚动对齐一致(itemPositions 是无序集合,不能取 first)。
  void _syncBrowseFocus() {
    if (!_browsing) return;
    final vis = _positions.itemPositions.value;
    if (vis.isEmpty) return;
    final idx = vis
        .reduce(
          (a, b) =>
              (a.itemLeadingEdge - _kAlignment).abs() <
                  (b.itemLeadingEdge - _kAlignment).abs()
              ? a
              : b,
        )
        .index;
    if (idx != _browseFocus) setState(() => _browseFocus = idx);
  }

  void _armResumeTimer() {
    _resumeTimer?.cancel();
    _resumeTimer = Timer(const Duration(seconds: 4), () {
      if (!mounted) return;
      setState(() {
        _browsing = false;
        _browseFocus = null;
      });
      _centerOn(_playingIndex);
    });
  }

  bool _onScroll(ScrollNotification n) {
    if (n is ScrollStartNotification && n.dragDetails != null) {
      _resumeTimer?.cancel();
      if (!_browsing) setState(() => _browsing = true);
    } else if (n is ScrollEndNotification && _browsing) {
      _armResumeTimer();
    }
    return false;
  }

  // 桌面鼠标滚轮不产生带 dragDetails 的 ScrollStart(只有触摸拖动有),
  // 浏览态从前永远不会被滚轮触发——焦点框不跟随、自动跟随还会拽回列表。
  // 用 Listener 捕获滚轮信号进浏览态;程序化 scrollTo 不产生 PointerSignal,
  // 不会误触发(保住 T5 的恢复计时器自循环修复)。
  void _onPointerSignal(PointerSignalEvent e) {
    if (e is! PointerScrollEvent) return;
    if (!_browsing) setState(() => _browsing = true);
    _armResumeTimer();
  }

  int get _focusedIndex =>
      _browsing ? (_browseFocus ?? _playingIndex) : _playingIndex;

  /// 点行(或行内 ▶)从该句播放:立即退出浏览态、把该行设为焦点并居中,
  /// 不等 4 秒恢复计时器。乐观置 _playingIndex=index(seek 后首个进度 tick
  /// 会得到同一下标,提前设置让高亮零延迟)。
  void _seekToLine(int index) {
    widget.onSeek(widget.lyrics.lines[index].time);
    _resumeTimer?.cancel();
    setState(() {
      _browsing = false;
      _browseFocus = null;
      _playingIndex = index;
    });
    _centerOn(index);
  }

  @override
  void dispose() {
    _sub?.cancel();
    _resumeTimer?.cancel();
    _positions.itemPositions.removeListener(_syncBrowseFocus);
    super.dispose();
  }

  static String _fmt(Duration d) {
    final m = d.inMinutes, s = d.inSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.lyrics.synced) return _plain(context);
    final focused = _focusedIndex;
    return Listener(
      onPointerSignal: _onPointerSignal,
      child: NotificationListener<ScrollNotification>(
        onNotification: _onScroll,
        // 上下各留约半个视口的内边距,让第一句/最后一句也能滚进焦点位
        // (否则列表滚到边缘时,头尾几行永远够不到 _kAlignment)。
        child: LayoutBuilder(
          builder: (context, constraints) => ScrollablePositionedList.builder(
            itemScrollController: _itemScroll,
            itemPositionsListener: _positions,
            initialScrollIndex: _playingIndex,
            initialAlignment: _alignmentFor(_playingIndex),
            padding: EdgeInsets.symmetric(vertical: constraints.maxHeight / 2),
            itemCount: widget.lyrics.lines.length,
            itemBuilder: (context, i) => _row(context, i, i == focused),
          ),
        ),
      ),
    );
  }

  // 行本身不挂点击手势:点歌词区任意处(除 ▶)交给外层翻回封面;跳转只走
  // 焦点框右侧的 ▶(浏览态下焦点框跟随视口中心,任何行都能滚到中心点到 ▶)。
  Widget _row(BuildContext context, int i, bool focused) {
    final line = widget.lyrics.lines[i];
    final theme = Theme.of(context);
    if (!focused) {
      // 浏览时当前播放行保持全亮(不淡化),滚开了也能一眼看到唱到哪句。
      final playing = i == _playingIndex;
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
        child: Text(
          line.text,
          textAlign: TextAlign.center,
          style: theme.textTheme.titleMedium?.copyWith(
            color: playing
                ? theme.colorScheme.onSurface
                : theme.colorScheme.onSurface.withValues(alpha: 0.4),
            fontWeight: playing ? FontWeight.w600 : null,
          ),
        ),
      );
    }
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 44,
            child: Text(_fmt(line.time), style: theme.textTheme.labelSmall),
          ),
          Expanded(
            child: Text(
              line.text,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.play_arrow),
            tooltip: AppLocalizations.of(context)!.playFromHere,
            onPressed: () => _seekToLine(i),
          ),
        ],
      ),
    );
  }

  Widget _plain(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 4),
          child: Text(
            AppLocalizations.of(context)!.lyricsNoTimestamps,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
            ),
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: widget.lyrics.lines.length,
            itemBuilder: (c, i) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
              child: Text(
                widget.lyrics.lines[i].text,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
