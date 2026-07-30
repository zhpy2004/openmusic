// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get cancel => '取消';

  @override
  String get save => '保存';

  @override
  String get delete => '删除';

  @override
  String get create => '创建';

  @override
  String get apply => '应用';

  @override
  String get close => '关闭';

  @override
  String get clear => '清除';

  @override
  String get remove => '移除';

  @override
  String get skip => '跳过';

  @override
  String get start => '开始';

  @override
  String get next => '下一步';

  @override
  String get finish => '完成';

  @override
  String get scrape => '刮削';

  @override
  String get favorite => '收藏';

  @override
  String get unfavorite => '取消收藏';

  @override
  String loadFailed(String error) {
    return '加载失败: $error';
  }

  @override
  String get tabLibrary => '曲库';

  @override
  String get tabPlaylists => '歌单';

  @override
  String get tabSettings => '设置';

  @override
  String get searchHint => '搜索标题 / 歌手 / 专辑';

  @override
  String get libraryEmpty => '曲库为空——到设置里添加文件夹并扫描';

  @override
  String get noPlaylistsYet => '还没有歌单,去「歌单」页新建';

  @override
  String get addToPlaylist => '加入歌单';

  @override
  String get favoritesTitle => '我喜欢的';

  @override
  String get favoritesEmpty => '还没有收藏——点曲目上的 ❤️';

  @override
  String get newPlaylist => '新建歌单';

  @override
  String get playlistNameHint => '歌单名';

  @override
  String get importM3u8 => '导入 M3U8';

  @override
  String get importedPlaylistName => '导入歌单';

  @override
  String importNoMatch(int count) {
    return '未匹配到曲库中的曲目($count 首未匹配)';
  }

  @override
  String importedTracks(int count) {
    return '已导入 $count 首';
  }

  @override
  String importedTracksWithUnmatched(int count, int unmatched) {
    return '已导入 $count 首($unmatched 首未匹配)';
  }

  @override
  String importFailed(String error) {
    return '导入失败: $error';
  }

  @override
  String get exportPlaylist => '导出歌单';

  @override
  String get exportM3u8 => '导出 M3U8';

  @override
  String get deletePlaylist => '删除歌单';

  @override
  String get exported => '已导出';

  @override
  String exportedWithMissing(int count) {
    return '已导出($count 首缺失未含)';
  }

  @override
  String exportFailed(String error) {
    return '导出失败: $error';
  }

  @override
  String deletePlaylistTitle(String name) {
    return '删除歌单「$name」?';
  }

  @override
  String get deletePlaylistBody => '歌单定义会被删除(曲目文件不受影响)。';

  @override
  String get playlistEmpty => '空歌单——从曲库长按曲目加入';

  @override
  String get fileMissing => '文件缺失';

  @override
  String get nowPlaying => '正在播放';

  @override
  String get nothingPlaying => '没有正在播放的曲目';

  @override
  String get noLyrics => '暂无歌词';

  @override
  String get playFromHere => '从这一句播放';

  @override
  String get lyricsNoTimestamps => '无时间轴歌词';

  @override
  String get musicFolders => '音乐文件夹';

  @override
  String get addSystemMusicFolder => '添加系统音乐文件夹';

  @override
  String get addFolder => '添加文件夹…';

  @override
  String get scanLibrary => '扫描曲库';

  @override
  String scanning(int done, int total) {
    return '扫描中 $done/$total';
  }

  @override
  String problemFiles(int count) {
    return '问题文件 $count 个';
  }

  @override
  String lastScanProblems(int count) {
    return '上次扫描有 $count 个问题';
  }

  @override
  String get needAudioPermission => '需要音频读取权限才能扫描';

  @override
  String scanFailed(String error) {
    return '扫描出错: $error';
  }

  @override
  String get batchFill => '批量补全封面/歌词';

  @override
  String get batchFillSubtitle => '给缺封面或缺歌词的曲目自动补全(可取消)';

  @override
  String get language => '语言';

  @override
  String get languageSystem => '跟随系统';

  @override
  String get scrapeTitle => '刮削';

  @override
  String get applied => '已应用';

  @override
  String applyFailed(String error) {
    return '应用失败: $error';
  }

  @override
  String searchFailed(String error) {
    return '搜索失败: $error';
  }

  @override
  String sourcesUnavailable(String sources) {
    return '以下源暂不可用: $sources';
  }

  @override
  String get noMatches => '无匹配结果,可重试';

  @override
  String get matchCandidates => '匹配候选(封面 + 文本)';

  @override
  String get lyricsCandidates => '歌词候选';

  @override
  String get applyCover => '应用封面';

  @override
  String get applyTextFix => '应用文本修正';

  @override
  String get lyricsSynced => '带时间轴';

  @override
  String get lyricsPlain => '纯文本';

  @override
  String get batchNothingToFill => '无缺封面/歌词的曲目,无需补全';

  @override
  String batchDone(int covers, int lyrics, int skipped) {
    return '补全完成:封面 $covers · 歌词 $lyrics · 未找到 $skipped';
  }

  @override
  String batchProgress(int done, int total) {
    return '补全封面/歌词 $done/$total';
  }

  @override
  String batchFilledSoFar(int covers, int lyrics) {
    return '已补:封面 $covers · 歌词 $lyrics';
  }

  @override
  String get wizardTitle => '建库向导';

  @override
  String get wizardWelcome => '欢迎使用 OpenMusic';

  @override
  String get wizardIntro => '3 步建好曲库:选文件夹 → 扫描 → 补全封面/歌词';

  @override
  String get wizardPickFolder => '选择音乐文件夹';

  @override
  String get wizardNoFolders => '还没有文件夹,点下面添加';

  @override
  String get wizardScanTitle => '扫描曲库';

  @override
  String get wizardScanning => '扫描中…';

  @override
  String get wizardStartScan => '开始扫描';

  @override
  String get wizardFillTitle => '补全封面/歌词';

  @override
  String get wizardSkipStep => '跳过此步';

  @override
  String get wizardComplete => '建库完成';

  @override
  String get wizardEnterLibrary => '进入曲库';

  @override
  String wizardScanFound(int count) {
    return '扫描完成:找到 $count 首';
  }

  @override
  String get syncTitle => '设备同步';

  @override
  String get syncSubtitle => '与局域网内的其他设备配对';

  @override
  String syncListening(int port) {
    return '监听中 :$port';
  }

  @override
  String get syncNotStarted => '未启动';

  @override
  String syncStartFailed(String error) {
    return '同步服务未启动:$error';
  }

  @override
  String get syncRetry => '重试';

  @override
  String get syncRenameDevice => '改设备名';

  @override
  String get syncPairedSection => '已配对设备';

  @override
  String get syncNoPaired => '还没有配对过任何设备';

  @override
  String get syncDiscoveredSection => '局域网内发现';

  @override
  String get syncNothingFound => '没有发现其他设备';

  @override
  String get syncNothingFoundHint => '确认两台设备连在同一个 WiFi,且都打开了 openmusic';

  @override
  String syncOnlineAt(String address) {
    return '在线 · $address';
  }

  @override
  String get syncOffline => '离线';

  @override
  String get syncIncompatible => '协议版本不同,需要升级 openmusic';

  @override
  String get syncPair => '配对';

  @override
  String get syncUnpair => '解除配对';

  @override
  String get syncTestConnection => '测试连接';

  @override
  String get syncNow => '同步';

  @override
  String syncSummary(int playlists, int favorites, int plays) {
    return '歌单 +$playlists · 收藏 +$favorites · 播放记录 +$plays';
  }

  @override
  String get syncAlreadyUpToDate => '已是最新';

  @override
  String get syncPeerTooOld => '对方版本不支持同步,请升级 openmusic';

  @override
  String syncPairingWith(String device) {
    return '与 $device 配对';
  }

  @override
  String get syncNegotiating => '正在协商密钥…';

  @override
  String get syncCompareCodes => '确认对方屏幕上显示的是同一个数字:';

  @override
  String get syncWaitingPeer => '等待对方确认(最多 60 秒)…';

  @override
  String get syncPairRequestTitle => '配对请求';

  @override
  String syncPairRequestFrom(String device) {
    return '$device 请求与本机配对';
  }

  @override
  String get syncCodesMatch => '两边数字一致';

  @override
  String get syncRejectPair => '拒绝';

  @override
  String syncPairedWith(String device) {
    return '已与 $device 配对';
  }

  @override
  String get syncPairRejected => '对方拒绝了配对';

  @override
  String get syncPairTimedOut => '对方未确认,配对已取消';

  @override
  String get syncPairFailed => '配对失败:无法连接对方设备';

  @override
  String syncHelloResult(String device, String platform, int count, int pv) {
    return '$device($platform)· 曲目 $count · 协议 v$pv';
  }

  @override
  String get syncAuthUnknownDevice => '对方已解除与本机的配对,请重新配对';

  @override
  String get syncAuthClockSkew => '两台设备时间相差超过 5 分钟,请校准系统时间';

  @override
  String syncAuthOther(String reason) {
    return '鉴权失败:$reason';
  }

  @override
  String syncConnectFailed(String error) {
    return '连接失败:$error';
  }

  @override
  String syncUnpairTitle(String device) {
    return '解除与 $device 的配对?';
  }

  @override
  String get syncUnpairBody =>
      '只会删除本机上的记录,对方设备上仍保留着与本机的配对。要彻底断开,请在两台设备上都执行一次。\n\n不会删除任何音乐文件。';

  @override
  String get syncPermissionNeeded => '没有「附近的设备」权限,因此看不到局域网里的其他设备。';

  @override
  String get syncGrantPermission => '授予权限';

  @override
  String get syncOpenSettings => '去系统设置开启';

  @override
  String problemRootUnreachable(String path) {
    return '根目录不可达: $path(本轮不清理其下曲目)';
  }

  @override
  String problemFileFailed(String path, String error) {
    return '$path: $error';
  }

  @override
  String problemBatchWriteFailed(int count, String error) {
    return '批量写入失败($count 条): $error';
  }
}
