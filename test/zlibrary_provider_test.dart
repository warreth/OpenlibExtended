// Real tests for the Z-Library provider: the z-bookcard parser against
// a live-captured results page, the DiamWall 503 solver against a
// live-captured challenge page, and graceful failure when every mirror
// is unreachable.

// Dart imports:
import 'dart:io';

// Flutter imports:
import 'package:flutter_test/flutter_test.dart';

// Package imports:
import 'package:crypto/crypto.dart' as crypto;
import 'package:dio/dio.dart';

// Project imports:
import 'package:openlib/services/diamwall_solver.dart';
import 'package:openlib/services/search_manager.dart';

void main() {
  test('German filter reaches Z-Library and returns the filtered edition',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final requests = <Uri>[];
    server.listen((request) async {
      requests.add(request.uri);
      final german = request.uri.queryParameters['languages[]'] == 'german';
      request.response.write(
          '<z-bookcard href="/book/1/test" language="${german ? 'German' : 'Spanish'}" extension="epub"><div slot="title">${german ? 'German edition' : 'Spanish edition'}</div></z-bookcard>');
      await request.response.close();
    });
    final provider =
        ZlibraryProvider(mirrors: ['http://127.0.0.1:${server.port}']);
    final books = await provider.search(const SearchQuery(
        text: 'pihkal',
        language: 'de',
        fileType: 'epub',
        filtersEnabled: true));
    expect(books.single.info, startsWith('German,'));
    expect(requests.single.queryParameters['languages[]'], 'german');
    expect(requests.single.queryParameters['extensions[]'], 'EPUB');
    requests.clear();
    await provider.search(const SearchQuery(text: 'pihkal', language: 'de'));
    expect(requests.single.queryParameters, isNot(contains('languages[]')));
  });

  test('language filter excludes mislabeled results returned by the server',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      request.response.write('''
<z-bookcard href="/book/1/german" language="German" extension="epub"><div slot="title">German edition</div></z-bookcard>
<z-bookcard href="/book/2/english" language="English" extension="epub"><div slot="title">Stray English result</div></z-bookcard>
<z-bookcard href="/book/3/unknown" extension="epub"><div slot="title">Unknown language</div></z-bookcard>
''');
      await request.response.close();
    });
    final provider =
        ZlibraryProvider(mirrors: ['http://127.0.0.1:${server.port}']);
    final filtered = await provider.search(const SearchQuery(
        text: 'pihkal', language: 'de', filtersEnabled: true));
    expect(filtered.map((book) => book.title), ['German edition']);
    final all = await provider.search(const SearchQuery(text: 'pihkal'));
    expect(all, hasLength(3));
  });

  test('file type filter uses the form value and drops mismatches', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final requests = <Uri>[];
    server.listen((request) async {
      requests.add(request.uri);
      request.response.write('''
<z-bookcard href="/book/1/epub" language="English" extension="epub"><div slot="title">EPUB edition</div></z-bookcard>
<z-bookcard href="/book/2/pdf" language="English" extension="pdf"><div slot="title">PDF edition</div></z-bookcard>
''');
      await request.response.close();
    });
    final provider =
        ZlibraryProvider(mirrors: ['http://127.0.0.1:${server.port}']);
    final filtered = await provider.search(const SearchQuery(
        text: 'pihkal', fileType: 'epub', filtersEnabled: true));
    expect(filtered.map((book) => book.title), ['EPUB edition']);
    expect(requests.single.queryParameters['extensions[]'], 'EPUB');
  });

  test('book details try the result origin before unrelated mirrors', () async {
    final hits = <String>[];
    final html = File('test/fixtures/zlib_book_page.html').readAsStringSync();
    Future<HttpServer> server(String name) async {
      final s = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      s.listen((r) async {
        hits.add(name);
        r.response.write(html);
        await r.response.close();
      });
      addTearDown(() => s.close(force: true));
      return s;
    }

    final unrelated = await server('unrelated');
    final original = await server('original');
    final provider = ZlibraryProvider(mirrors: [
      'http://127.0.0.1:${unrelated.port}',
      'http://127.0.0.1:${original.port}'
    ]);
    final result = await provider
        .bookInfo('http://127.0.0.1:${original.port}/book/123/title.html');
    expect(result, isNotNull);
    expect(hits, ['original']);
  });

  test('book details stop when the total time budget expires', () async {
    var calls = 0;
    final s = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    s.listen((r) {
      calls++;
    }); // deliberately never answer
    addTearDown(() => s.close(force: true));
    final url = 'http://127.0.0.1:${s.port}';
    final provider = ZlibraryProvider(mirrors: [url, url]);
    final result = await provider.bookInfo('$url/book/123/title.html',
        timeout: const Duration(milliseconds: 80));
    expect(result, isNull);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(calls, 1,
        reason: 'timed-out work must not continue to more mirrors');
  }, timeout: const Timeout(Duration(seconds: 3)));

  final challenge =
      File('test/fixtures/diamwall_challenge.html').readAsStringSync();
  final results =
      File('test/fixtures/zlib_search_results.html').readAsStringSync();

  group('DiamWallSolver.looksLikeChallenge', () {
    test('recognizes the captured 503 challenge page', () {
      final solver = DiamWallSolver();
      expect(solver.looksLikeChallenge(503, challenge), isTrue);
      // A challenge body served with a non-503 status (cached copy,
      // soft challenge) is still recognized by its markers.
      expect(solver.looksLikeChallenge(200, challenge), isTrue);
    });

    test('does not flag normal pages or empty bodies', () {
      final solver = DiamWallSolver();
      expect(solver.looksLikeChallenge(503, ''), isTrue); // status alone
      expect(solver.looksLikeChallenge(200, results), isFalse);
      expect(solver.looksLikeChallenge(200, '<html><body>hello</body></html>'),
          isFalse);
    });
  });

  group('DiamWallSolver.solve', () {
    test('solves the captured challenge and returns c_token/c_time', () async {
      final solver = DiamWallSolver();
      final cookies = await solver.solve(challenge);

      expect(cookies, isNotNull);
      expect(cookies!.keys, containsAll(['c_token', 'c_time']));
      // c_token = seed + counter; the seed is the 40-hex prefix
      // (the live page embeds it in uppercase hex).
      final token = cookies['c_token']!;
      expect(token.length, greaterThan(40));
      expect(RegExp(r'^[0-9a-fA-F]{40}\d+$').hasMatch(token), isTrue,
          reason: 'c_token should be <40-hex seed><decimal counter>');
      // c_time parses as elapsed seconds.
      expect(double.tryParse(cookies['c_time']!), isNotNull);
    });

    test('solved token actually satisfies the embedded PoW check', () async {
      final solver = DiamWallSolver();
      final cookies = await solver.solve(challenge);
      final token = cookies!['c_token']!;

      // Re-derive n1 from the seed's first char, exactly like the page.
      final seed = token.substring(0, 40);
      final n1 = int.parse('0x${seed[0]}');
      final digest = _sha1Bytes(seed + token.substring(40));
      expect(digest[n1], 0xB0);
      expect(digest[n1 + 1], 0x0B);
    });

    test('returns null quickly for a page with no seed', () async {
      final solver = DiamWallSolver();
      // Strip the seed the same way the solver finds it - uppercase or
      // lowercase hex, followed by the c_token marker.
      final broken = challenge.replaceAll(
          RegExp(r"'[0-9a-fA-F]{40}'\s*,\s*'c_token='", caseSensitive: false),
          "'','c_token='");
      expect(solver.looksLikeChallenge(200, broken), isFalse,
          reason: 'marker detection keys on the seed too');
      final sw = Stopwatch()..start();
      final cookies = await solver.solve(broken);
      sw.stop();
      expect(cookies, isNull);
      expect(sw.elapsed, lessThan(const Duration(seconds: 2)));
    });

    test('brute force is bounded on an unsolvable seed', () async {
      // A seed whose n1 points at a byte pair no SHA1 hit satisfies
      // within the cap still terminates: craft a low-iteration variant
      // by checking the sync path directly against an empty page.
      final sw = Stopwatch()..start();
      final result = DiamWallSolver.solveSync('no seed here at all');
      sw.stop();
      expect(result, isNull);
      expect(sw.elapsed, lessThan(const Duration(seconds: 1)));
    });

    test('real-difficulty solve finishes well under the iteration cap',
        () async {
      // The captured page solved in ~10k iterations live; the solver
      // must not need anywhere near the 5M cap.
      final sw = Stopwatch()..start();
      final cookies = DiamWallSolver.solveSync(challenge);
      sw.stop();
      expect(cookies, isNotNull);
      expect(sw.elapsed, lessThan(const Duration(seconds: 10)));
    });
  });

  test('no-results page ignores hidden decoy book cards', () {
    final html =
        File('test/fixtures/zlib_hidden_no_results.html').readAsStringSync();
    expect(ZlibraryProvider().parseResults(html, 'https://z-lib.gl'), isEmpty);
  });

  test(
      'hidden result ancestors are excluded without rejecting visible opaque IDs',
      () {
    const card =
        '<z-bookcard href="/book/opaque123/title.html"><div slot="title">Visible book</div></z-bookcard>';
    final html = '<div hidden>$card</div><div aria-hidden="true">$card</div>'
        '<div aria-hidden="false">$card</div>';
    final books = ZlibraryProvider().parseResults(html, 'https://z-lib.gl');
    expect(books, hasLength(1));
    expect(books.single.md5, 'opaque123');
  });

  test('Z-Library details retain the book synopsis', () {
    final data = ZlibraryProvider().parseBookPage(
        '<h1 itemprop="name">A book</h1>'
            '<div id="bookDescriptionBox"><p>A first paragraph.</p><p>Another <b>important</b> paragraph.</p></div>',
        'https://z-lib.gl',
        'https://z-lib.gl/book/opaque123/title.html');
    expect(data!.description,
        'A first paragraph.\n\nAnother important paragraph.');
  });

  group('ZlibraryProvider.parseResults', () {
    test('parses z-bookcard elements from the captured live page', () {
      final provider = ZlibraryProvider();
      final books = provider.parseResults(results, 'https://z-lib.gd');

      expect(books, isNotEmpty);
      // Live page served 51 result cards per page.
      expect(books.length, greaterThanOrEqualTo(50));

      final first = books.first;
      expect(first.title, isNotEmpty);
      expect(first.title, 'Flutter-Interview-Questions-and-Answers');
      expect(first.link, startsWith('https://z-lib.gd/book/4XNVZObxX9/'));
      expect(first.md5, '4XNVZObxX9');
      expect(first.thumbnail, isNotNull);
      expect(first.info, contains('PDF'));
    });

    test('extracts authors, falling back to Unknown when absent', () {
      final provider = ZlibraryProvider();
      final books = provider.parseResults(results, 'https://z-lib.gd');

      final withAuthor =
          books.firstWhere((b) => b.author != null && b.author != 'Unknown');
      expect(withAuthor.author, isNotEmpty);
      expect(books.any((b) => b.author == 'Unknown'), anyOf(isTrue, isFalse));
    });

    test('skips cards without href or title', () {
      final provider = ZlibraryProvider();
      const html = '''
      <html><body>
        <z-bookcard href="/book/abc123/x.html"><div slot="title">T</div></z-bookcard>
        <z-bookcard><div slot="title">NoHref</div></z-bookcard>
        <z-bookcard href="/book/def456/y.html"><div slot="">EmptyTitle</div></z-bookcard>
      </body></html>
      ''';
      final books = provider.parseResults(html, 'https://z-lib.gd');
      expect(books.length, 1);
      expect(books.first.title, 'T');
      expect(books.first.md5, 'abc123');
      expect(books.first.author, 'Unknown');
    });

    test('uses the href id segment as the unique id (no md5 on zlib)', () {
      final provider = ZlibraryProvider();
      final books = provider.parseResults(results, 'https://z-lib.gd');
      final ids = books.map((b) => b.md5).toSet();
      expect(ids.length, books.length,
          reason: 'book ids must be unique per card');
      expect(ids.every((id) => RegExp(r'^[0-9a-zA-Z]+$').hasMatch(id)), isTrue);
    });
  });

  group('ZlibraryProvider graceful failure', () {
    test('all-unreachable mirrors return [] without throwing', () async {
      final provider = ZlibraryProvider(
        dio: Dio(BaseOptions(
          connectTimeout: const Duration(seconds: 2),
          receiveTimeout: const Duration(seconds: 2),
        )),
        mirrors: [
          'http://127.0.0.1:1', // closed port, fails fast
          'http://127.0.0.1:2',
        ],
      );
      final books = await provider.search(const SearchQuery(text: 'flutter'));
      expect(books, isEmpty);
    });

    test('search URL encodes spaces as %20 in path instead of +', () async {
      final requests = <String>[];
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((HttpRequest request) {
        requests.add(request.uri.toString());
        request.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType.html
          ..write(results)
          ..close();
      });

      try {
        final provider = ZlibraryProvider(
          mirrors: ['http://${server.address.host}:${server.port}'],
        );
        await provider.search(const SearchQuery(text: 'Pride and Prejudice'));

        expect(requests, isNotEmpty);
        expect(requests.first, equals('/s/Pride%20and%20Prejudice'));
        expect(requests.first, isNot(contains('+')));
      } finally {
        await server.close();
      }
    });

    test('no attemptable mirror means no request at all', () async {
      // What the provider gets when open-slum.org reports every Z-Library
      // mirror DOWN (or the user switched them all off): an empty list.
      // It must then make zero HTTP calls instead of guessing a URL.
      var requests = 0;
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) {
        requests++;
        request.response.statusCode = HttpStatus.ok;
        request.response.close();
      });

      try {
        final provider = ZlibraryProvider(
          mirrors: const [], // SLUM: nothing attemptable
        );
        final books = await provider.search(const SearchQuery(text: 'flutter'));

        expect(books, isEmpty);
        expect(requests, 0,
            reason: 'a down/unavailable mirror must never be contacted');
      } finally {
        await server.close();
      }
    });

    test('tries the mirrors in the order it was given', () async {
      // Auto mode hands the mirror list best-first (unprotected, then
      // DiamWall, ...). The provider must not reorder it.
      final hits = <String>[];
      final first = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      first.listen((request) {
        hits.add('first');
        request.response
          ..statusCode = HttpStatus.serviceUnavailable
          ..write('')
          ..close();
      });
      final second = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      second.listen((request) {
        hits.add('second');
        request.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType.html
          ..write(results)
          ..close();
      });

      try {
        final provider = ZlibraryProvider(mirrors: [
          'http://127.0.0.1:${first.port}',
          'http://127.0.0.1:${second.port}',
        ]);
        final books = await provider.search(const SearchQuery(text: 'flutter'));

        expect(hits, ['first', 'second']);
        expect(books, isNotEmpty);
      } finally {
        await first.close();
        await second.close();
      }
    });
  });

  // The /dl/ hop exactly as the mirrors run it: dead ids answer 204, the
  // live id answers 302 to a signed CDN URL, that URL serves the bytes,
  // and a throttled mirror answers with its "Daily limit reached" page.
  // A local server plays the protocol, so the resolver is exercised end
  // to end without depending on a mirror's mood.
  group('resolveBookDownload (real protocol, local server)', () {
    late HttpServer server;

    /// Serves a real book page, a CDN file and /dl/<id> ids.
    Future<HttpServer> startServer({
      String cdnPath = '/cdn/book.pdf',
      Set<String> redirectIds = const {},
      Set<String> limiterIds = const {},
      String limiterHtml = '',
      String bookPageHtml = '',
    }) async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final port = server.port;
      server.listen((request) async {
        final path = request.uri.path;
        if (path.startsWith('/dl/')) {
          final id = path.substring(4);
          if (redirectIds.contains(id)) {
            request.response
              ..statusCode = HttpStatus.found
              ..headers.set('location', 'http://127.0.0.1:$port$cdnPath');
          } else if (limiterIds.contains(id)) {
            request.response
              ..statusCode = HttpStatus.ok
              ..headers.contentType = ContentType.html
              ..write(limiterHtml);
          } else {
            request.response.statusCode = HttpStatus.noContent;
          }
        } else if (path == cdnPath) {
          request.response
            ..statusCode = HttpStatus.ok
            ..headers.contentType = ContentType.binary
            ..add(List<int>.generate(4096, (i) => i % 251));
        } else {
          request.response
            ..statusCode = HttpStatus.ok
            ..headers.contentType = ContentType.html
            ..write(bookPageHtml);
        }
        await request.response.close();
      });
      return server;
    }

    final bookPage =
        File('test/fixtures/zlib_book_page.html').readAsStringSync();
    final limiter =
        File('test/fixtures/zlib_daily_limit.html').readAsStringSync();

    /// The /dl/ ids the captured book page links to.
    List<String> bookPageDlIds(String html) => RegExp(r'href="/dl/([^"]+)"')
        .allMatches(html)
        .map((m) => m.group(1)!)
        .toSet()
        .toList();

    tearDown(() async {
      await server.close();
    });

    test('walks past the dead 204 ids and returns the signed CDN URL',
        () async {
      final ids = bookPageDlIds(bookPage);
      expect(ids.length, greaterThan(1),
          reason: 'the fixture must carry several /dl/ ids');

      server = await startServer(
        redirectIds: {ids.last},
        bookPageHtml: bookPage,
      );
      final provider =
          ZlibraryProvider(mirrors: ['http://127.0.0.1:${server.port}']);

      final result = await provider
          .resolveBookDownload('http://127.0.0.1:${server.port}/book/x/y.html');

      expect(result.url, 'http://127.0.0.1:${server.port}/cdn/book.pdf',
          reason: 'the first id that 302s must win');
    });

    test('the returned URL really serves the file bytes', () async {
      final ids = bookPageDlIds(bookPage);
      server = await startServer(
        redirectIds: {ids.first},
        bookPageHtml: bookPage,
      );
      final provider =
          ZlibraryProvider(mirrors: ['http://127.0.0.1:${server.port}']);

      final result = await provider
          .resolveBookDownload('http://127.0.0.1:${server.port}/book/x/y.html');
      expect(result.url, isNotNull);

      final download = await Dio().get<List<int>>(result.url!,
          options: Options(responseType: ResponseType.bytes));
      expect(download.data!.length, 4096);
      expect(download.data!.take(4).toList(), [0, 1, 2, 3]);
    });

    test('reports the daily-limit reason from the live limiter page', () async {
      final ids = bookPageDlIds(bookPage);
      server = await startServer(
        limiterIds: ids.toSet(),
        limiterHtml: limiter,
        bookPageHtml: bookPage,
      );
      final provider =
          ZlibraryProvider(mirrors: ['http://127.0.0.1:${server.port}']);

      final result = await provider
          .resolveBookDownload('http://127.0.0.1:${server.port}/book/x/y.html');

      expect(result.url, isNull);
      expect(result.refusal, isNotNull,
          reason: 'the limiter page names a reason the user can act on');
      expect(result.refusal, contains('Daily download limit'));
    });

    test('invents no reason when the page says nothing recognizable', () async {
      final ids = bookPageDlIds(bookPage);
      // A realistic unrecognized page: it carries the site nav, which
      // includes a "Login" link on every z-lib page. That must not be
      // mistaken for "sign in required".
      server = await startServer(
        limiterIds: ids.toSet(),
        limiterHtml: '<html><body><nav><a href="/login">Login</a>'
            '<a href="/registration">Create Account</a></nav>'
            '<p>Nothing to see here</p></body></html>',
        bookPageHtml: bookPage,
      );
      final provider =
          ZlibraryProvider(mirrors: ['http://127.0.0.1:${server.port}']);

      final result = await provider
          .resolveBookDownload('http://127.0.0.1:${server.port}/book/x/y.html');

      expect(result.url, isNull);
      expect(result.refusal, isNull,
          reason: 'never show a message the mirror did not give');
    });
  });
}

/// SHA1 digest bytes for the PoW verification test.
List<int> _sha1Bytes(String input) =>
    crypto.sha1.convert(input.codeUnits).bytes;
