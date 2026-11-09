// Unit tests for the challenge HTML cache and the challenge-page and
// loadStop-race heuristics of the webview solver. No real webview is
// opened: guiEnabled stays off and the visible fallback is a fake.

// Dart imports:
import 'dart:async';
import 'dart:io';

// Flutter imports:
import 'package:flutter_test/flutter_test.dart';

// Package imports:
import 'package:desktop_webview_window/desktop_webview_window.dart'
    as desktop_webview;

// Project imports:
import 'package:openlib/services/challenge_html_cache.dart';
import 'package:openlib/services/webview_challenge_solver.dart';

/// A page long enough for the solver to accept it.
final _usableHtml = '<html>${'results ' * 200}</html>';

/// A Webview that answers the solver's polls from mutable fields.
class _FakeWebview implements desktop_webview.Webview {
  String title = '';
  String body = '';
  String readyState = 'complete';
  String html = '';
  void Function()? onTitleRead;

  final List<bool> visibility = [];
  bool foreground = false;
  bool closed = false;
  final Completer<void> _closeCompleter = Completer<void>();

  @override
  Future<void> get onClose => _closeCompleter.future;

  @override
  Future<String?> evaluateJavaScript(String javaScript) async {
    if (javaScript == 'document.title') {
      onTitleRead?.call();
      return title;
    }
    if (javaScript.contains('document.body')) return body;
    if (javaScript == 'document.readyState') return readyState;
    if (javaScript.contains('outerHTML')) return html;
    return null;
  }

  @override
  Future<void> setWebviewWindowVisibility(bool visible) async {
    visibility.add(visible);
  }

  @override
  Future<void> bringToForeground({bool maximized = false}) async {
    foreground = true;
  }

  @override
  void close() {
    closed = true;
    if (!_closeCompleter.isCompleted) _closeCompleter.complete();
  }

