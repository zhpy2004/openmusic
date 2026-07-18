# OpenMusic

开源轻量本地音乐播放器,Windows + Android 双端(Flutter)。

**当前状态:M1 播放骨架(v0.1.0-m1)** —— 能日常听歌的最小闭环:

- 曲库:添加文件夹、增量扫描(mtime+size 指纹)、损坏文件跳过并计数、标题/歌手/专辑搜索
- 播放:队列播放、gapless(media_kit/mpv)、随机/循环三态、进度拖动
- 系统集成:Android 通知栏/锁屏/蓝牙按键(audio_service);Windows 媒体悬浮窗/媒体键(SMTC)

歌单/收藏、刮削、局域网同步在 M2/M3 路线图(见 `docs/superpowers/specs/`)。

## 构建

```
flutter pub get
flutter run -d windows   # 或 -d <android设备>
```

Windows 跑测试需要 `tool/sqlite3/sqlite3.dll`(仓库已内置)。

```
flutter test
```

## 文档

- 设计 spec:`docs/superpowers/specs/2026-07-16-openmusic-design.md`
- M1 实施计划(含全部审查修订记录):`docs/superpowers/plans/2026-07-16-m1-playback-skeleton.md`
- M1 验收烟测清单:`docs/superpowers/checklists/m1-smoke.md`
