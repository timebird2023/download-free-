import 'dart:io';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'backend_service.dart';

class WebShareServer {
  static final WebShareServer _instance = WebShareServer._internal();
  factory WebShareServer() => _instance;
  WebShareServer._internal();

  HttpServer? _server;
  int port = 8080;
  final ValueNotifier<bool> isRunningNotifier = ValueNotifier<bool>(false);
  final ValueNotifier<List<String>> logsNotifier = ValueNotifier<List<String>>([]);

  bool get isRunning => _server != null;

  Future<String?> getLocalIpAddress() async {
    try {
      final interfaces = await NetworkInterface.list(
        includeLoopback: false,
        type: InternetAddressType.IPv4,
      );
      for (var interface in interfaces) {
        for (var addr in interface.addresses) {
          if (!addr.isLoopback && addr.type == InternetAddressType.IPv4) {
            return addr.address;
          }
        }
      }
    } catch (e) {
      debugPrint('Error getting IP: $e');
    }
    return null;
  }

  Future<bool> startServer() async {
    if (_server != null) return true;
    final candidatePorts = [8080, 8088, 8888, 5000, 3000];
    for (final p in candidatePorts) {
      try {
        _server = await HttpServer.bind(InternetAddress.anyIPv4, p);
        port = p;
        break;
      } catch (e) {
        debugPrint('المنفذ $p غير متاح: $e');
      }
    }
    if (_server == null) {
      _addLog('تعذر تشغيل الخادم على أي من المنافذ المتاحة');
      isRunningNotifier.value = false;
      return false;
    }
    try {
      isRunningNotifier.value = true;
      _addLog('تم تشغيل خادم المشاركة بنجاح على المنفذ $port');

      _server!.listen((HttpRequest request) async {
        try {
          final uri = request.uri;
          _addLog('${request.method} ${uri.path}');

          if (uri.path == '/' || uri.path == '/index.html') {
            await _serveHtmlPage(request);
          } else if (uri.path == '/download') {
            await _serveDownload(request);
          } else if (uri.path == '/stream') {
            await _serveStream(request);
          } else {
            request.response.statusCode = HttpStatus.notFound;
            request.response.write('Not Found');
            await request.response.close();
          }
        } catch (e) {
          try {
            request.response.statusCode = HttpStatus.internalServerError;
            request.response.write('Error: $e');
            await request.response.close();
          } catch (_) {}
        }
      });
      return true;
    } catch (e) {
      _addLog('فشل في تشغيل الخادم: $e');
      isRunningNotifier.value = false;
      return false;
    }
  }

  Future<void> stopServer() async {
    if (_server != null) {
      await _server!.close(force: true);
      _server = null;
      isRunningNotifier.value = false;
      _addLog('تم إيقاف خادم المشاركة');
    }
  }

  void _addLog(String msg) {
    final now = DateTime.now();
    final timeStr = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';
    final current = List<String>.from(logsNotifier.value);
    current.insert(0, '[$timeStr] $msg');
    if (current.length > 50) current.removeLast();
    logsNotifier.value = current;
  }

