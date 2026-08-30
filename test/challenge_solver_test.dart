import 'package:flutter_test/flutter_test.dart';
import 'package:openlib/services/challenge_html_cache.dart';
import 'package:openlib/services/webview_challenge_solver.dart';

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
      expect(
          ChallengeHtmlCache.has('https://annas-archive.pk/search?q=test'),
          isTrue);
    });

    test('returns null for uncached URLs', () {
      ChallengeHtmlCache.store(
          'https://annas-archive.pk/search?q=a', '<html></html>');

      expect(ChallengeHtmlCache.get('https://annas-archive.pk/search?q=b'),
          isNull);
      expect(ChallengeHtmlCache.has('https://annas-archive.pk/search?q=b'),
          isFalse);
    });

    test('rejects empty keys and values', () {
      ChallengeHtmlCache.store('', '<html></html>');
      ChallengeHtmlCache.store('https://example.com', '');

      expect(ChallengeHtmlCache.get(''), isNull);
      expect(ChallengeHtmlCache.get('https://example.com'), isNull);
    });

    test('overwrites previous entries for the same URL', () {
      ChallengeHtmlCache.store('https://example.com', 'old');
      ChallengeHtmlCache.store('https://example.com', 'new');

      expect(ChallengeHtmlCache.get('https://example.com'), equals('new'));
    });

    test('clear removes all entries', () {
      ChallengeHtmlCache.store('https://example.com/a', 'a');
      ChallengeHtmlCache.store('https://example.com/b', 'b');
      ChallengeHtmlCache.clear();

      expect(ChallengeHtmlCache.get('https://example.com/a'), isNull);
      expect(ChallengeHtmlCache.get('https://example.com/b'), isNull);
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
              bodySnippet:
                  '<script src="/.well-known/ddos-guard/js-challenge/index.js">'),
          isTrue);
      expect(
          WebviewChallengeSolver.isChallengePage(
              title: '', bodySnippet: 'https://check.ddos-guard.net/check.js'),
          isTrue);
    });

    test('detects Cloudflare challenge', () {
      expect(
          WebviewChallengeSolver.isChallengePage(
              title: 'Just a moment...', bodySnippet: ''),
          isTrue);
      expect(
          WebviewChallengeSolver.isChallengePage(
              title: 'Attention Required! | Cloudflare', bodySnippet: ''),
          isTrue);
    });

    test('does not flag real search results', () {
      // Title/body taken from a real captured results page.
      expect(
          WebviewChallengeSolver.isChallengePage(
              title: 'harry potter - Search - Anna’s Archive',
              bodySnippet:
                  '<div class="js-aarecord-list-outer">books</div>'),
          isFalse);
    });

    test('does not flag a book detail page', () {
      expect(
          WebviewChallengeSolver.isChallengePage(
              title: 'Villa Coco: A Novel - Anna’s Archive',
              bodySnippet:
                  '<div class="main-inner">book details</div>'),
          isFalse);
    });
  });
}
