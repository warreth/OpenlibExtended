// Drives the real DownloadManager end-to-end against a local HTTP server:
// verifies the full lifecycle (queue -> download -> verify -> complete),
// progress accounting, and pause/resume behavior with a real Range-capable
// server. No mocks of the manager itself; only the environment (sqlite, paths,
// notifications are inert on desktop) is faked.

// Dart imports:
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

// Package imports:
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

// Project imports:
import 'package:openlib/services/database.dart';
import 'package:openlib/services/download_manager.dart';
import 'package:openlib/services/files.dart' show generateBookFileName;

/// Minimal local file server with real Range support, like the real mirrors.
/// [chunkDelay] forces multi-chunk delivery so downloads can be paused
/// mid-transfer.
class _RangeServer {
  final HttpServer _server;
  final Uint8List bytes;
  final bool supportsRange;
  final Duration? chunkDelay;

  _RangeServer(this._server, this.bytes,
      {this.supportsRange = true, this.chunkDelay});

  Uri get url => Uri.parse('http://127.0.0.1:${_server.port}/book.epub');

  static Future<_RangeServer> start(
      {required Uint8List bytes,
      bool supportsRange = true,
      Duration? chunkDelay}) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    return _RangeServer(server, bytes,
        supportsRange: supportsRange, chunkDelay: chunkDelay);
  }

  Future<void> _send(HttpResponse response, Uint8List data) async {
    if (chunkDelay == null) {
      response.add(data);
    } else {
      const chunkSize = 16 * 1024;
      for (var i = 0; i < data.length; i += chunkSize) {
        response.add(data.sublist(
            i, (i + chunkSize).clamp(0, data.length)));
        await response.flush();
        await Future.delayed(chunkDelay!);
      }
    }
  }

  void handle(HttpRequest request) async {
    if (request.method == 'HEAD') {
      // _getAliveMirror probes with HEAD; respond without a body.
      request.response.statusCode = HttpStatus.ok;
      request.response.headers.set(
          HttpHeaders.acceptRangesHeader, supportsRange ? 'bytes' : 'none');
      request.response.close();
      return;
    }

    final rangeHeader = request.headers.value(HttpHeaders.rangeHeader);
    if (rangeHeader != null && supportsRange) {
      final match = RegExp(r'bytes=(\d*)-(\d*)').firstMatch(rangeHeader)!;
      final start = int.parse(match.group(1) ?? '0');
      if (start >= bytes.length) {
        // 416: what a completed-file resume attempt receives
        request.response.statusCode = 416;
        request.response.close();
        return;
      }
      final end = match.group(2)!.isEmpty || int.parse(match.group(2)!) >= bytes.length
          ? bytes.length - 1
          : int.parse(match.group(2)!);

      request.response.statusCode = HttpStatus.partialContent;
      request.response.headers.set(HttpHeaders.contentRangeHeader,
          'bytes $start-$end/${bytes.length}');
      request.response.headers
          .set(HttpHeaders.contentLengthHeader, end - start + 1);
      await _send(request.response, bytes.sublist(start, end + 1));
      request.response.close();
      return;
    }
    request.response.headers.set(
        HttpHeaders.acceptRangesHeader, supportsRange ? 'bytes' : 'none');
    request.response.headers
        .set(HttpHeaders.contentLengthHeader, bytes.length);
    // Server ignoring the Range header: reply 200 with the whole body,
    // exactly like the real slow-download mirrors do.
    await _send(request.response, bytes);
    request.response.close();
  }

  Future<void> close() => _server.close();
}

class _FakePathProvider extends PathProviderPlatform {
  // Unique per-suite base dir: flutter test runs test files concurrently, so
  // each suite needs its own sqlite DB / storage paths.
  static final String base =
      '/tmp/openlib_dl_test_${DateTime.now().millisecondsSinceEpoch}_$pid';

  Future<String> _dir(String name) async {
    final dir = Directory('$base/$name');
    await dir.create(recursive: true);
    return dir.path;
  }

  @override
  Future<String?> getApplicationSupportPath() => _dir('support');

