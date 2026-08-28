import 'dart:io';

import 'package:path/path.dart' as p;

/// 解析曲目封面的伴随文件路径:同名 .jpg 优先,其次 .png;都没有返回 null。
/// (内嵌封面的读取留到后续增强——M2-B 的封面来源是刮削写下的伴随文件。)
///
/// 放在 library 层而非 providers:播放层的媒体会话也要用它给通知栏配图,
/// 而 providers 反过来依赖播放层,搁在那儿会成环。
Future<String?> resolveCoverPath(String audioPath) async {
  for (final ext in const ['.jpg', '.png']) {
    final candidate = p.setExtension(audioPath, ext);
    if (await File(candidate).exists()) return candidate;
  }
  return null;
}
