import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../app/providers.dart';
import '../data/database.dart';
import '../scraper/metadata_source.dart';
import '../scraper/scraper_service.dart';

/// 单曲手动刮削页:搜索三源候选 → 用户选 → 应用。
/// 封面/歌词写伴随文件、文本写覆盖表,**绝不改音频字节**(见 ScraperService)。
class ScrapeScreen extends ConsumerStatefulWidget {
  const ScrapeScreen({super.key, required this.track});
  final Track track;

  @override
  ConsumerState<ScrapeScreen> createState() => _ScrapeScreenState();
}

class _ScrapeScreenState extends ConsumerState<ScrapeScreen> {
  Future<ScrapeResults>? _future;
  MatchCandidate? _pickedMatch;
  LyricsCandidate? _pickedLyrics;
  bool _applyCover = true;
  // 文本修正默认关:在线源(iTunes/MusicBrainz)多返回繁体,会把简体标签库
  // 悄悄简→繁,多非用户所愿。封面/歌词默认应用,改标题/歌手需用户显式勾。
  bool _applyText = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _future = ref
        .read(scraperServiceProvider)
        .search(
          TrackQuery(
            title: widget.track.title,
            artist: widget.track.artist,
            album: widget.track.album,
            durationMs: widget.track.durationMs,
          ),
        );
  }

  Future<void> _apply() async {
    if (_pickedMatch == null && _pickedLyrics == null) return;
    final l10n = AppLocalizations.of(context)!;
    setState(() => _busy = true);
    try {
      await ref
          .read(scraperServiceProvider)
          .apply(
            widget.track,
            ScrapeSelection(
              match: _pickedMatch,
              applyCover: _applyCover && _pickedMatch?.coverUrl != null,
              applyText: _applyText && _pickedMatch != null,
              lyrics: _pickedLyrics,
            ),
          );
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l10n.applied)));
        Navigator.of(context).maybePop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l10n.applyFailed('$e'))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.scrapeTitle)),
      body: FutureBuilder<ScrapeResults>(
        future: _future,
        builder: (context, snap) {
          if (!snap.hasData && !snap.hasError) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(child: Text(l10n.searchFailed('${snap.error}')));
          }
          final r = snap.data!;
          return ListView(
            children: [
              ListTile(
                leading: const Icon(Icons.music_note),
                title: Text(widget.track.title),
                subtitle: Text(widget.track.artist),
              ),
              if (r.failedSources.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: Text(
                    l10n.sourcesUnavailable(r.failedSources.join(', ')),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              if (r.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Center(child: Text(l10n.noMatches)),
                ),
              if (r.matches.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                  child: Text(l10n.matchCandidates),
                ),
                // 用 ListTile + 单选图标而非 RadioListTile:后者的
                // groupValue/onChanged 在 Flutter 3.32+ 已废弃(改用 RadioGroup
                // 祖先),而这里两组单选交错在同一个 ListView 里,拆出两个
                // RadioGroup 反而要打散列表结构。
                for (final m in r.matches)
                  ListTile(
                    leading: Icon(
                      identical(_pickedMatch, m)
                          ? Icons.radio_button_checked
                          : Icons.radio_button_off,
                    ),
                    title: Text('${m.title} — ${m.artist}'),
                    subtitle: Text(m.album),
                    trailing: Text(m.source),
                    selected: identical(_pickedMatch, m),
                    onTap: () => setState(() => _pickedMatch = m),
                  ),
                CheckboxListTile(
                  value: _applyCover,
                  onChanged: (v) => setState(() => _applyCover = v ?? false),
                  title: Text(l10n.applyCover),
                ),
                CheckboxListTile(
                  value: _applyText,
                  onChanged: (v) => setState(() => _applyText = v ?? false),
                  title: Text(l10n.applyTextFix),
                ),
              ],
              if (r.lyrics.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                  child: Text(l10n.lyricsCandidates),
                ),
                for (final l in r.lyrics)
                  ListTile(
                    leading: Icon(
                      identical(_pickedLyrics, l)
                          ? Icons.radio_button_checked
                          : Icons.radio_button_off,
                    ),
                    title: Text('${l.title} — ${l.artist}'),
                    subtitle: Text(
                      '${l.source} · ${l.hasSynced ? l10n.lyricsSynced : l10n.lyricsPlain}',
                    ),
                    selected: identical(_pickedLyrics, l),
                    onTap: () => setState(() => _pickedLyrics = l),
                  ),
              ],
              Padding(
                padding: const EdgeInsets.all(16),
                child: FilledButton(
                  onPressed: _busy ? null : _apply,
                  child: Text(l10n.apply),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
