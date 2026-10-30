import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openlib/cli/annas_archive.dart';

class _HtmlAdapter implements HttpClientAdapter {
  _HtmlAdapter(this.body, this.statusCode);

  final String body;
  final int statusCode;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return ResponseBody.fromString(
      body,
      statusCode,
      headers: {
        Headers.contentTypeHeader: [Headers.textPlainContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  test('a missing book survives the mirror walk as not-found', () async {
    final dio = Dio()
      ..httpClientAdapter =
          _HtmlAdapter('<html><body>no record</body></html>', 200);
    final client = CliAnnasArchive(
      dio: dio,
      mirrors: const ['https://a.example', 'https://b.example'],
      requestTimeout: const Duration(seconds: 1),
    );

    await expectLater(
      client.bookInfo('0123456789abcdef0123456789abcdef'),
      throwsA(isA<CliNotFoundException>()),
    );
  });

  test('plain 403s are reported as forbidden attempts', () async {
    final dio = Dio()
      ..httpClientAdapter =
          _HtmlAdapter('<html><body>forbidden</body></html>', 403);
    final client = CliAnnasArchive(
      dio: dio,
      mirrors: const ['https://a.example'],
      requestTimeout: const Duration(seconds: 1),
    );

    try {
      await client.searchBooks('dune');
      fail('expected a network failure');
    } on CliNetworkException catch (e) {
      expect(e.attempts, isNotEmpty);
      expect(e.attempts.first.kind, 'forbidden');
    }
  });

  test('challenge pages are reported as challenge attempts', () async {
    final dio = Dio()
      ..httpClientAdapter = _HtmlAdapter(
        '<html><head><title>Just a moment...</title></head></html>',
        403,
      );
    final client = CliAnnasArchive(
      dio: dio,
      mirrors: const ['https://a.example'],
      requestTimeout: const Duration(seconds: 1),
    );

    try {
      await client.searchBooks('dune');
      fail('expected a challenge failure');
    } on CliBlockException catch (e) {
      expect(e.attempts, isNotEmpty);
      expect(e.attempts.first.kind, 'challenge');
    }
  });

  test('download resumes, resets on 200 and accepts 416 as complete', () async {
    final dir = await Directory.systemTemp.createTemp('cli-download-test');
    addTearDown(() => dir.delete(recursive: true));

    final content = utf8.encode('hello world');
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));

    var mode = 'partial';
    server.listen((request) async {
      final response = request.response;
      final range = request.headers.value('range');
      if (mode == 'complete') {
        response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
        await response.close();
        return;
      }
      if (mode == 'ignore' || range == null) {
        response.statusCode = HttpStatus.ok;
        response.contentLength = content.length;
        response.add(content);
        await response.close();
        return;
      }
      response.statusCode = HttpStatus.partialContent;
      final rest = content.sublist(6);
      response.contentLength = rest.length;
      response.add(rest);
      await response.close();
    });

    final url = 'http://127.0.0.1:${server.port}/book';
    final file = File('${dir.path}/book.epub')
      ..writeAsBytesSync(content.sublist(0, 6));
    final client = CliAnnasArchive(
      mirrors: ['http://127.0.0.1:${server.port}'],
    );

    final resumed = await client.downloadFile(url: url, savePath: file.path);
    expect(resumed, content.length);
    expect(file.readAsBytesSync(), content);

    // A server that ignores Range must not append a second copy.
    file.writeAsBytesSync(content.sublist(0, 6));
    mode = 'ignore';
    final restarted = await client.downloadFile(url: url, savePath: file.path);
    expect(restarted, content.length);
    expect(file.readAsBytesSync(), content);

    // Range past EOF: the existing file is already complete.
    mode = 'complete';
    final alreadyComplete =
        await client.downloadFile(url: url, savePath: file.path);
    expect(alreadyComplete, content.length);
    expect(file.readAsBytesSync(), content);
  });
}
