import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openlib/cli/annas_archive.dart';
import 'package:openlib/cli/runner.dart';
import 'package:openlib/core/slum.dart';

class _RunResult {
  final int code;
  final String out;
  final String err;
  _RunResult(this.code, this.out, this.err);

  Map<String, dynamic> get json => jsonDecode(out) as Map<String, dynamic>;
}

class FakeClient implements CliArchiveClient {
  final List<CliBook> books;
  final CliBookDetails? details;
  final Object? searchError;
  final Object? infoError;
  final Object? resolveError;
  final Object? downloadError;
  final int downloadBytes;
  final int progressCalls;
  String? savedPath;

  FakeClient({
    this.books = const [],
    this.details,
    this.searchError,
    this.infoError,
    this.resolveError,
    this.downloadError,
    this.downloadBytes = 42,
    this.progressCalls = 0,
  });

  @override
  Future<List<CliBook>> searchBooks(
    String query, {
    String content = '',
    String sort = '',
    String fileType = '',
    String language = '',
    String? yearFrom,
    String? yearTo,
    String author = '',
    String publisher = '',
    int page = 1,
  }) async {
    if (searchError != null) throw searchError!;
    return books;
  }

  @override
  Future<CliBookDetails> bookInfo(String md5OrUrl) async {
    if (infoError != null) throw infoError!;
    return details!;
  }

  @override
  Future<String> resolveSlowDownload(String slowDownloadUrl) async {
    if (resolveError != null) throw resolveError!;
    return slowDownloadUrl;
  }

  @override
  Future<int> downloadFile({
    required String url,
    required String savePath,
    void Function(int received, int? total)? onProgress,
  }) async {
    savedPath = savePath;
    if (downloadError != null) throw downloadError!;
    for (var i = 1; i <= progressCalls; i++) {
      onProgress?.call(i, progressCalls);
    }
    return downloadBytes;
  }
}

const _details = CliBookDetails(
  title: 'Villa Coco',
  author: 'Alice Author',
  link: 'https://mirror/md5/abc',
  md5: '9fbeb1ac79a509bcc8a17d6137b929e7',
  publisher: 'Publisher',
  info: 'English [en], epub, 1.2MB, 2021',
  description: 'A novel.',
  slowDownloadUrl: 'https://mirror/slow_download/a/0/0',
);

Future<_RunResult> _run(
  List<String> args, {
  CliArchiveClient? client,
  List<SlumSite>? mirrors,
}) async {
  final out = StringBuffer();
  final err = StringBuffer();
  final runner = CliRunner(
    writeOut: out.write,
    writeErr: err.write,
    clientFactory: client == null ? null : (_) async => client,
    mirrorsLoader: mirrors == null ? null : () async => mirrors,
  );
  final code = await runner.run(args);
  return _RunResult(code, out.toString(), err.toString());
}