  @override
  Future<String?> getApplicationDocumentsPath() => _dir('documents');

  @override
  Future<String?> getTemporaryPath() => _dir('temp');

  @override
  Future<String?> getLibraryPath() => _dir('library');
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    PathProviderPlatform.instance = _FakePathProvider();
  });

  group('DownloadManager end-to-end (local server)', () {
    late DownloadManager manager;
    late _RangeServer server;
    late String saveDir;

    setUp(() async {
      manager = DownloadManager();
      await manager.initialize();

      saveDir = (await _FakePathProvider().getTemporaryPath())!;
      // bookStorageDirectory preference is read by the manager
      await MyLibraryDb.instance
          .savePreference('bookStorageDirectory', saveDir);
    });

    tearDown(() async {
      await server.close();
    });

    test('completes and verifies a full download', () async {
      final bytes = Uint8List.fromList(
          List.generate(1024 * 300, (i) => i % 251)); // ~300KB
      server = await _RangeServer.start(bytes: bytes);
      server._server.listen(server.handle);

      final task = DownloadTask(
        id: 'md5hash_001',
        md5: 'md5hash_001',
        title: 'Test Book',
        mirrors: [server.url.toString()],
        format: 'epub',
        link: server.url.toString(),
      );

      final completer = Completer<void>();
      manager.downloadsStream.listen((downloads) {
        final t = downloads[task.id];
        if (t != null && t.status == DownloadStatus.completed) {
          completer.complete();
        }
      });

      await manager.addDownload(task);
      await completer.future.timeout(const Duration(seconds: 30));

      // The file must exist with exact content, under the real naming scheme.
      final saved = File(
          '$saveDir/${generateBookFileName(title: 'Test Book', format: 'epub', md5: 'md5hash_001')}');
      expect(saved.existsSync(), isTrue, reason: 'downloaded file exists');
      expect(saved.lengthSync(), bytes.length);
      expect(saved.readAsBytesSync(), bytes);

      manager.removeDownload(task.id);
    }, timeout: const Timeout(Duration(seconds: 60)));

    test('pause mid-download then resume continues from disk (Range server)',
        () async {
      final bytes = Uint8List.fromList(
          List.generate(1024 * 200, (i) => (i * 7) % 251));
      // 30ms per 16KB chunk: slow enough to pause in the middle.
      server = await _RangeServer.start(
          bytes: bytes, chunkDelay: const Duration(milliseconds: 30));
      server._server.listen(server.handle);

      final task = DownloadTask(
        id: 'md5hash_002',
        md5: 'md5hash_002',
        title: 'Range Book',
        mirrors: [server.url.toString()],
        format: 'epub',
        link: server.url.toString(),
      );

      final paused = Completer<void>();
      final completed = Completer<void>();
      var pausedOnce = false;
      var pausedProgress = 0.0;

      manager.downloadsStream.listen((downloads) {
        final t = downloads[task.id];
        if (t == null) return;
        if (!pausedOnce && t.status == DownloadStatus.downloading &&
            t.progress > 0.3 && t.progress < 0.9) {
          pausedOnce = true;
          pausedProgress = t.progress;
          manager.pauseDownload(task.id);
        }
        if (t.status == DownloadStatus.paused && !paused.isCompleted) {
          paused.complete();
          // Resume from the next event loop tick.
          Future.microtask(() => manager.resumeDownload(task.id));
        }
        if (t.status == DownloadStatus.completed && !completed.isCompleted) {
          completed.complete();
        }
      });

      await manager.addDownload(task);
      await paused.future.timeout(const Duration(seconds: 30));
      expect(pausedOnce, isTrue,
          reason: 'pause must happen mid-transfer, not after completion');

      await completed.future.timeout(const Duration(seconds: 30));

      final saved = File(
          '$saveDir/${generateBookFileName(title: 'Range Book', format: 'epub', md5: 'md5hash_002')}');
      expect(saved.lengthSync(), bytes.length);
      expect(saved.readAsBytesSync(), bytes,
          reason: 'resumed file must be byte-identical after pausing at '
              '${(pausedProgress * 100).toStringAsFixed(0)}%');

      manager.removeDownload(task.id);
    }, timeout: const Timeout(Duration(seconds: 90)));

    test('recreates a deleted storage directory instead of stalling', () async {
      // This is the real-world "stuck at 100%": the save directory (e.g. on
      // a removed drive or a deleted folder) no longer exists when the
      // download starts. The manager must recreate it and finish normally
      // rather than dying silently mid-transfer with progress frozen.
      final dir = Directory('${_FakePathProvider.base}/gone_md5hash_004');
      await dir.create(recursive: true);
      await MyLibraryDb.instance
          .savePreference('bookStorageDirectory', dir.path);

      final bytes =
          Uint8List.fromList(List.generate(50 * 1024, (i) => i % 251));
      server = await _RangeServer.start(bytes: bytes);
      server._server.listen(server.handle);

      final task = DownloadTask(
        id: 'md5hash_004',
        md5: 'md5hash_004',
        title: 'Vanishing Dir Book',
        mirrors: [server.url.toString()],
        format: 'epub',
        link: server.url.toString(),
      );

      final completed = Completer<void>();
      final failed = Completer<String>();
      manager.downloadsStream.listen((downloads) {
        final t = downloads[task.id];
        if (t == null) return;
        if (t.status == DownloadStatus.completed && !completed.isCompleted) {
          completed.complete();
        }
        if (t.status == DownloadStatus.failed && !failed.isCompleted) {
          failed.complete(t.errorMessage ?? 'unknown');
        }
      });

      // Remove the storage directory right before the download begins.
      await dir.delete(recursive: true);

      await manager.addDownload(task);
      final outcome = await Future.any([
        completed.future.then((_) => 'completed'),
        failed.future.then((m) => 'failed: $m'),
      ]).timeout(const Duration(seconds: 30));

      expect(outcome, 'completed',
          reason: 'deleted storage dir must be recreated, download must '
              'finish, got: $outcome');
      expect(File('${dir.path}/${generateBookFileName(
        title: 'Vanishing Dir Book', format: 'epub', md5: 'md5hash_004')}'
        ).existsSync(), isTrue);

      manager.removeDownload(task.id);
    }, timeout: const Timeout(Duration(seconds: 60)));

    test('server without Range support restarts cleanly from zero', () async {
      final bytes = Uint8List.fromList(
          List.generate(1024 * 100, (i) => (i * 13) % 251));
      server = await _RangeServer.start(
          bytes: bytes,
          supportsRange: false,
          chunkDelay: const Duration(milliseconds: 20));
      server._server.listen(server.handle);

      final task = DownloadTask(
        id: 'md5hash_003',
        md5: 'md5hash_003',
        title: 'No Range Book',
        mirrors: [server.url.toString()],
        format: 'epub',
        link: server.url.toString(),
      );

      final paused = Completer<void>();
      final completed = Completer<void>();
      var pausedOnce = false;

      manager.downloadsStream.listen((downloads) {
        final t = downloads[task.id];
        if (t == null) return;
        if (!pausedOnce && t.status == DownloadStatus.downloading &&
            t.progress > 0.4 && t.progress < 0.9) {
          pausedOnce = true;
          manager.pauseDownload(task.id);
        }
        if (t.status == DownloadStatus.paused && !paused.isCompleted) {
          paused.complete();
          Future.microtask(() => manager.resumeDownload(task.id));
        }
        if (t.status == DownloadStatus.completed && !completed.isCompleted) {
          completed.complete();
        }
      });

      await manager.addDownload(task);
      await paused.future.timeout(const Duration(seconds: 30));
      await completed.future.timeout(const Duration(seconds: 30));

      final saved = File(
          '$saveDir/${generateBookFileName(title: 'No Range Book', format: 'epub', md5: 'md5hash_003')}');
      expect(saved.lengthSync(), bytes.length);
      expect(saved.readAsBytesSync(), bytes,
          reason: 'restart-from-zero must still produce the correct file');

      manager.removeDownload(task.id);
    }, timeout: const Timeout(Duration(seconds: 90)));
  });
}
