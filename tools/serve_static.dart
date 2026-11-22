// 极简静态文件服务器：替代 `python -m http.server`（未安装 Python 的机器）。
// 仅依赖 dart:io，无需 pub 解析——直接 `dart tools/serve_static.dart <目录> [端口]` 运行。
//
// 用法：dart tools/serve_static.dart <托管根目录> [端口，默认 8080]
// 行为对齐 python http.server：目录请求回 index.html、逐请求打印访问日志、
// 支持 If-Modified-Since 协商缓存（304）；拒绝路径穿越（.. 段）。
import 'dart:io';

/// 扩展名 → Content-Type 映射（覆盖 Flutter Web 产物涉及的全部类型）。
const Map<String, String> _mimeTypes = {
  '.html': 'text/html; charset=utf-8',
  '.htm': 'text/html; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.js': 'application/javascript; charset=utf-8',
  '.mjs': 'application/javascript; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.wasm': 'application/wasm',
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.jpeg': 'image/jpeg',
  '.gif': 'image/gif',
  '.svg': 'image/svg+xml',
  '.ico': 'image/x-icon',
  '.webp': 'image/webp',
  '.ttf': 'font/ttf',
  '.otf': 'font/otf',
  '.woff': 'font/woff',
  '.woff2': 'font/woff2',
  '.txt': 'text/plain; charset=utf-8',
  '.map': 'application/json; charset=utf-8',
};

/// HTTP 日期格式（RFC 1123，GMT），供 Last-Modified / If-Modified-Since 用。
const List<String> _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const List<String> _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// 把 DateTime 格式化为 HTTP 日期字符串。
String _httpDate(DateTime t) {
  final u = t.toUtc();
  return '${_weekdays[u.weekday - 1]}, ${u.day.toString().padLeft(2, '0')} '
      '${_months[u.month - 1]} ${u.year} '
      '${u.hour.toString().padLeft(2, '0')}:'
      '${u.minute.toString().padLeft(2, '0')}:'
      '${u.second.toString().padLeft(2, '0')} GMT';
}

/// 解析 If-Modified-Since 头为 UTC 时间；解析失败返回 null。
DateTime? _parseHttpDate(String s) {
  final m = RegExp(
    r'(\d{1,2}) ([A-Za-z]{3}) (\d{4}) (\d{2}):(\d{2}):(\d{2})',
  ).firstMatch(s);
  if (m == null) return null;
  final month = _months.indexOf(m[2]!) + 1;
  if (month == 0) return null;
  return DateTime.utc(
    int.parse(m[3]!), month, int.parse(m[1]!),
    int.parse(m[4]!), int.parse(m[5]!), int.parse(m[6]!),
  );
}

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln('用法: dart tools/serve_static.dart <托管根目录> [端口，默认 8080]');
    exit(2);
  }
  final root = Directory(args[0]);
  if (!root.existsSync()) {
    stderr.writeln('托管目录不存在: ${args[0]}');
    exit(2);
  }
  final port = args.length > 1 ? int.tryParse(args[1]) ?? 8080 : 8080;
  final rootPath = root.resolveSymbolicLinksSync();

  final server = await HttpServer.bind(InternetAddress.anyIPv4, port);
  stdout.writeln('== 静态托管 ${args[0]} http://localhost:$port（Dart serve_static）==');
  await for (final request in server) {
    _serve(request, rootPath);
  }
}

/// 处理单个静态文件请求。
Future<void> _serve(HttpRequest request, String rootPath) async {
  final origin = '${request.connectionInfo?.remoteAddress.address ?? '-'}';
  try {
    // 过滤路径段：丢弃 '.' 与 '..'，天然防目录穿越
    final segments = [
      for (final s in Uri.parse(request.uri.path).pathSegments)
        if (s != '.' && s != '..' && s.isNotEmpty) s,
    ];
    var filePath = rootPath;
    for (final s in segments) {
      filePath = '$filePath${Platform.pathSeparator}$s';
    }
    var file = File(filePath);
    if (!file.existsSync() || FileSystemEntity.isDirectorySync(filePath)) {
      // 目录请求回退 index.html
      final index = File('$filePath${Platform.pathSeparator}index.html');
      file = index.existsSync() ? index : file;
    }
    if (!file.existsSync()) {
      stdout.writeln('$origin - "GET ${request.uri.path} HTTP/1.1" 404');
      request.response.statusCode = 404;
      await request.response.close();
      return;
    }
    final modified = file.lastModifiedSync();
    final ims = request.headers.value(HttpHeaders.ifModifiedSinceHeader);
    final since = ims == null ? null : _parseHttpDate(ims);
    if (since != null &&
        !modified.toUtc().isAfter(since.add(const Duration(seconds: 1)))) {
      stdout.writeln('$origin - "GET ${request.uri.path} HTTP/1.1" 304');
      request.response.statusCode = 304;
      await request.response.close();
      return;
    }
    final base = file.path.split(Platform.pathSeparator).last;
    final dot = base.lastIndexOf('.');
    final ext = dot >= 0 ? base.substring(dot).toLowerCase() : '';
    request.response.headers.contentType =
        ContentType.parse(_mimeTypes[ext] ?? 'application/octet-stream');
    request.response.headers.set(HttpHeaders.lastModifiedHeader, _httpDate(modified));
    stdout.writeln(
      '$origin - "GET ${request.uri.path} HTTP/1.1" 200 '
      '${file.lengthSync()}',
    );
    await file.openRead().pipe(request.response);
  } catch (e) {
    stdout.writeln('$origin - "GET ${request.uri.path} HTTP/1.1" 500 ($e)');
    request.response.statusCode = 500;
    await request.response.close();
  }
}
