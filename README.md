# OpenMusic

本地优先的轻量音乐播放器,Windows + Android 双端(Flutter 单代码库)。

主打两件事:**从零建库不费劲**、**两台设备一键同步**。不做在线音源聚合,不做账号云服务——你的曲库是你自己的文件。

> 当前 **v0.5.0**:播放骨架与曲库体验(歌单/收藏、刮削、歌词、建库引导)已完成,可日常使用。局域网同步开发中,见 [ROADMAP.md](ROADMAP.md)。

## 下载

到 [Releases](https://github.com/zhpy2004/openmusic/releases/latest) 页面下载:

| 平台 | 文件 | 说明 |
|---|---|---|
| Windows | `openmusic-v0.5.0-windows-x64.zip` | 解压后双击 `openmusic.exe`,免安装。整个文件夹要保持完整 |
| Android | `openmusic-v0.5.0-android-universal.apk` | **不确定选哪个就下这个**,通吃所有机型 |
| Android | `openmusic-v0.5.0-android-arm64-v8a.apk` | 2017 年后的手机基本都是,体积小一半 |
| Android | `openmusic-v0.5.0-android-armeabi-v7a.apk` | 较老的 32 位设备 |

Android 侧装需要在系统里允许「安装未知来源应用」。APK 用固定密钥签名,后续版本可直接覆盖升级。

## 功能

**建库**
- 选文件夹扫描导入,增量扫描(mtime + size 判定,重扫只处理变动过的文件)
- 支持 MP3 / FLAC / AAC / OGG / OPUS / WAV
- 首次启动有建库向导:选文件夹 → 扫描 → 批量补全封面歌词 → 完成
- 损坏或不支持的文件跳过并记入「问题文件」清单,不中断整次扫描

**播放**
- 队列播放、gapless 无缝衔接(media_kit / mpv)
- 随机播放,三态循环(关 / 列表 / 单曲)
- Android:通知栏、锁屏、蓝牙耳机按键(audio_service)
- Windows:系统媒体悬浮窗与媒体键(SMTC)

**歌单与收藏**
- 歌单增删改、❤️ 我喜欢的
- 标准 M3U8 导入导出(相对路径,可移植到别的播放器)
- 曲目按**内容指纹**引用:改名、挪目录都不丢关联;文件暂时缺失的曲目在歌单里置灰保留,不会被静默删掉

**刮削(元数据补全)**
- 单曲手动刮削 + 全库批量补全,三个开放数据源:iTunes Search、LRCLIB、MusicBrainz + Cover Art Archive
- **绝不修改音频文件字节**:封面写 `<音频名>.jpg`、歌词写 `<音频名>.lrc` 伴随文件,标题/歌手修正写数据库覆盖层——改文件头会让内容指纹变化,歌单和收藏的关联就断了
- 批量补全只补缺的,不覆盖已有的封面/歌词;匹配不够可信时宁可跳过,不乱糊封面

**歌词**
- 行级 LRC 滚动显示,当前行居中高亮,随播放推进
- 正在播放页点封面翻到歌词;鼠标滚轮或手指滑动可自由浏览,4 秒后自动回到当前句
- 焦点框跟随视口中心,点 ▶ 从任意一句开始播放
- 无时间轴的纯文本歌词也能显示;没有歌词时正常提示

## 构建运行

需要 Flutter 3.44+(Dart 3.12+)。

```bash
flutter pub get
flutter run -d windows        # 桌面
flutter run -d <android设备>  # 手机
```

跑测试:

```bash
flutter test
```

Windows 上跑测试依赖仓库内置的 `tool/sqlite3/sqlite3.dll`,无需另外安装。

## 技术栈

Flutter · riverpod(状态)· drift/SQLite(索引)· media_kit(播放,mpv 内核)· audio_service(Android 媒体会话)· smtc_windows(Windows 媒体面板)

**设计原则:文件即真相。** SQLite 只是索引缓存,删库重扫不丢数据;歌单与收藏是原生数据,带 UUID 与 updated_at,为跨设备同步预留。曲目的跨设备身份是内容指纹 `xxh3(文件大小 + 头 128KB + 尾 128KB)`。

## 路线图

见 [ROADMAP.md](ROADMAP.md)。下一步是局域网同步:mDNS 发现 + 配对码 + 选择性文件同步。

## 许可

[MIT](LICENSE)