  Future<void> _serveHtmlPage(HttpRequest request) async {
    final files = await BackendService().getDownloadedFiles();
    final response = request.response;
    response.headers.contentType = ContentType.html;

    final buffer = StringBuffer();
    buffer.write('''
<!DOCTYPE html>
<html lang="ar" dir="rtl">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Boykta Pro - مشاركة الملفات عبر الـ Wi-Fi</title>
  <style>
    :root {
      --bg: #0A0A0F;
      --card: #161622;
      --card-hover: #1E1E30;
      --cyan: #00D9FF;
      --magenta: #FF007A;
      --text: #F1F1F6;
      --muted: #8E8EA8;
      --border: rgba(255, 255, 255, 0.08);
    }
    * { box-sizing: border-box; margin: 0; padding: 0; font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif; }
    body { background-color: var(--bg); color: var(--text); padding: 25px; line-height: 1.6; }
    .container { max-width: 900px; margin: 0 auto; }
    .header { text-align: center; margin-bottom: 30px; padding: 25px; background: linear-gradient(135deg, rgba(0,217,255,0.1), rgba(255,0,122,0.1)); border-radius: 20px; border: 1px solid var(--border); }
    .header h1 { font-size: 26px; color: #fff; margin-bottom: 8px; display: flex; align-items: center; justify-content: center; gap: 10px; }
    .header p { color: var(--muted); font-size: 14px; }
    .stats { display: flex; justify-content: center; gap: 20px; margin-top: 15px; }
    .stat-badge { background: rgba(255,255,255,0.05); padding: 6px 16px; border-radius: 20px; font-size: 13px; font-weight: bold; border: 1px solid var(--border); }
    .file-list { display: flex; flex-direction: column; gap: 12px; }
    .file-card { display: flex; align-items: center; justify-content: space-between; background: var(--card); padding: 14px 18px; border-radius: 14px; border: 1px solid var(--border); transition: all 0.2s ease; }
    .file-card:hover { background: var(--card-hover); border-color: rgba(0,217,255,0.3); transform: translateY(-1px); }
    .file-info { display: flex; align-items: center; gap: 14px; flex: 1; min-width: 0; }
    .file-icon { width: 44px; height: 44px; border-radius: 10px; display: flex; align-items: center; justify-content: center; font-size: 20px; flex-shrink: 0; }
    .icon-video { background: rgba(0, 217, 255, 0.15); color: var(--cyan); }
    .icon-audio { background: rgba(255, 0, 122, 0.15); color: var(--magenta); }
    .icon-doc { background: rgba(255, 255, 255, 0.1); color: #fff; }
    .file-name { font-weight: bold; font-size: 14px; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
    .file-meta { font-size: 12px; color: var(--muted); display: flex; gap: 10px; align-items: center; }
    .actions { display: flex; gap: 8px; flex-shrink: 0; }
    .btn { display: inline-flex; align-items: center; gap: 6px; padding: 8px 14px; border-radius: 8px; text-decoration: none; font-size: 13px; font-weight: bold; cursor: pointer; border: none; transition: 0.2s; }
    .btn-download { background: var(--cyan); color: #000; }
    .btn-download:hover { background: #33e2ff; }
    .btn-play { background: rgba(255,255,255,0.08); color: #fff; }
    .btn-play:hover { background: rgba(255,255,255,0.15); }
    .empty { text-align: center; padding: 50px 20px; color: var(--muted); }
  </style>
</head>
<body>
  <div class="container">
    <div class="header">
      <h1>⚡ Boykta Pro - مشاركة الملفات عبر الـ Wi-Fi</h1>
      <p>تصفح وحمّل جميع مقاطع الفيديو والصوتيات المحملة في هاتفك مباشرة على جهاز الكمبيوتر بدون إنترنت وبسرعة فائقة</p>
      <div class="stats">
        <div class="stat-badge">📂 إجمالي الملفات: ${files.length}</div>
        <div class="stat-badge" style="color: var(--cyan);">📶 متصل بشبكة Wi-Fi المحلية</div>
      </div>
    </div>
''');

    if (files.isEmpty) {
      buffer.write('''
    <div class="empty">
      <h2>لا توجد ملفات محملة حالياً</h2>
      <p>قم بتحميل مقاطع من التطبيق لتظهر هنا فوراً وتتمكن من تحميلها على الكمبيوتر</p>
    </div>
''');
    } else {
      buffer.write('<div class="file-list">');
      for (var f in files) {
        if (f is! File) continue;
        final name = f.path.split('/').last;
        final p = name.toLowerCase();
        final isAudio = p.endsWith('.mp3') || p.endsWith('.m4a') || p.endsWith('.wav') || p.endsWith('.aac') || p.endsWith('.ogg');
        final isVideo = p.endsWith('.mp4') || p.endsWith('.mkv') || p.endsWith('.webm') || p.endsWith('.mov');
        
        String sizeStr = 'غير معروف';
        try {
          final bytes = f.lengthSync();
          sizeStr = bytes >= 1024 * 1024
              ? '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB'
              : '${(bytes / 1024).toStringAsFixed(1)} KB';
        } catch (_) {}

        final iconClass = isAudio ? 'icon-audio' : (isVideo ? 'icon-video' : 'icon-doc');
        final iconEmoji = isAudio ? '🎵' : (isVideo ? '🎬' : '📄');
        final encodedPath = Uri.encodeComponent(f.path);

        buffer.write('''
      <div class="file-card">
        <div class="file-info">
          <div class="file-icon $iconClass">$iconEmoji</div>
          <div style="min-width: 0;">
            <div class="file-name" title="$name">$name</div>
            <div class="file-meta">
              <span>$sizeStr</span>
              <span>•</span>
              <span>${isAudio ? 'ملف صوتي' : (isVideo ? 'فيديو' : 'مستند')}</span>
            </div>
          </div>
        </div>
        <div class="actions">
          <a class="btn btn-play" href="/stream?file=$encodedPath" target="_blank">تشغيل 👁️</a>
          <a class="btn btn-download" href="/download?file=$encodedPath">تحميل ⬇️</a>
        </div>
      </div>
''');
      }
      buffer.write('</div>');
    }

    buffer.write('''
  </div>
</body>
</html>
''');

    response.write(buffer.toString());
    await response.close();
  }


