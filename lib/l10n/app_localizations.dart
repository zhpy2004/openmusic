import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('zh'),
  ];

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// No description provided for @create.
  ///
  /// In en, this message translates to:
  /// **'Create'**
  String get create;

  /// No description provided for @apply.
  ///
  /// In en, this message translates to:
  /// **'Apply'**
  String get apply;

  /// No description provided for @close.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get close;

  /// No description provided for @clear.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get clear;

  /// No description provided for @remove.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get remove;

  /// No description provided for @skip.
  ///
  /// In en, this message translates to:
  /// **'Skip'**
  String get skip;

  /// No description provided for @start.
  ///
  /// In en, this message translates to:
  /// **'Start'**
  String get start;

  /// No description provided for @next.
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get next;

  /// No description provided for @finish.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get finish;

  /// No description provided for @scrape.
  ///
  /// In en, this message translates to:
  /// **'Scrape'**
  String get scrape;

  /// No description provided for @favorite.
  ///
  /// In en, this message translates to:
  /// **'Add to favorites'**
  String get favorite;

  /// No description provided for @unfavorite.
  ///
  /// In en, this message translates to:
  /// **'Remove from favorites'**
  String get unfavorite;

  /// No description provided for @loadFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to load: {error}'**
  String loadFailed(String error);

  /// No description provided for @tabLibrary.
  ///
  /// In en, this message translates to:
  /// **'Library'**
  String get tabLibrary;

  /// No description provided for @tabPlaylists.
  ///
  /// In en, this message translates to:
  /// **'Playlists'**
  String get tabPlaylists;

  /// No description provided for @tabSettings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get tabSettings;

  /// No description provided for @searchHint.
  ///
  /// In en, this message translates to:
  /// **'Search title, artist, or album'**
  String get searchHint;

  /// No description provided for @libraryEmpty.
  ///
  /// In en, this message translates to:
  /// **'Your library is empty — add a folder in Settings and scan'**
  String get libraryEmpty;

  /// No description provided for @noPlaylistsYet.
  ///
  /// In en, this message translates to:
  /// **'No playlists yet — create one on the Playlists tab'**
  String get noPlaylistsYet;

  /// No description provided for @addToPlaylist.
  ///
  /// In en, this message translates to:
  /// **'Add to playlist'**
  String get addToPlaylist;

  /// No description provided for @favoritesTitle.
  ///
  /// In en, this message translates to:
  /// **'Favorites'**
  String get favoritesTitle;

  /// No description provided for @favoritesEmpty.
  ///
  /// In en, this message translates to:
  /// **'No favorites yet — tap the ♥ on any track'**
  String get favoritesEmpty;

  /// No description provided for @newPlaylist.
  ///
  /// In en, this message translates to:
  /// **'New playlist'**
  String get newPlaylist;

  /// No description provided for @playlistNameHint.
  ///
  /// In en, this message translates to:
  /// **'Playlist name'**
  String get playlistNameHint;

  /// No description provided for @importM3u8.
  ///
  /// In en, this message translates to:
  /// **'Import M3U8'**
  String get importM3u8;

  /// No description provided for @importedPlaylistName.
  ///
  /// In en, this message translates to:
  /// **'Imported playlist'**
  String get importedPlaylistName;

  /// No description provided for @importNoMatch.
  ///
  /// In en, this message translates to:
  /// **'Nothing matched your library ({count} entries unmatched)'**
  String importNoMatch(int count);

  /// No description provided for @importedTracks.
  ///
  /// In en, this message translates to:
  /// **'Imported {count, plural, =1{1 track} other{{count} tracks}}'**
  String importedTracks(int count);

  /// No description provided for @importedTracksWithUnmatched.
  ///
  /// In en, this message translates to:
  /// **'Imported {count, plural, =1{1 track} other{{count} tracks}} ({unmatched} unmatched)'**
  String importedTracksWithUnmatched(int count, int unmatched);

  /// No description provided for @importFailed.
  ///
  /// In en, this message translates to:
  /// **'Import failed: {error}'**
  String importFailed(String error);

  /// No description provided for @exportPlaylist.
  ///
  /// In en, this message translates to:
  /// **'Export playlist'**
  String get exportPlaylist;

  /// No description provided for @exportM3u8.
  ///
  /// In en, this message translates to:
  /// **'Export M3U8'**
  String get exportM3u8;

  /// No description provided for @deletePlaylist.
  ///
  /// In en, this message translates to:
  /// **'Delete playlist'**
  String get deletePlaylist;

  /// No description provided for @exported.
  ///
  /// In en, this message translates to:
  /// **'Exported'**
  String get exported;

  /// No description provided for @exportedWithMissing.
  ///
  /// In en, this message translates to:
  /// **'Exported ({count, plural, =1{1 missing track} other{{count} missing tracks}} excluded)'**
  String exportedWithMissing(int count);

  /// No description provided for @exportFailed.
  ///
  /// In en, this message translates to:
  /// **'Export failed: {error}'**
  String exportFailed(String error);

  /// No description provided for @deletePlaylistTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete playlist \"{name}\"?'**
  String deletePlaylistTitle(String name);

  /// No description provided for @deletePlaylistBody.
  ///
  /// In en, this message translates to:
  /// **'The playlist will be removed. Your audio files are not affected.'**
  String get deletePlaylistBody;

  /// No description provided for @playlistEmpty.
  ///
  /// In en, this message translates to:
  /// **'Empty playlist — long-press a track in your library to add it'**
  String get playlistEmpty;

  /// No description provided for @fileMissing.
  ///
  /// In en, this message translates to:
  /// **'File missing'**
  String get fileMissing;

  /// No description provided for @nowPlaying.
  ///
  /// In en, this message translates to:
  /// **'Now playing'**
  String get nowPlaying;

  /// No description provided for @nothingPlaying.
  ///
  /// In en, this message translates to:
  /// **'Nothing is playing'**
  String get nothingPlaying;

  /// No description provided for @noLyrics.
  ///
  /// In en, this message translates to:
  /// **'No lyrics'**
  String get noLyrics;

  /// No description provided for @playFromHere.
  ///
  /// In en, this message translates to:
  /// **'Play from this line'**
  String get playFromHere;

  /// No description provided for @lyricsNoTimestamps.
  ///
  /// In en, this message translates to:
  /// **'Lyrics without timestamps'**
  String get lyricsNoTimestamps;

  /// No description provided for @musicFolders.
  ///
  /// In en, this message translates to:
  /// **'Music folders'**
  String get musicFolders;

  /// No description provided for @addSystemMusicFolder.
  ///
  /// In en, this message translates to:
  /// **'Add system music folder'**
  String get addSystemMusicFolder;

  /// No description provided for @addFolder.
  ///
  /// In en, this message translates to:
  /// **'Add folder…'**
  String get addFolder;

  /// No description provided for @scanLibrary.
  ///
  /// In en, this message translates to:
  /// **'Scan library'**
  String get scanLibrary;

  /// No description provided for @scanning.
  ///
  /// In en, this message translates to:
  /// **'Scanning {done}/{total}'**
  String scanning(int done, int total);

  /// No description provided for @problemFiles.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 problem file} other{{count} problem files}}'**
  String problemFiles(int count);

  /// No description provided for @lastScanProblems.
  ///
  /// In en, this message translates to:
  /// **'Last scan reported {count, plural, =1{1 problem} other{{count} problems}}'**
  String lastScanProblems(int count);

  /// No description provided for @needAudioPermission.
  ///
  /// In en, this message translates to:
  /// **'Audio permission is required to scan'**
  String get needAudioPermission;

  /// No description provided for @scanFailed.
  ///
  /// In en, this message translates to:
  /// **'Scan failed: {error}'**
  String scanFailed(String error);

  /// No description provided for @batchFill.
  ///
  /// In en, this message translates to:
  /// **'Fill in missing covers and lyrics'**
  String get batchFill;

  /// No description provided for @batchFillSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Automatically fills tracks missing artwork or lyrics (can be cancelled)'**
  String get batchFillSubtitle;

  /// No description provided for @language.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get language;

  /// No description provided for @languageSystem.
  ///
  /// In en, this message translates to:
  /// **'System default'**
  String get languageSystem;

  /// No description provided for @scrapeTitle.
  ///
  /// In en, this message translates to:
  /// **'Scrape'**
  String get scrapeTitle;

  /// No description provided for @applied.
  ///
  /// In en, this message translates to:
  /// **'Applied'**
  String get applied;

  /// No description provided for @applyFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to apply: {error}'**
  String applyFailed(String error);

  /// No description provided for @searchFailed.
  ///
  /// In en, this message translates to:
  /// **'Search failed: {error}'**
  String searchFailed(String error);

  /// No description provided for @sourcesUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Currently unavailable: {sources}'**
  String sourcesUnavailable(String sources);

  /// No description provided for @noMatches.
  ///
  /// In en, this message translates to:
  /// **'No matches — try again'**
  String get noMatches;

  /// No description provided for @matchCandidates.
  ///
  /// In en, this message translates to:
  /// **'Matches (artwork + text)'**
  String get matchCandidates;

  /// No description provided for @lyricsCandidates.
  ///
  /// In en, this message translates to:
  /// **'Lyrics'**
  String get lyricsCandidates;

  /// No description provided for @applyCover.
  ///
  /// In en, this message translates to:
  /// **'Apply artwork'**
  String get applyCover;

  /// No description provided for @applyTextFix.
  ///
  /// In en, this message translates to:
  /// **'Apply text corrections'**
  String get applyTextFix;

  /// No description provided for @lyricsSynced.
  ///
  /// In en, this message translates to:
  /// **'synced'**
  String get lyricsSynced;

  /// No description provided for @lyricsPlain.
  ///
  /// In en, this message translates to:
  /// **'plain text'**
  String get lyricsPlain;

  /// No description provided for @batchNothingToFill.
  ///
  /// In en, this message translates to:
  /// **'Nothing to fill — every track already has artwork and lyrics'**
  String get batchNothingToFill;

  /// No description provided for @batchDone.
  ///
  /// In en, this message translates to:
  /// **'Done — {covers} covers, {lyrics} lyrics, {skipped} not found'**
  String batchDone(int covers, int lyrics, int skipped);

  /// No description provided for @batchProgress.
  ///
  /// In en, this message translates to:
  /// **'Filling covers and lyrics {done}/{total}'**
  String batchProgress(int done, int total);

  /// No description provided for @batchFilledSoFar.
  ///
  /// In en, this message translates to:
  /// **'So far: {covers} covers, {lyrics} lyrics'**
  String batchFilledSoFar(int covers, int lyrics);

  /// No description provided for @wizardTitle.
  ///
  /// In en, this message translates to:
  /// **'Setup'**
  String get wizardTitle;

  /// No description provided for @wizardWelcome.
  ///
  /// In en, this message translates to:
  /// **'Welcome to OpenMusic'**
  String get wizardWelcome;

  /// No description provided for @wizardIntro.
  ///
  /// In en, this message translates to:
  /// **'Three steps to your library: pick a folder → scan → fill in covers and lyrics'**
  String get wizardIntro;

  /// No description provided for @wizardPickFolder.
  ///
  /// In en, this message translates to:
  /// **'Choose your music folder'**
  String get wizardPickFolder;

  /// No description provided for @wizardNoFolders.
  ///
  /// In en, this message translates to:
  /// **'No folders yet — add one below'**
  String get wizardNoFolders;

  /// No description provided for @wizardScanTitle.
  ///
  /// In en, this message translates to:
  /// **'Scan your library'**
  String get wizardScanTitle;

  /// No description provided for @wizardScanning.
  ///
  /// In en, this message translates to:
  /// **'Scanning…'**
  String get wizardScanning;

  /// No description provided for @wizardStartScan.
  ///
  /// In en, this message translates to:
  /// **'Start scan'**
  String get wizardStartScan;

  /// No description provided for @wizardFillTitle.
  ///
  /// In en, this message translates to:
  /// **'Fill in covers and lyrics'**
  String get wizardFillTitle;

  /// No description provided for @wizardSkipStep.
  ///
  /// In en, this message translates to:
  /// **'Skip this step'**
  String get wizardSkipStep;

  /// No description provided for @wizardComplete.
  ///
  /// In en, this message translates to:
  /// **'All set'**
  String get wizardComplete;

  /// No description provided for @wizardEnterLibrary.
  ///
  /// In en, this message translates to:
  /// **'Open library'**
  String get wizardEnterLibrary;

  /// No description provided for @wizardScanFound.
  ///
  /// In en, this message translates to:
  /// **'Scan complete: {count, plural, =0{no tracks found} =1{1 track} other{{count} tracks}}'**
  String wizardScanFound(int count);

  /// Title of the device sync screen
  ///
  /// In en, this message translates to:
  /// **'Device sync'**
  String get syncTitle;

  /// No description provided for @syncSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Pair with devices on your local network'**
  String get syncSubtitle;

  /// No description provided for @syncListening.
  ///
  /// In en, this message translates to:
  /// **'Listening on :{port}'**
  String syncListening(int port);

  /// No description provided for @syncNotStarted.
  ///
  /// In en, this message translates to:
  /// **'Not running'**
  String get syncNotStarted;

  /// No description provided for @syncStartFailed.
  ///
  /// In en, this message translates to:
  /// **'Sync service not running: {error}'**
  String syncStartFailed(String error);

  /// No description provided for @syncRetry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get syncRetry;

  /// No description provided for @syncRenameDevice.
  ///
  /// In en, this message translates to:
  /// **'Rename device'**
  String get syncRenameDevice;

  /// No description provided for @syncPairedSection.
  ///
  /// In en, this message translates to:
  /// **'Paired devices'**
  String get syncPairedSection;

  /// No description provided for @syncNoPaired.
  ///
  /// In en, this message translates to:
  /// **'No paired devices yet'**
  String get syncNoPaired;

  /// No description provided for @syncDiscoveredSection.
  ///
  /// In en, this message translates to:
  /// **'Found on your network'**
  String get syncDiscoveredSection;

  /// No description provided for @syncNothingFound.
  ///
  /// In en, this message translates to:
  /// **'No other devices found'**
  String get syncNothingFound;

  /// No description provided for @syncNothingFoundHint.
  ///
  /// In en, this message translates to:
  /// **'Make sure both devices are on the same Wi-Fi and have openmusic open'**
  String get syncNothingFoundHint;

  /// No description provided for @syncOnlineAt.
  ///
  /// In en, this message translates to:
  /// **'Online · {address}'**
  String syncOnlineAt(String address);

  /// No description provided for @syncOffline.
  ///
  /// In en, this message translates to:
  /// **'Offline'**
  String get syncOffline;

  /// No description provided for @syncIncompatible.
  ///
  /// In en, this message translates to:
  /// **'Different protocol version — please update openmusic'**
  String get syncIncompatible;

  /// No description provided for @syncPair.
  ///
  /// In en, this message translates to:
  /// **'Pair'**
  String get syncPair;

  /// No description provided for @syncUnpair.
  ///
  /// In en, this message translates to:
  /// **'Unpair'**
  String get syncUnpair;

  /// No description provided for @syncTestConnection.
  ///
  /// In en, this message translates to:
  /// **'Test connection'**
  String get syncTestConnection;

  /// No description provided for @syncNow.
  ///
  /// In en, this message translates to:
  /// **'Sync'**
  String get syncNow;

  /// No description provided for @syncSummary.
  ///
  /// In en, this message translates to:
  /// **'Synced: {playlists} playlist changes · {favorites} favorite changes · {plays} new plays'**
  String syncSummary(int playlists, int favorites, int plays);

  /// No description provided for @syncAlreadyUpToDate.
  ///
  /// In en, this message translates to:
  /// **'Already up to date'**
  String get syncAlreadyUpToDate;

  /// No description provided for @syncPeerTooOld.
  ///
  /// In en, this message translates to:
  /// **'The other device doesn\'t support syncing — please update openmusic'**
  String get syncPeerTooOld;

  /// No description provided for @syncPairingWith.
  ///
  /// In en, this message translates to:
  /// **'Pairing with {device}'**
  String syncPairingWith(String device);

  /// No description provided for @syncNegotiating.
  ///
  /// In en, this message translates to:
  /// **'Negotiating keys…'**
  String get syncNegotiating;

  /// No description provided for @syncCompareCodes.
  ///
  /// In en, this message translates to:
  /// **'Check that the other device shows the same number:'**
  String get syncCompareCodes;

  /// No description provided for @syncWaitingPeer.
  ///
  /// In en, this message translates to:
  /// **'Waiting for the other device (up to 60 s)…'**
  String get syncWaitingPeer;

  /// No description provided for @syncPairRequestTitle.
  ///
  /// In en, this message translates to:
  /// **'Pairing request'**
  String get syncPairRequestTitle;

  /// No description provided for @syncPairRequestFrom.
  ///
  /// In en, this message translates to:
  /// **'{device} wants to pair with this device'**
  String syncPairRequestFrom(String device);

  /// No description provided for @syncCodesMatch.
  ///
  /// In en, this message translates to:
  /// **'Numbers match'**
  String get syncCodesMatch;

  /// No description provided for @syncRejectPair.
  ///
  /// In en, this message translates to:
  /// **'Decline'**
  String get syncRejectPair;

  /// No description provided for @syncPairedWith.
  ///
  /// In en, this message translates to:
  /// **'Paired with {device}'**
  String syncPairedWith(String device);

  /// No description provided for @syncPairRejected.
  ///
  /// In en, this message translates to:
  /// **'The other device declined'**
  String get syncPairRejected;

  /// No description provided for @syncPairTimedOut.
  ///
  /// In en, this message translates to:
  /// **'The other device did not confirm; pairing cancelled'**
  String get syncPairTimedOut;

  /// No description provided for @syncPairFailed.
  ///
  /// In en, this message translates to:
  /// **'Pairing failed: could not reach the other device'**
  String get syncPairFailed;

  /// No description provided for @syncHelloResult.
  ///
  /// In en, this message translates to:
  /// **'{device} ({platform}) · {count, plural, =1{1 track} other{{count} tracks}} · protocol v{pv}'**
  String syncHelloResult(String device, String platform, int count, int pv);

  /// No description provided for @syncAuthUnknownDevice.
  ///
  /// In en, this message translates to:
  /// **'The other device has unpaired from this one; pair again'**
  String get syncAuthUnknownDevice;

  /// No description provided for @syncAuthClockSkew.
  ///
  /// In en, this message translates to:
  /// **'The two devices\' clocks differ by more than 5 minutes; please correct the system time'**
  String get syncAuthClockSkew;

  /// No description provided for @syncAuthOther.
  ///
  /// In en, this message translates to:
  /// **'Authentication failed: {reason}'**
  String syncAuthOther(String reason);

  /// No description provided for @syncConnectFailed.
  ///
  /// In en, this message translates to:
  /// **'Connection failed: {error}'**
  String syncConnectFailed(String error);

  /// No description provided for @syncUnpairTitle.
  ///
  /// In en, this message translates to:
  /// **'Unpair from {device}?'**
  String syncUnpairTitle(String device);

  /// No description provided for @syncUnpairBody.
  ///
  /// In en, this message translates to:
  /// **'This only removes the record on this device — the other device still keeps its pairing. Do it on both devices to fully disconnect.\n\nNo music files are deleted.'**
  String get syncUnpairBody;

  /// No description provided for @syncPermissionNeeded.
  ///
  /// In en, this message translates to:
  /// **'Without the “nearby devices” permission, devices on your network can\'t be found.'**
  String get syncPermissionNeeded;

  /// No description provided for @syncGrantPermission.
  ///
  /// In en, this message translates to:
  /// **'Grant permission'**
  String get syncGrantPermission;

  /// No description provided for @syncOpenSettings.
  ///
  /// In en, this message translates to:
  /// **'Open system settings'**
  String get syncOpenSettings;

  /// No description provided for @problemRootUnreachable.
  ///
  /// In en, this message translates to:
  /// **'Folder unreachable: {path} (tracks under it were left untouched)'**
  String problemRootUnreachable(String path);

  /// No description provided for @problemFileFailed.
  ///
  /// In en, this message translates to:
  /// **'{path}: {error}'**
  String problemFileFailed(String path, String error);

  /// No description provided for @problemBatchWriteFailed.
  ///
  /// In en, this message translates to:
  /// **'Batch write failed ({count} entries): {error}'**
  String problemBatchWriteFailed(int count, String error);
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