void main() {
  test('no arguments prints help and exits 1', () async {
    final result = await _run([]);
    expect(result.code, 1);
    expect(result.out, contains('Usage'));
    expect(result.err, isEmpty);
  });

  test('--help exits 0', () async {
    final result = await _run(['--help']);
    expect(result.code, 0);
    expect(result.out, contains('Usage'));
  });

  test('unknown options are a usage error', () async {
    final result = await _run(['search', 'dune', '--bogus']);
    expect(result.code, 1);
    expect(result.json['error']['code'], 'usage');
    expect(result.out.trim().split('\n'), hasLength(1));
  });

  test('a value option without a value is a usage error', () async {
    final result = await _run(['search', 'dune', '--limit']);
    expect(result.code, 1);
    expect(result.json['error']['code'], 'usage');
  });

  test('invalid numbers are a usage error', () async {
    for (final args in [
      <String>['search', 'dune', '--limit', '0'],
      <String>['search', 'dune', '--page', 'nope'],
      <String>['search', 'dune', '--timeout', '0'],
    ]) {
      final result = await _run(args);
      expect(result.code, 1, reason: args.join(' '));
      expect(result.json['error']['code'], 'usage');
    }
  });

  test('an invalid base URL is a usage error', () async {
    final result = await _run([
      'search',
      'dune',
      '--base-url',
      'not-a-url',
      '--limit',
      '1',
    ]);
    expect(result.code, 1);
    expect(result.json['error']['code'], 'usage');
  });

  test('unknown commands are a usage error', () async {
    final result = await _run(['frobnicate']);
    expect(result.code, 1);
    expect(result.json['error']['code'], 'usage');
  });

  test('search emits one JSON result and honours the limit', () async {
    final client = FakeClient(books: [
      const CliBook(
        title: 'Dune',
        link: 'https://mirror/md5/a',
        md5: 'a',
        info: 'epub',
      ),
      const CliBook(
        title: 'Dune Messiah',
        link: 'https://mirror/md5/b',
        md5: 'b',
        info: 'epub',
      ),
    ]);
    final result = await _run(
      ['search', 'dune', '--limit', '1'],
      client: client,
    );
    expect(result.code, 0);
    expect(result.json['count'], 1);
    expect(result.json['results'], hasLength(1));
    expect(result.err, isEmpty);
  });

  test('--quiet suppresses progress events', () async {
    final result = await _run(
      ['download', 'abc', '--quiet'],
      client: FakeClient(details: _details, progressCalls: 3),
    );
    expect(result.code, 0);
    expect(result.err, isEmpty);
  });

  test('missing books exit 3, not 4', () async {
    final result = await _run(
      ['info', 'abc'],
      client: FakeClient(infoError: CliNotFoundException('no record')),
    );
    expect(result.code, 3);
    expect(result.json['error']['code'], 'not_found');
  });

  test('challenge-blocked exits 2', () async {
    final result = await _run(
      ['info', 'abc'],
      client: FakeClient(infoError: CliBlockException('blocked')),
    );
    expect(result.code, 2);
    expect(result.json['error']['code'], 'blocked');
  });

  test('network failures exit 4', () async {
    final result = await _run(
      ['info', 'abc'],
      client: FakeClient(infoError: CliNetworkException('offline')),
    );
    expect(result.code, 4);
    expect(result.json['error']['code'], 'network');
  });

  test('a book without a slow download link exits 3', () async {
    const details = CliBookDetails(
      title: 'Fast only',
      author: 'Author',
      link: 'https://mirror/md5/abc',
      md5: 'abc',
      publisher: 'Publisher',
      info: 'epub',
    );
    final result = await _run(
      ['download', 'abc'],
      client: FakeClient(details: details),
    );
    expect(result.code, 3);
    expect(result.json['error']['code'], 'not_found');
  });

  test('download writes into a dotted parent directory', () async {
    final root = await Directory.systemTemp.createTemp('cli-output');
    addTearDown(() => root.delete(recursive: true));
    final target = '${root.path}/books.v2/sub';
    final client = FakeClient(details: _details);
    final result = await _run(
      ['download', 'abc', '--output', target],
      client: client,
    );
    expect(result.code, 0);
    expect(client.savedPath, startsWith('$target${Platform.pathSeparator}'));
    expect(Directory(target).existsSync(), isTrue);
  });

  test('download progress is throttled and still reported', () async {
    final result = await _run(
      ['download', 'abc'],
      client: FakeClient(details: _details, progressCalls: 200),
    );
    expect(result.code, 0);
    final progress = result.err
        .trim()
        .split('\n')
        .where((line) => line.contains('"step":"downloading"'))
        .length;
    expect(progress, greaterThan(0));
    expect(progress, lessThan(200));
  });

  test('mirrors reports down mirrors too', () async {
    final result = await _run(
      ['mirrors'],
      mirrors: const [
        SlumSite(
          service: MirrorService.annasArchive,
          url: 'https://up.example',
          host: 'up.example',
          status: SlumStatus.up,
          protection: Protection.none,
        ),
        SlumSite(
          service: MirrorService.annasArchive,
          url: 'https://down.example',
          host: 'down.example',
          status: SlumStatus.down,
          protection: Protection.unknown,
        ),
      ],
    );
    expect(result.code, 0);
    expect(result.json['count'], 2);
    expect(
      (result.json['mirrors'] as List).map((m) => m['status']),
      containsAll(['up', 'down']),
    );
  });

  test('an empty mirror list is a network error', () async {
    final result = await _run(['search', 'dune'], mirrors: const []);
    expect(result.code, 4);
    expect(result.json['error']['code'], 'network');
  });
}
