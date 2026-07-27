import 'dart:convert';
import 'dart:io';

import '../data/database.dart';
import 'request_auth.dart';

/// 本机同步服务。绑 0.0.0.0:0 让系统分配端口(随 mDNS 播报),
/// 不钉固定端口——Windows 防火墙按程序而非端口授权,随机端口无额外代价。
class SyncServer {
  SyncServer({
    required this.db,
    required this.deviceId,
    required this.deviceName,
    required this.platform,
    required this.trackCount,
  });

  static const protocolVersion = 1;

  final AppDatabase db;
  final String deviceId;
  final String deviceName;
  final String platform;
  final Future<int> Function() trackCount;

  final ReplayGuard _guard = ReplayGuard();
  HttpServer? _http;

  int? get port => _http?.port;
  bool get isRunning => _http != null;

  Future<int> start({int port = 0}) async {
    if (_http != null) return _http!.port;
    final server = await HttpServer.bind(InternetAddress.anyIPv4, port);
    _http = server;
    server.listen(_handle, onError: (_) {});
    return server.port;
  }

  Future<void> stop() async {
    final server = _http;
    _http = null;
    await server?.close(force: true);
  }

  Future<void> _handle(HttpRequest req) async {
    try {
      final body = await _readBody(req);
      final path = req.uri.path;
      if (req.method == 'GET' && path == '/v1/hello') {
        await _handleHello(req, body);
        return;
      }
      await _respond(req, 404, {'error': 'not_found'});
    } catch (e) {
      // 单个请求失败绝不能带倒服务(母 spec §8)。
      await _respond(req, 500, {'error': e.toString()});
    }
  }

  Future<List<int>> _readBody(HttpRequest req) async {
    final chunks = <int>[];
    await for (final chunk in req) {
      chunks.addAll(chunk);
    }
    return chunks;
  }

  Map<String, String> _headersOf(HttpRequest req) {
    final map = <String, String>{};
    req.headers.forEach((name, values) {
      if (values.isNotEmpty) map[name.toLowerCase()] = values.first;
    });
    return map;
  }

  /// 验签;通过返回 null,否则已经把 401 写回去了。
  Future<AuthFailure?> _authorize(HttpRequest req, List<int> body) async {
    final failure = await verifyRequest(
      headers: _headersOf(req),
      method: req.method,
      path: req.uri.path,
      body: body,
      keyLookup: (id) async {
        final peer = await db.getPeer(id);
        return peer == null ? null : base64.decode(peer.sharedKey);
      },
      guard: _guard,
    );
    if (failure != null) {
      await _respond(req, 401, {'reason': failure.wireName});
    }
    return failure;
  }

  Future<void> _handleHello(HttpRequest req, List<int> body) async {
    if (await _authorize(req, body) != null) return;
    await _respond(req, 200, {
      'did': deviceId,
      'name': deviceName,
      'plat': platform,
      'pv': protocolVersion,
      'trackCount': await trackCount(),
    });
  }

  Future<void> _respond(
    HttpRequest req,
    int status,
    Map<String, dynamic> body,
  ) async {
    req.response.statusCode = status;
    req.response.headers.contentType = ContentType.json;
    req.response.write(jsonEncode(body));
    await req.response.close();
  }
}
