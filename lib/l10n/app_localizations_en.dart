// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get cancel => 'Cancel';

  @override
  String get delete => 'Delete';

  @override
  String get create => 'Create';

  @override
  String get apply => 'Apply';

  @override
  String get close => 'Close';

  @override
  String get clear => 'Clear';

  @override
  String get remove => 'Remove';

  @override
  String get skip => 'Skip';

  @override
  String get start => 'Start';

  @override
  String get next => 'Next';

  @override
  String get finish => 'Done';

  @override
  String get scrape => 'Scrape';

  @override
  String get favorite => 'Add to favorites';

  @override
  String get unfavorite => 'Remove from favorites';

  @override
  String loadFailed(String error) {
    return 'Failed to load: $error';
  }

  @override
  String get tabLibrary => 'Library';

  @override
  String get tabPlaylists => 'Playlists';

  @override
  String get tabSettings => 'Settings';

  @override
  String get searchHint => 'Search title, artist, or album';

  @override
  String get libraryEmpty =>
      'Your library is empty — add a folder in Settings and scan';

  @override
  String get noPlaylistsYet =>
      'No playlists yet — create one on the Playlists tab';

  @override
  String get addToPlaylist => 'Add to playlist';

  @override
  String get favoritesTitle => 'Favorites';

  @override
  String get favoritesEmpty => 'No favorites yet — tap the ♥ on any track';

  @override
  String get newPlaylist => 'New playlist';

  @override
  String get playlistNameHint => 'Playlist name';

  @override
  String get importM3u8 => 'Import M3U8';

  @override
  String get importedPlaylistName => 'Imported playlist';

  @override
  String importNoMatch(int count) {
    return 'Nothing matched your library ($count entries unmatched)';
  }

  @override
  String importedTracks(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count tracks',
      one: '1 track',
    );
    return 'Imported $_temp0';
  }

  @override
  String importedTracksWithUnmatched(int count, int unmatched) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count tracks',
      one: '1 track',
    );
    return 'Imported $_temp0 ($unmatched unmatched)';
  }

  @override
  String importFailed(String error) {
    return 'Import failed: $error';
  }

  @override
  String get exportPlaylist => 'Export playlist';

  @override
  String get exportM3u8 => 'Export M3U8';

  @override
  String get deletePlaylist => 'Delete playlist';

  @override
  String get exported => 'Exported';

  @override
  String exportedWithMissing(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count missing tracks',
      one: '1 missing track',
    );
    return 'Exported ($_temp0 excluded)';
  }

  @override
  String exportFailed(String error) {
    return 'Export failed: $error';
  }

  @override
  String deletePlaylistTitle(String name) {
    return 'Delete playlist \"$name\"?';
  }

  @override
  String get deletePlaylistBody =>
      'The playlist will be removed. Your audio files are not affected.';

  @override
  String get playlistEmpty =>
      'Empty playlist — long-press a track in your library to add it';

  @override
  String get fileMissing => 'File missing';

  @override
  String get nowPlaying => 'Now playing';

  @override
  String get nothingPlaying => 'Nothing is playing';

  @override
  String get noLyrics => 'No lyrics';

  @override
  String get playFromHere => 'Play from this line';

  @override
  String get lyricsNoTimestamps => 'Lyrics without timestamps';

  @override
  String get musicFolders => 'Music folders';

  @override
  String get addSystemMusicFolder => 'Add system music folder';

  @override
  String get addFolder => 'Add folder…';

  @override
  String get scanLibrary => 'Scan library';

  @override
  String scanning(int done, int total) {
    return 'Scanning $done/$total';
  }

  @override
  String problemFiles(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count problem files',
      one: '1 problem file',
    );
    return '$_temp0';
  }

  @override
  String lastScanProblems(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count problems',
      one: '1 problem',
    );
    return 'Last scan reported $_temp0';
  }

  @override
  String get needAudioPermission => 'Audio permission is required to scan';

  @override
  String scanFailed(String error) {
    return 'Scan failed: $error';
  }

  @override
  String get batchFill => 'Fill in missing covers and lyrics';

  @override
  String get batchFillSubtitle =>
      'Automatically fills tracks missing artwork or lyrics (can be cancelled)';

  @override
  String get language => 'Language';

  @override
  String get languageSystem => 'System default';

  @override
  String get scrapeTitle => 'Scrape';

  @override
  String get applied => 'Applied';

  @override
  String applyFailed(String error) {
    return 'Failed to apply: $error';
  }

  @override
  String searchFailed(String error) {
    return 'Search failed: $error';
  }

  @override
  String sourcesUnavailable(String sources) {
    return 'Currently unavailable: $sources';
  }

  @override
  String get noMatches => 'No matches — try again';

  @override
  String get matchCandidates => 'Matches (artwork + text)';

  @override
  String get lyricsCandidates => 'Lyrics';

  @override
  String get applyCover => 'Apply artwork';

  @override
  String get applyTextFix => 'Apply text corrections';

  @override
  String get lyricsSynced => 'synced';

  @override
  String get lyricsPlain => 'plain text';

  @override
  String get batchNothingToFill =>
      'Nothing to fill — every track already has artwork and lyrics';

  @override
  String batchDone(int covers, int lyrics, int skipped) {
    return 'Done — $covers covers, $lyrics lyrics, $skipped not found';
  }

  @override
  String batchProgress(int done, int total) {
    return 'Filling covers and lyrics $done/$total';
  }

  @override
  String batchFilledSoFar(int covers, int lyrics) {
    return 'So far: $covers covers, $lyrics lyrics';
  }

  @override
  String get wizardTitle => 'Setup';

  @override
  String get wizardWelcome => 'Welcome to OpenMusic';

  @override
  String get wizardIntro =>
      'Three steps to your library: pick a folder → scan → fill in covers and lyrics';

  @override
  String get wizardPickFolder => 'Choose your music folder';

  @override
  String get wizardNoFolders => 'No folders yet — add one below';

  @override
  String get wizardScanTitle => 'Scan your library';

  @override
  String get wizardScanning => 'Scanning…';

  @override
  String get wizardStartScan => 'Start scan';

  @override
  String get wizardFillTitle => 'Fill in covers and lyrics';

  @override
  String get wizardSkipStep => 'Skip this step';

  @override
  String get wizardComplete => 'All set';

  @override
  String get wizardEnterLibrary => 'Open library';

  @override
  String problemRootUnreachable(String path) {
    return 'Folder unreachable: $path (tracks under it were left untouched)';
  }

  @override
  String problemFileFailed(String path, String error) {
    return '$path: $error';
  }

  @override
  String problemBatchWriteFailed(int count, String error) {
    return 'Batch write failed ($count entries): $error';
  }
}