  Future<bool> _isPathAllowed(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) return false;
      final canonicalPath = file.resolveSymbolicLinksSync();
      if (canonicalPath.contains(".vault_private")) return false;

      final downloadedFiles = await _backend.getDownloadedFiles();
      for (final f in downloadedFiles) {
        try {
          if (f.resolveSymbolicLinksSync() == canonicalPath) {
            return true;
          }
        } catch (_) {
          if (f.path == filePath || f.path == canonicalPath) {
            return true;
          }
        }
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<void> _serveDownload(HttpRequest request) async {
    final filePath = request.uri.queryParameters['file'];
    if (filePath == null) {
      request.response.statusCode = HttpStatus.badRequest;
      await request.response.close();
      return;
    }
    if (!await _isPathAllowed(filePath)) {
      request.response.statusCode = HttpStatus.forbidden;
      request.response.write("Access denied");
      await request.response.close();
      return;
    }

    final file = File(filePath);
    if (!await file.exists()) {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }

    final fileName = file.path.split('/').last;
    final fileLength = await file.length();

    request.response.headers.set('Content-Disposition', 'attachment; filename="${Uri.encodeComponent(fileName)}"');
    request.response.headers.set(HttpHeaders.contentLengthHeader, fileLength.toString());
    request.response.headers.contentType = ContentType.binary;

    await file.openRead().pipe(request.response);
  }

  Future<void> _serveStream(HttpRequest request) async {
    final filePath = request.uri.queryParameters['file'];
    if (filePath == null) {
      request.response.statusCode = HttpStatus.badRequest;
      await request.response.close();
      return;
    }
    if (!await _isPathAllowed(filePath)) {
      request.response.statusCode = HttpStatus.forbidden;
      request.response.write("Access denied");
      await request.response.close();
      return;
    }

    final file = File(filePath);
    if (!await file.exists()) {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }

    final lower = filePath.toLowerCase();
    ContentType contentType;
    if (lower.endsWith('.mp4')) {
      contentType = ContentType('video', 'mp4');
    } else if (lower.endsWith('.mp3')) {
      contentType = ContentType('audio', 'mpeg');
    } else if (lower.endsWith('.m4a')) {
      contentType = ContentType('audio', 'mp4');
    } else {
      contentType = ContentType.binary;
    }

    final fileLength = await file.length();
    final rangeHeader = request.headers.value(HttpHeaders.rangeHeader);

    if (rangeHeader != null && rangeHeader.startsWith('bytes=')) {
      final parts = rangeHeader.substring(6).split('-');
      final start = int.parse(parts[0]);
      final end = parts.length > 1 && parts[1].isNotEmpty ? int.parse(parts[1]) : fileLength - 1;

      request.response.statusCode = HttpStatus.partialContent;
      request.response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
      request.response.headers.set(HttpHeaders.contentRangeHeader, 'bytes $start-$end/$fileLength');
      request.response.headers.set(HttpHeaders.contentLengthHeader, (end - start + 1).toString());
      request.response.headers.contentType = contentType;

      await file.openRead(start, end + 1).pipe(request.response);
    } else {
      request.response.statusCode = HttpStatus.ok;
      request.response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
      request.response.headers.set(HttpHeaders.contentLengthHeader, fileLength.toString());
      request.response.headers.contentType = contentType;

      await file.openRead().pipe(request.response);
    }
  }
}
