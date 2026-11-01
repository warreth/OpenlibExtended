// Tests for the WeLib provider. The parser runs against a book page
// captured live from welib.org, so the assertions are about the real
// markup - including the related-books list, which uses the same
// `book-card` element the search results do.

// Dart imports:
import 'dart:io';

// Flutter imports:
import 'package:flutter_test/flutter_test.dart';

// Package imports:
import 'package:dio/dio.dart';

// Project imports:
import 'package:openlib/services/annas_archieve.dart';
import 'package:openlib/services/challenge_html_cache.dart';
import 'package:openlib/services/search_manager.dart';
import 'package:openlib/services/webview_challenge_solver.dart';

const _md5 = '00f8a97a0e03ac203235b306e249aa76';

String _fixture() =>
    File('test/fixtures/welib_book_page.html').readAsStringSync();

void main() {
  group('parseBookPage on a live-captured welib page', () {
    late BookInfoData? data;

    setUpAll(() {
      data = WelibProvider().parseBookPage(
        _fixture(),
        'https://welib.org',
        'https://welib.org/md5/$_md5',
      );
    });

    test('reads the title from the page heading', () {
      expect(data, isNotNull);
      expect(data!.title, 'The Score');
    });

    test('reads format and size from the page title tag', () {
      // <title>The Score ( PDF, 1.7 MB ) - WeLib</title>
      expect(data!.format, 'pdf');
      expect(data!.info, contains('PDF'));
      expect(data!.info, contains('1.7 MB'));
    });

    test('keeps the md5 as the book id', () {
      expect(data!.md5, _md5);
      expect(data!.link, 'https://welib.org/md5/$_md5');
    });

    test('points the download at the public-server page', () {
      expect(data!.mirror, 'https://welib.org/slow_download/$_md5/0/0');
      expect(data!.isFastDownload, isFalse);
    });

    test('carries a cover URL', () {
      expect(data!.thumbnail, isNotNull);
      expect(data!.thumbnail, startsWith('https://'));
    });

    test('rejects a page with no book heading', () {
      final parsed = WelibProvider().parseBookPage(
          '<html><body><p>nothing</p></body></html>',
          'https://welib.org',
          'https://welib.org/md5/$_md5');
      expect(parsed, isNull);
    });
  });

  group('parseResults', () {
    test('reads language and format from the metadata row instead of author', () {
      final books = WelibProvider().parseResults(_fixture(), 'https://welib.org');
      expect(books.first.info, 'English, PDF, 2015, 1.7 MB');
      expect(books.first.info, isNot(contains('Elle Kennedy')));
    });

    test('reads the book cards welib renders (related books)', () {
      final books = WelibProvider().parseResults(_fixture(), 'https://welib.org');

      // The captured page carries a full "related books" grid built from
      // the same book-card element the search page uses.
      expect(books.length, greaterThanOrEqualTo(10));
      for (final book in books) {
        expect(book.title, isNotEmpty);
        expect(book.link, startsWith('https://welib.org/md5/'));
        expect(book.md5, matches(RegExp(r'^[0-9a-f]{32}$')));
      }
    });

    test('every card has a distinct md5', () {
      final books = WelibProvider().parseResults(_fixture(), 'https://welib.org');
      final ids = books.map((b) => b.md5).toSet();
      expect(ids.length, books.length,
          reason: 'a book id must identify one book');
    });

    test('ignores markup with no book cards', () {
      final books = WelibProvider()
          .parseResults('<html><body><p>empty</p></body></html>', 'https://welib.org');
      expect(books, isEmpty);
    });
  });

  group('bookInfo', () {
    test('fetches a real book page from a mirror and parses it', () async {
      final content = _fixture();
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) {
        request.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType.html
          ..write(content)
          ..close();
      });

      try {
        final provider = WelibProvider(
          mirrors: ['http://127.0.0.1:${server.port}'],
        );
        final data = await provider.bookInfo('https://welib.org/md5/$_md5');

        expect(data, isNotNull);
        expect(data!.title, 'The Score');
        expect(data.format, 'pdf');
      } finally {
        await server.close();
      }
    });

    test('returns null for a URL that carries no md5', () async {
      final data = await WelibProvider(mirrors: const [])
          .bookInfo('https://welib.org/search?q=flutter');
      expect(data, isNull);
    });

    test('returns null when the mirror serves a non-200', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) {
        request.response.statusCode = HttpStatus.forbidden;
        request.response.close();
      });

      try {
        final provider = WelibProvider(
          mirrors: ['http://127.0.0.1:${server.port}'],
        );
        expect(await provider.bookInfo('https://welib.org/md5/$_md5'), isNull);
      } finally {
        await server.close();
      }
    });
  });

  group('search', () {
    test('does not attempt a search without an attemptable mirror', () async {
      var requests = 0;
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) {
        requests++;
        request.response.statusCode = HttpStatus.ok;
        request.response.close();
      });

      try {
        // What the provider gets when open-slum.org reports welib.org DOWN.
        final provider = WelibProvider(mirrors: const []);
        final books = await provider.search(const SearchQuery(text: 'flutter'));

        expect(books, isEmpty);
        expect(requests, 0);
      } finally {
        await server.close();
      }
    });

    test('parses results when the mirror answers without a challenge',
        () async {
      final content = _fixture();
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) {
        request.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType.html
          ..write(content)
          ..close();
      });

      try {
        final provider = WelibProvider(
          mirrors: ['http://127.0.0.1:${server.port}'],
        );
        final books = await provider.search(const SearchQuery(text: 'the score'));

        expect(books, isNotEmpty);
      } finally {
        await server.close();
      }
    });

    test('reports no results when the mirror is Cloudflare-gated', () async {
      // welib.org really does answer /search with a Cloudflare
      // interstitial; without a webview solver (this test VM) the
      // provider must report nothing rather than throw or hang.
      // guiEnabled=false keeps the solver from opening a real window in
      // a headless test run.
      WebviewChallengeSolver.guiEnabled = false;
      WebviewChallengeSolver.overrideIsMobile = false;
      WebviewChallengeSolver.headlessEnabled = false;
      addTearDown(() {
        WebviewChallengeSolver.guiEnabled = true;
        WebviewChallengeSolver.overrideIsMobile = null;
        WebviewChallengeSolver.headlessEnabled = true;
      });
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) {
        request.response
          ..statusCode = HttpStatus.forbidden
          ..headers.set('cf-mitigated', 'challenge')
          ..headers.contentType = ContentType.html
          ..write('<!DOCTYPE html><html><head><title>Just a moment...'
              '</title></head><body>challenges.cloudflare.com</body></html>')
          ..close();
      });

      try {
        final provider = WelibProvider(
          dio: Dio(BaseOptions(
            connectTimeout: const Duration(seconds: 5),
            receiveTimeout: const Duration(seconds: 5),
          )),
          mirrors: ['http://127.0.0.1:${server.port}'],
        );
        final books = await provider.search(const SearchQuery(text: 'flutter'));
        expect(books, isEmpty);
      } finally {
        await server.close();
      }
    });
  });

  // Production paths for the Cloudflare-gated mirrors: the real
  // interstitial (captured live from welib.org against Dart's HTTP
  // fingerprint) must be classified, routed into the webview solver,
  // its captured page parsed, and the solve cached for follow-ups - or
  // honestly reported when no solver exists.
  group('Cloudflare solver flow (real captured interstitial)', () {
    final interstitial =
        File('test/fixtures/cloudflare_interstitial.html').readAsStringSync();
    final bookPage = _fixture();

    setUp(() {
      ChallengeHtmlCache.clear();
    });

    /// Serves the real Cloudflare 403 interstitial for search, and after
    /// [solvedRequests] requests the real page (as a solvable browser
    /// would see it afterwards).
    Future<(HttpServer, List<String>)> challengeServer(
        {int solvedAfter = -1}) async {
      final hits = <String>[];
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        hits.add(request.uri.toString());
        request.response
          ..statusCode =
              hits.length <= solvedAfter ? HttpStatus.forbidden : HttpStatus.ok
          ..headers.set('cf-mitigated', 'challenge')
          ..headers.contentType = ContentType.html
          ..write(hits.length <= solvedAfter ? interstitial : bookPage);
        await request.response.close();
      });
      return (server, hits);
    }

    Dio smallDio() => Dio(BaseOptions(
          connectTimeout: const Duration(seconds: 5),
          receiveTimeout: const Duration(seconds: 5),
        ));

    /// Puts the solver into the test-VM branch where the registered
    /// visible-solver hook plays the webview (no real window opens).
    void enableSolverSeam(Future<String?> Function(String url) hook) {
      WebviewChallengeSolver.guiEnabled = false;
      WebviewChallengeSolver.overrideIsMobile = true;
      WebviewChallengeSolver.headlessEnabled = false;
      WebviewChallengeSolver.visibleSolverFallback = hook;
      addTearDown(() {
        WebviewChallengeSolver.guiEnabled = true;
        WebviewChallengeSolver.overrideIsMobile = null;
        WebviewChallengeSolver.headlessEnabled = true;
        WebviewChallengeSolver.visibleSolverFallback = null;
      });
    }

    test('routes the header signal into the solver and parses its capture',
        () async {
      final (server, hits) = await challengeServer(solvedAfter: 999);
      var solvedUrls = <String>[];
      enableSolverSeam((url) async {
        solvedUrls.add(url);
        return bookPage;
      });

      try {
        final provider =
            WelibProvider(dio: smallDio(), mirrors: ['http://127.0.0.1:${server.port}']);
        final books =
            await provider.search(const SearchQuery(text: 'flutter'));

        expect(books, isNotEmpty,
            reason: 'the solved page must parse into real book cards');
        expect(books.first.md5, hasLength(32));
        expect(solvedUrls,
            ['http://127.0.0.1:${server.port}/search?q=flutter'],
            reason: 'the solver must be asked for the exact blocked URL');
        // The interstitial page is fetched once (then solved, not
        // re-fetched); the provider must never loop on it.
        expect(hits.length, 1);
      } finally {
        await server.close();
      }
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('a solved page is reused from the cache on the next search',
        () async {
      final (server, hits) = await challengeServer(solvedAfter: 999);
      enableSolverSeam((url) async => bookPage);

      try {
        final provider =
            WelibProvider(dio: smallDio(), mirrors: ['http://127.0.0.1:${server.port}']);
        await provider.search(const SearchQuery(text: 'flutter'));
        expect(hits.length, 1);

        // The "Try Again" / paginate flow: no new challenge, no new
        // request - the captured page is the answer.
        final books = await provider.search(const SearchQuery(text: 'flutter'));
        expect(books, isNotEmpty,
            reason: 'the cached capture must still parse');
        expect(hits.length, 1,
            reason: 'the cached page must be served without requests');
      } finally {
        await server.close();
      }
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('without a solver it reports nothing and never invents results',
        () async {
      final (server, hits) = await challengeServer(solvedAfter: 999);
      // The production-VM shape (this test VM has no webview binary):
      // guiEnabled=false, no visible hook registered.
      WebviewChallengeSolver.guiEnabled = false;
      WebviewChallengeSolver.overrideIsMobile = false;
      WebviewChallengeSolver.headlessEnabled = false;
      addTearDown(() {
        WebviewChallengeSolver.guiEnabled = true;
        WebviewChallengeSolver.overrideIsMobile = null;
        WebviewChallengeSolver.headlessEnabled = true;
      });

      try {
        final provider =
            WelibProvider(dio: smallDio(), mirrors: ['http://127.0.0.1:${server.port}']);
        final books =
            await provider.search(const SearchQuery(text: 'flutter'));

        expect(books, isEmpty, reason: 'no solver means no results, no throw');
        expect(hits.length, 1,
            reason: 'the blocked URL must not be retried in a loop');
      } finally {
        await server.close();
      }
    });

    test('a 403 without challenge signals is not mistaken for one',
        () async {
      // The real shape AA's download mirrors serve (captured live):
      // a plain 403 and normal text, no header, no interstitial.
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      var solverCalls = 0;
      server.listen((request) async {
        request.response
          ..statusCode = HttpStatus.forbidden
          ..headers.contentType = ContentType.html
          ..write("<html><body>Link expired or invalid. "
              "Get a new link to continue. <a href='/login'>Login</a></body></html>");
        await request.response.close();
      });
      WebviewChallengeSolver.guiEnabled = false;
      WebviewChallengeSolver.overrideIsMobile = true;
      WebviewChallengeSolver.visibleSolverFallback = (url) async {
        solverCalls++;
        return bookPage;
      };
      addTearDown(() {
        WebviewChallengeSolver.guiEnabled = true;
        WebviewChallengeSolver.overrideIsMobile = null;
        WebviewChallengeSolver.visibleSolverFallback = null;
      });

      try {
        final provider =
            WelibProvider(dio: smallDio(), mirrors: ['http://127.0.0.1:${server.port}']);
        final books =
            await provider.search(const SearchQuery(text: 'flutter'));

        expect(books, isEmpty,
            reason: 'a mirror that refuses is not searched further on');
        expect(solverCalls, 0,
            reason: 'no interstitial means no solver run');
      } finally {
        await server.close();
        ChallengeHtmlCache.clear();
      }
    });

    test('a normal page mentioning Cloudflare is still searched fine',
        () async {
      // Search pages can embed a Cloudflare Turnstile widget (its
      // marker lives in the DOM); that is 200 content, not a block.
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      var solverCalls = 0;
      server.listen((request) async {
        request.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType.html
          ..write('<!DOCTYPE html><html><head>'
              '<title>Anything | WeLib</title>'
              '<script src="https://challenges.cloudflare.com/turnstile/v0/api.js"></script>'
              '</head><body>${_fixture()}</body></html>');
        await request.response.close();
      });
      WebviewChallengeSolver.guiEnabled = false;
      WebviewChallengeSolver.overrideIsMobile = true;
      WebviewChallengeSolver.visibleSolverFallback = (url) async {
        solverCalls++;
        return null;
      };
      addTearDown(() {
        WebviewChallengeSolver.guiEnabled = true;
        WebviewChallengeSolver.overrideIsMobile = null;
        WebviewChallengeSolver.visibleSolverFallback = null;
      });

      try {
        final provider =
            WelibProvider(dio: smallDio(), mirrors: ['http://127.0.0.1:${server.port}']);
        final books =
            await provider.search(const SearchQuery(text: 'flutter'));

        expect(books, isNotEmpty,
            reason: 'a 200 page with a Turnstile widget is content');
        expect(solverCalls, 0,
            reason: 'no interstitial means no solver run');
      } finally {
        await server.close();
        ChallengeHtmlCache.clear();
      }
    });
  });

  group('resolveDownload', () {
    /// The download block captured live from welib.org's public-server
    /// page for `The Score`: the partner file anchor sits under a
    /// `<div class="mb-4 text-xl font-bold">` (Anna's Archive puts that
    /// class on a `<p>`), next to the in-app-browser warning template.
    /// There is no login gate on the markup - the file link is there.
    final partnerPage = File('test/fixtures/welib_download_page.html')
        .readAsStringSync();

    /// Serves one page and returns the provider pointed at it.
    Future<(HttpServer, WelibProvider)> pageServer(String html,
        {int status = 200}) async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        request.response
          ..statusCode = status
          ..headers.contentType = ContentType.html
          ..write(html);
        await request.response.close();
      });
      ChallengeHtmlCache.clear();
      return (server, WelibProvider());
    }

    test('resolves the partner file link on the real page shape', () async {
      final (server, provider) = await pageServer(partnerPage);
      try {
        final result = await provider.resolveDownload(
            'http://127.0.0.1:${server.port}/slow_download/$_md5/0/0');
        expect(
            result.url,
            'https://x-cdn-x.com/hs7/zlib2/pilimi-zlib2-19250000-19329999/'
            '19263581~/1792244044.6TiJ-hGRb5cS6PXg6l6x1A/$_md5/'
            'The%20Score%20--%20Elle%20Kennedy%20--%20%28%20WeLib.org%20%29.pdf');
        expect(result.refusal, isNull);
      } finally {
        await server.close();
      }
    });

    test('reports the rate limit instead of a missing link', () async {
      // welib.org throttles anonymous clients: a few downloads in a row
      // and it answers 429. That is temporary and says so.
      final (server, provider) =
          await pageServer('<html>Too Many Requests</html>', status: 429);
      try {
        final result = await provider.resolveDownload(
            'http://127.0.0.1:${server.port}/slow_download/$_md5/0/0');
        expect(result.url, isNull);
        expect(result.refusal, contains('rate-limiting'));
      } finally {
        await server.close();
      }
    });

    test('reports a bot check it could not clear', () async {
      // Cloudflare held the client (no solver, or its window closed):
      // the page never arrived, and that is not "this book has no link".
      WebviewChallengeSolver.guiEnabled = false;
      WebviewChallengeSolver.overrideIsMobile = false;
      WebviewChallengeSolver.headlessEnabled = false;
      addTearDown(() {
        WebviewChallengeSolver.guiEnabled = true;
        WebviewChallengeSolver.overrideIsMobile = null;
        WebviewChallengeSolver.headlessEnabled = true;
      });

      final (server, provider) = await pageServer(
          '<!DOCTYPE html><html><head><title>Just a moment...'
          '</title></head><body>challenges.cloudflare.com</body></html>',
          status: 403);
      try {
        final result = await provider.resolveDownload(
            'http://127.0.0.1:${server.port}/slow_download/$_md5/0/0');
        expect(result.url, isNull);
        expect(result.refusal, contains('bot check'));
      } finally {
        await server.close();
      }
    });

    test('never resolves another book\'s download link', () async {
      // A related-books grid carries /auto_download/<other md5> links;
      // picking one would download the wrong book.
      final (server, provider) =
          await pageServer('<html><body><a href="/auto_download/'
              '2b3cf90c84658f55bf8d9abe8532e33e/0/0">Other</a></body></html>');
      try {
        final result = await provider.resolveDownload(
            'http://127.0.0.1:${server.port}/slow_download/$_md5/0/0');
        expect(result.url, isNull,
            reason: 'another book\'s link must not be used');
      } finally {
        await server.close();
      }
    });

    test('resolves this book\'s own auto_download link', () async {
      final (server, provider) = await pageServer(
          '<html><body><a href="/auto_download/$_md5/0/0">Download</a>'
          '</body></html>');
      try {
        final result = await provider.resolveDownload(
            'http://127.0.0.1:${server.port}/slow_download/$_md5/0/0');
        expect(result.url,
            'http://127.0.0.1:${server.port}/auto_download/$_md5/0/0');
      } finally {
        await server.close();
      }
    });

    test('resolves a bare direct file link', () async {
      final (server, provider) = await pageServer(
          '<html><body><a href="https://cdn.example/x/book.epub">Get</a>'
          '</body></html>');
      try {
        final result = await provider.resolveDownload(
            'http://127.0.0.1:${server.port}/slow_download/$_md5/0/0');
        expect(result.url, 'https://cdn.example/x/book.epub');
      } finally {
        await server.close();
      }
    });
  });

  group('isWelibUrl', () {
    // The book page's download button routes on this predicate; it must
    // keep agreeing with the provider that parses the page.
    test('accepts the public-server page welib results carry', () {
      expect(isWelibUrl('https://welib.org/slow_download/$_md5/0/0'), isTrue);
      expect(isWelibUrl('https://welib.org/md5/$_md5'), isTrue);
    });

    test('rejects the other sources\' download pages', () {
      // Anna's Archive serves the same /slow_download/ path; only the
      // host decides which parser runs.
      expect(isWelibUrl('https://annas-archive.gl/slow_download/$_md5'), isFalse);
      expect(isWelibUrl('https://z-lib.gd/dl/abc'), isFalse);
      expect(isWelibUrl('https://libgen.la/get.php?md5=$_md5'), isFalse);
    });

    test('rejects missing or unparseable values', () {
      expect(isWelibUrl(null), isFalse);
      expect(isWelibUrl(''), isFalse);
      expect(isWelibUrl('not a url'), isFalse);
    });
  });

}