  @override
  void launch(String url, {bool triggerOnUrlRequestEvent = true}) {}

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

void main() {
  group('ChallengeHtmlCache', () {
    setUp(() {
      ChallengeHtmlCache.clear();
    });

    test('stores and retrieves HTML by URL', () {
      ChallengeHtmlCache.store(
          'https://annas-archive.pk/search?q=test', '<html>results</html>');

      expect(ChallengeHtmlCache.get('https://annas-archive.pk/search?q=test'),
          equals('<html>results</html>'));
      expect(ChallengeHtmlCache.has('https://annas-archive.pk/search?q=test'),
          isTrue);
    });

    test('returns null for uncached URLs', () {
      ChallengeHtmlCache.store('https://annas-archive.pk/search?q=a', 'x');

      expect(ChallengeHtmlCache.get('https://annas-archive.pk/search?q=b'),
          isNull);
      expect(ChallengeHtmlCache.has('https://annas-archive.pk/search?q=b'),
          isFalse);
    });

    test('rejects empty keys and values', () {
      ChallengeHtmlCache.store('', '<html></html>');
      ChallengeHtmlCache.store('https://a', '');

      expect(ChallengeHtmlCache.get(''), isNull);
      expect(ChallengeHtmlCache.get('https://a'), isNull);
    });

    test('overwrites previous entries for the same URL', () {
      ChallengeHtmlCache.store('https://a', 'first');
      ChallengeHtmlCache.store('https://a', 'second');

      expect(ChallengeHtmlCache.get('https://a'), equals('second'));
    });

    test('clear removes all entries', () {
      ChallengeHtmlCache.store('https://a', 'x');
      ChallengeHtmlCache.clear();

      expect(ChallengeHtmlCache.has('https://a'), isFalse);
    });
  });

  group('WebviewChallengeSolver.isChallengePage', () {
    test('detects DDoS-Guard challenge by title', () {
      expect(
          WebviewChallengeSolver.isChallengePage(
              title: 'DDoS-Guard', bodySnippet: ''),
          isTrue);
    });

    test('detects DDoS-Guard challenge by body markers', () {
      expect(
          WebviewChallengeSolver.isChallengePage(
              title: '',
              bodySnippet: '<script src="https://check.ddos-guard.net/x">'),
          isTrue);
    });

    test('detects Cloudflare challenge', () {
      expect(
          WebviewChallengeSolver.isChallengePage(
              title: 'Just a moment...', bodySnippet: 'cf-turnstile'),
          isTrue);
    });

    test('does not flag real search results', () {
      expect(
          WebviewChallengeSolver.isChallengePage(
              title: 'harry potter - Search - Anna’s Archive',
              bodySnippet: '<div class="js-aarecord-list-outer">books</div>'),
          isFalse);
    });

    test('does not flag a book detail page', () {
      expect(
          WebviewChallengeSolver.isChallengePage(
              title: 'Villa Coco: A Novel - Anna’s Archive',
              bodySnippet: '<div class="main-inner">book details</div>'),
          isFalse);
    });
  });

  // Regression from an Android field log: the challenge had been
  // cleared (title = real page) but the page was not done loading, so
  // onLoadStop completed the solve with null and killed the poll loop.
  // A loadStop may only complete with real captured HTML in hand.
  group('loadStop race regression', () {
    test('real title but empty HTML must not complete', () {
      expect(
          WebviewChallengeSolver.shouldCompleteFromLoadStop(
              'harry potter - Search - Anna’s Archive', null),
          isFalse);
      expect(
          WebviewChallengeSolver.shouldCompleteFromLoadStop(
              'harry potter - Search - Anna’s Archive', ''),
          isFalse);
    });

    test('challenge title with HTML must not complete', () {
      expect(
          WebviewChallengeSolver.shouldCompleteFromLoadStop(
              'DDoS-Guard', '<html>challenge page</html>'),
          isFalse);
    });

    test('real title with captured HTML completes', () {
      expect(
          WebviewChallengeSolver.shouldCompleteFromLoadStop(
              'harry potter - Search - Anna’s Archive', _usableHtml),
          isTrue);
    });

    test('a redirect stub is not a solved page', () {
      expect(
          WebviewChallengeSolver.shouldCompleteFromLoadStop(
              'Redirecting...', '<html><body>Redirecting</body></html>'),
          isFalse);
    });
  });

  group('WebviewChallengeSolver.isUsableHtml', () {
    test('requires the length the callers parse', () {
      expect(WebviewChallengeSolver.isUsableHtml(null), isFalse);
      expect(WebviewChallengeSolver.isUsableHtml(''), isFalse);
      expect(WebviewChallengeSolver.isUsableHtml('<html>short</html>'),
          isFalse);
      expect(WebviewChallengeSolver.isUsableHtml(_usableHtml), isTrue);
    });
  });

  group('WebviewChallengeSolver.looksLikeLoadError', () {
    test('recognizes a DNS error page', () {
      expect(
          WebviewChallengeSolver.looksLikeLoadError(
              "This site can't be reached", 'ERR_NAME_NOT_RESOLVED'),
          isTrue);
      expect(
          WebviewChallengeSolver.looksLikeLoadError(
              '', 'dns_probe_finished_nxdomain'),
          isTrue);
    });

    test('does not flag a challenge or a real page', () {
      expect(
          WebviewChallengeSolver.looksLikeLoadError(
              'DDoS-Guard', 'Checking your browser'),
          isFalse);
      expect(
          WebviewChallengeSolver.looksLikeLoadError(
              'harry potter - Search - Anna’s Archive', 'results'),
          isFalse);
    });
  });

  group('WebviewChallengeSolver.hasInteractiveChallengeMarkers', () {
    test('a silent DDoS-Guard check has nothing to click', () {
      expect(
          WebviewChallengeSolver.hasInteractiveChallengeMarkers(
              '<div class="ddg-l10n-title">Checking your browser</div>'),
          isFalse);
    });

    test('a Turnstile iframe or checkbox is interactive', () {
      expect(
          WebviewChallengeSolver.hasInteractiveChallengeMarkers(
              '<iframe src="https://challenges.cloudflare.com/x"></iframe>'),
          isTrue);
      expect(
          WebviewChallengeSolver.hasInteractiveChallengeMarkers(
              '<input type="checkbox" id="challenge">'),
          isTrue);
    });
  });

  group('desktop solver', () {
    setUp(() {
      ChallengeHtmlCache.clear();
      WebviewChallengeSolver.guiEnabled = true;
      WebviewChallengeSolver.overrideIsMobile = false;
      WebviewChallengeSolver.closeDesktopWindow = true;
    });
    tearDown(() {
      WebviewChallengeSolver.guiEnabled = true;
      WebviewChallengeSolver.overrideIsMobile = null;
      WebviewChallengeSolver.closeDesktopWindow = !Platform.isLinux;
      WebviewChallengeSolver.desktopWindowFactory = null;
    });

    test('a blank window gives up instead of polling to the deadline',
        () async {
      final fake = _FakeWebview();
      final result = await WebviewChallengeSolver.solveDesktopWebview(
        fake,
        timeout: const Duration(seconds: 2),
        pollInterval: const Duration(milliseconds: 10),
        blankTimeout: const Duration(milliseconds: 50),
      );

      expect(result, isNull);
    });

    test('a redirect stub is never reported as solved', () async {
      final fake = _FakeWebview()
        ..title = 'Redirecting...'
        ..body = '<html>redirect</html>'
        ..html = '<html>redirect</html>';

      final result = await WebviewChallengeSolver.solveDesktopWebview(
        fake,
        timeout: const Duration(milliseconds: 120),
        pollInterval: const Duration(milliseconds: 10),
      );

      expect(result, isNull);
    });

    test('a page that stays too short gives up before the deadline',
        () async {
      final fake = _FakeWebview()
        ..title = 'Redirecting...'
        ..body = '<html>redirect</html>'
        ..html = '<html>redirect</html>';
      final stopwatch = Stopwatch()..start();

      final result = await WebviewChallengeSolver.solveDesktopWebview(
        fake,
        timeout: const Duration(seconds: 5),
        pollInterval: const Duration(milliseconds: 10),
        blankTimeout: const Duration(milliseconds: 50),
      );
      stopwatch.stop();

      expect(result, isNull);
      expect(stopwatch.elapsed, lessThan(const Duration(seconds: 2)),
          reason: 'a short page must not poll to the full timeout');
    });

    test('a browser error page is a failed load, not a challenge', () async {
      final fake = _FakeWebview()
        ..title = "This site can't be reached"
        ..body = '<div>ERR_NAME_NOT_RESOLVED</div>'
        ..html = '<html>error</html>';

      final result = await WebviewChallengeSolver.solveDesktopWebview(
        fake,
        timeout: const Duration(seconds: 2),
        pollInterval: const Duration(milliseconds: 10),
      );

      expect(result, isNull);
    });

    test('a real page is captured', () async {
      final fake = _FakeWebview()
        ..title = 'harry potter - Search - Anna’s Archive'
        ..body = '<div class="js-aarecord-list-outer">books</div>'
        ..html = _usableHtml;

      final result = await WebviewChallengeSolver.solveDesktopWebview(
        fake,
        timeout: const Duration(seconds: 2),
        pollInterval: const Duration(milliseconds: 10),
      );

      expect(result, _usableHtml);
    });

    test('a silent challenge that passes is captured', () async {
      final fake = _FakeWebview()
        ..title = 'DDoS-Guard'
        ..body = '<div class="ddg-l10n-title">Checking your browser</div>'
        ..html = '<html>challenge</html>';
      var polls = 0;
      fake.onTitleRead = () {
        polls++;
        if (polls >= 2) {
          fake
            ..title = 'harry potter - Search - Anna’s Archive'
            ..body = '<div class="js-aarecord-list-outer">books</div>'
            ..html = _usableHtml;
        }
      };

      final result = await WebviewChallengeSolver.solveDesktopWebview(
        fake,
        timeout: const Duration(seconds: 2),
        pollInterval: const Duration(milliseconds: 10),
      );

      expect(result, _usableHtml);
      expect(fake.visibility, isNot(contains(true)),
          reason: 'a silent JS check needs no visible window');
    });

    test('an interactive challenge shows the window', () async {
      final fake = _FakeWebview()
        ..title = 'Just a moment...'
        ..body = '<iframe src="https://challenges.cloudflare.com/x"></iframe>'
        ..html = '<html>challenge</html>';

      final result = await WebviewChallengeSolver.solveDesktopWebview(
        fake,
        timeout: const Duration(milliseconds: 120),
        pollInterval: const Duration(milliseconds: 10),
      );

      expect(result, isNull);
      expect(fake.visibility, contains(true));
      expect(fake.foreground, isTrue);
    });

    test('the window is closed after a solve', () async {
      final fake = _FakeWebview()
        ..title = 'harry potter - Search - Anna’s Archive'
        ..body = '<div class="js-aarecord-list-outer">books</div>'
        ..html = _usableHtml;
      WebviewChallengeSolver.desktopWindowFactory = (_) async => fake;

      final result = await WebviewChallengeSolver.fetchHtmlAfterChallenge(
        'https://annas-archive.pk/close-test',
        timeout: const Duration(seconds: 2),
      );

      expect(result, _usableHtml);
      expect(fake.closed, isTrue,
          reason: 'a stale Verifying access window must not stay behind');
      expect(fake.visibility.first, isFalse,
          reason: 'the window starts hidden for a silent JS check');
    });
  });

  // A failed headless mobile solve must consult the registered
  // visible-solver hook and cache its result.
  group('visible solver fallback', () {
    test('used and cached when the headless solve returns nothing', () async {
      ChallengeHtmlCache.clear();
      var askedFor = '';
      WebviewChallengeSolver.guiEnabled = false; // no real webview
      WebviewChallengeSolver.overrideIsMobile = true;
      WebviewChallengeSolver.visibleSolverFallback = (url) async {
        askedFor = url;
        return _usableHtml;
      };
      addTearDown(() {
        WebviewChallengeSolver.guiEnabled = true;
        WebviewChallengeSolver.overrideIsMobile = null;
        WebviewChallengeSolver.visibleSolverFallback = null;
      });

      const url = 'https://annas-archive.gl/search?q=race';
      final html = await WebviewChallengeSolver.fetchHtmlAfterChallenge(url);

      expect(askedFor, url);
      expect(html, _usableHtml);
      expect(ChallengeHtmlCache.get(url), _usableHtml);
    });

    test('returns null without caching when the user backs out', () async {
      WebviewChallengeSolver.guiEnabled = false;
      WebviewChallengeSolver.overrideIsMobile = true;
      WebviewChallengeSolver.visibleSolverFallback = (url) async => null;
      addTearDown(() {
        WebviewChallengeSolver.guiEnabled = true;
        WebviewChallengeSolver.overrideIsMobile = null;
        WebviewChallengeSolver.visibleSolverFallback = null;
      });

      final result = await WebviewChallengeSolver.fetchHtmlAfterChallenge(
          'https://annas-archive.pk/backout');

      expect(result, isNull);
      expect(
          ChallengeHtmlCache.get('https://annas-archive.pk/backout'), isNull);
    });

    test('a short visible-fallback page is not cached or returned', () async {
      ChallengeHtmlCache.clear();
      WebviewChallengeSolver.guiEnabled = false;
      WebviewChallengeSolver.overrideIsMobile = true;
      WebviewChallengeSolver.visibleSolverFallback =
          (url) async => '<html>short</html>';
      addTearDown(() {
        WebviewChallengeSolver.guiEnabled = true;
        WebviewChallengeSolver.overrideIsMobile = null;
        WebviewChallengeSolver.visibleSolverFallback = null;
      });

      const url = 'https://annas-archive.pk/short';
      final result = await WebviewChallengeSolver.fetchHtmlAfterChallenge(url);

      expect(result, isNull);
      expect(ChallengeHtmlCache.get(url), isNull,
          reason: 'a page the callers discard must not be cached as solved');
    });

    test('desktop solve does not consult the fallback', () async {
      var fallbackCalls = 0;
      WebviewChallengeSolver.guiEnabled = false;
      WebviewChallengeSolver.overrideIsMobile = false;
      WebviewChallengeSolver.visibleSolverFallback = (url) async {
        fallbackCalls++;
        return '<html>should-not-happen</html>';
      };
      addTearDown(() {
        WebviewChallengeSolver.guiEnabled = true;
        WebviewChallengeSolver.overrideIsMobile = null;
        WebviewChallengeSolver.visibleSolverFallback = null;
      });

      final result = await WebviewChallengeSolver.fetchHtmlAfterChallenge(
          'https://annas-archive.pk/slow');

      expect(result, isNull);
      expect(fallbackCalls, 0);
    });

    // The settings toggle: background verification off means no headless
    // attempt at all - the visible window runs straight away.
    test('headless disabled skips the headless attempt and goes visible',
        () async {
      var fallbackCalls = 0;
      WebviewChallengeSolver.guiEnabled = false;
      WebviewChallengeSolver.headlessEnabled = false;
      WebviewChallengeSolver.overrideIsMobile = true;
      WebviewChallengeSolver.visibleSolverFallback = (url) async {
        fallbackCalls++;
        return _usableHtml;
      };
      addTearDown(() {
        WebviewChallengeSolver.guiEnabled = true;
        WebviewChallengeSolver.headlessEnabled = true;
        WebviewChallengeSolver.overrideIsMobile = null;
        WebviewChallengeSolver.visibleSolverFallback = null;
      });

      final result = await WebviewChallengeSolver.fetchHtmlAfterChallenge(
          'https://annas-archive.pk/toggle');

      expect(fallbackCalls, 1);
      expect(result, _usableHtml);
    });
  });
}
