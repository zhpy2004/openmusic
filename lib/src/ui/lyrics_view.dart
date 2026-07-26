import 'dart:async';

import 'package:flutter/material.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

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
    _playingIndex =
        currentIndexAt(widget.lyrics.lines, widget.initialPosition);
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

  void _centerOn(int index) {
    if (_itemScroll.isAttached) {
      _itemScroll.scrollTo(
        index: index,
        alignment: 0.4, // 略高于正中,给下方留几行预览空间
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  // 浏览态下,把焦点同步到跨越视口中点的那一行。
  void _syncBrowseFocus() {
    if (!_browsing) return;
    final vis = _positions.itemPositions.value;
    if (vis.isEmpty) return;
    final center = vis.where(
      (p) => p.itemLeadingEdge <= 0.5 && p.itemTrailingEdge >= 0.5,
    );
    final idx = center.isNotEmpty ? center.first.index : vis.first.index;
    if (idx != _browseFocus) setState(() => _browseFocus = idx);
  }

  bool _onScroll(ScrollNotification n) {
    if (n is ScrollStartNotification && n.dragDetails != null) {
      _resumeTimer?.cancel();
      if (!_browsing) setState(() => _browsing = true);
    } else if (n is ScrollEndNotification && _browsing) {
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
    return false;
  }

  int get _focusedIndex =>
      _browsing ? (_browseFocus ?? _playingIndex) : _playingIndex;

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
    return NotificationListener<ScrollNotification>(
      onNotification: _onScroll,
      child: ScrollablePositionedList.builder(
        itemScrollController: _itemScroll,
        itemPositionsListener: _positions,
        initialScrollIndex: _playingIndex,
        initialAlignment: 0.4,
        itemCount: widget.lyrics.lines.length,
        itemBuilder: (context, i) => _row(context, i, i == focused),
      ),
    );
  }

  Widget _row(BuildContext context, int i, bool focused) {
    final line = widget.lyrics.lines[i];
    final theme = Theme.of(context);
    if (!focused) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
        child: Text(
          line.text,
          textAlign: TextAlign.center,
          style: theme.textTheme.titleMedium?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
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
              style: theme.textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.play_arrow),
            tooltip: '从这一句播放',
            onPressed: () => widget.onSeek(line.time),
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
            '无时间轴歌词',
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
