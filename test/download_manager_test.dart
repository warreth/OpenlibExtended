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

  /// Number of GET requests that respond 500 before serving normally, to
  /// simulate an overloaded mirror.
  int failNextGets = 0;
  int failedGets = 0;

  _RangeServer(this._server, this.bytes,
      {this.supportsRange = true, this.chunkDelay});

  Uri get url => Uri.parse('http://127.0.0.1:${_server.port}/book.epub');

  /// The bound port, for restarting "the same mirror" after an outage.
  int get port => _server.port;

  static Future<_RangeServer> start(
      {required Uint8List bytes,
      bool supportsRange = true,
      Duration? chunkDelay,
      int port = 0}) async {
    final server =
        await HttpServer.bind(InternetAddress.loopbackIPv4, port);
    return _RangeServer(server, bytes,
        supportsRange: supportsRange, chunkDelay: chunkDelay);
  }

  Future<void> _send(HttpResponse response, Uint8List data) async {
    if (chunkDelay == null) {
      response.add(data);
    } else {
      const chunkSize = 16 * 1024;
      for (var i = 0; i < data.length; i += chunkSize) {
        response.add(data.sublist(i, (i + chunkSize).clamp(0, data.length)));
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

    if (failNextGets > 0) {
      failNextGets--;
      failedGets++;
      request.response.statusCode = 500;
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
      final end =
          match.group(2)!.isEmpty || int.parse(match.group(2)!) >= bytes.length
              ? bytes.length - 1
              : int.parse(match.group(2)!);

      request.response.statusCode = HttpStatus.partialContent;
      request.response.headers.set(
          HttpHeaders.contentRangeHeader, 'bytes $start-$end/${bytes.length}');
      request.response.headers
          .set(HttpHeaders.contentLengthHeader, end - start + 1);
      await _send(request.response, bytes.sublist(start, end + 1));
      request.response.close();
      return;
    }
    request.response.headers
        .set(HttpHeaders.acceptRangesHeader, supportsRange ? 'bytes' : 'none');
    request.response.headers.set(HttpHeaders.contentLengthHeader, bytes.length);
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
      final bytes =
          Uint8List.fromList(List.generate(1024 * 200, (i) => (i * 7) % 251));
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
        if (!pausedOnce &&
            t.status == DownloadStatus.downloading &&
            t.progress > 0.3 &&
            t.progress < 0.9) {
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
      expect(
          File('${dir.path}/${generateBookFileName(title: 'Vanishing Dir Book', format: 'epub', md5: 'md5hash_004')}')
              .existsSync(),
          isTrue);

      manager.removeDownload(task.id);
    }, timeout: const Timeout(Duration(seconds: 60)));

    test('rejects a second task for the same book (md5 dedupe)', () async {
      final bytes =
          Uint8List.fromList(List.generate(50 * 1024, (i) => i % 251));
      server = await _RangeServer.start(bytes: bytes);
      server._server.listen(server.handle);

      final taskA = DownloadTask(
        id: 'md5hash_005_a',
        md5: 'md5hash_005',
        title: 'Deduped Book',
        mirrors: [server.url.toString()],
        format: 'epub',
        link: server.url.toString(),
      );
      // Same book pressed again milliseconds later: different timestamped id,
      // identical md5 and target file.
      final taskB = DownloadTask(
        id: 'md5hash_005_b',
        md5: 'md5hash_005',
        title: 'Deduped Book',
        mirrors: [server.url.toString()],
        format: 'epub',
        link: server.url.toString(),
      );

      final completed = Completer<void>();
      manager.downloadsStream.listen((downloads) {
        final t = downloads[taskA.id];
        if (t?.status == DownloadStatus.completed && !completed.isCompleted) {
          completed.complete();
        }
      });

      await manager.addDownload(taskA);
      await manager.addDownload(taskB);

      expect(manager.activeDownloads.containsKey(taskB.id), isFalse,
          reason: 'second task for the same md5 must be rejected');

      await completed.future.timeout(const Duration(seconds: 30));

      final saved = File(
          '$saveDir/${generateBookFileName(title: 'Deduped Book', format: 'epub', md5: 'md5hash_005')}');
      expect(saved.lengthSync(), bytes.length,
          reason: 'the single accepted task must finish cleanly');

      manager.removeDownload(taskA.id);
    }, timeout: const Timeout(Duration(seconds: 60)));

    test('retries a transient 500 from the mirror and completes', () async {
      final bytes =
          Uint8List.fromList(List.generate(60 * 1024, (i) => (i * 3) % 251));
      server = await _RangeServer.start(bytes: bytes);
      server.failNextGets = 2; // two 500s, then success
      server._server.listen(server.handle);

      final task = DownloadTask(
        id: 'md5hash_006',
        md5: 'md5hash_006',
        title: 'Flaky Mirror Book',
        mirrors: [server.url.toString()],
        format: 'epub',
        link: server.url.toString(),
      );

      final completed = Completer<void>();
      manager.downloadsStream.listen((downloads) {
        final t = downloads[task.id];
        if (t?.status == DownloadStatus.completed && !completed.isCompleted) {
          completed.complete();
        }
      });

      await manager.addDownload(task);
      await completed.future.timeout(const Duration(seconds: 60));

      expect(server.failedGets, 2,
          reason: 'the manager must have hit the injected 500s');
      final saved = File(
          '$saveDir/${generateBookFileName(title: 'Flaky Mirror Book', format: 'epub', md5: 'md5hash_006')}');
      expect(saved.lengthSync(), bytes.length);
      expect(saved.readAsBytesSync(), bytes,
          reason: 'backoff retry must produce the exact file');

      manager.removeDownload(task.id);
    }, timeout: const Timeout(Duration(seconds: 90)));
    test('server without Range support restarts cleanly from zero', () async {
      final bytes =
          Uint8List.fromList(List.generate(1024 * 100, (i) => (i * 13) % 251));
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
        if (!pausedOnce &&
            t.status == DownloadStatus.downloading &&
            t.progress > 0.4 &&
            t.progress < 0.9) {
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

    test('resumeInterruptedDownloads picks up after app suspension', () async {
      // The Android backgrounding story: the OS cuts the socket
      // mid-transfer. On foreground return, resumeInterruptedDownloads
      // must continue failed/paused tasks from their partial files
      // instead of leaving them dead.
      final bytes =
          Uint8List.fromList(List.generate(1024 * 200, (i) => (i * 13) % 251));
      server = await _RangeServer.start(
          bytes: bytes, chunkDelay: const Duration(milliseconds: 25));
      server._server.listen(server.handle);

      final task = DownloadTask(
        id: 'md5hash_bg',
        md5: 'md5hash_bg',
        title: 'Background Book',
        mirrors: [server.url.toString()],
        format: 'epub',
        link: server.url.toString(),
      );

      final completed = Completer<void>();
      final fileName = generateBookFileName(
          title: 'Background Book', format: 'epub', md5: 'md5hash_bg');
      var partialBytesAtFailure = 0;

      manager.downloadsStream.listen((downloads) {
        final t = downloads[task.id];
        if (t == null) return;
        if (t.status == DownloadStatus.completed && !completed.isCompleted) {
          completed.complete();
        }
      });

      await manager.addDownload(task);

      // Simulate the OS suspension: kill the server mid-transfer. The
      // download fails with the socket gone, leaving a partial file.
      await Future<void>.delayed(const Duration(milliseconds: 400));
      final serverPort = server.port; // read before the socket closes
      await server.close();
      final partial = File('$saveDir/$fileName');
      if (partial.existsSync()) {
        partialBytesAtFailure = partial.lengthSync();
      }
      // Drain the failure: mirrors exhausted takes a moment.
      for (var i = 0; i < 100; i++) {
        final t = manager.activeDownloads[task.id];
        if (t != null && t.status == DownloadStatus.failed) break;
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
      expect(manager.activeDownloads[task.id]?.status, DownloadStatus.failed,
          reason: 'the socket cut must fail the task, not hang it');

      // The app "comes back": new server, same URL, and the manager
      // resumes everything interrupted.
      // Same port as before: a real suspension resumes against the same
      // mirror URL - the server just came back after being unreachable.
      server = await _RangeServer.start(
          bytes: bytes,
          chunkDelay: const Duration(milliseconds: 5),
          port: serverPort);
      server._server.listen(server.handle);

      await manager.resumeInterruptedDownloads();
      await completed.future.timeout(const Duration(seconds: 40));

      final saved = File('$saveDir/$fileName');
      expect(saved.lengthSync(), bytes.length);
      expect(saved.readAsBytesSync(), bytes,
          reason: 'resumed transfer must be byte-identical');
      if (partialBytesAtFailure > 0) {
        expect(partialBytesAtFailure, lessThan(bytes.length),
            reason: 'the cut must have happened mid-transfer');
      }

      manager.removeDownload(task.id);
    }, timeout: const Timeout(Duration(seconds: 90)));
  });
}
