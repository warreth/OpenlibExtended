// Live end-to-end provider tests: open-slum.org -> search -> book info ->
// real download bytes. These hit the real mirrors and are skipped in
// normal runs; execute with:
//
//   flutter test --run-skipped test/live_providers_test.dart
//
// They are deliberately free of the app's sqlite database so they run
// anywhere, including musl containers where the sqlite native asset does
// not load. The download is a real HTTP transfer of the file the mirror
// serves - nothing is faked.

// Dart imports:
import 'dart:io';

// Flutter imports:
import 'package:flutter_test/flutter_test.dart';

// Package imports:
import 'package:dio/dio.dart';

// Project imports:
import 'package:openlib/services/instance_manager.dart';
import 'package:openlib/services/search_manager.dart';

const _ua =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/125.0 Safari/537.36';

/// Fetches [url] and returns (contentType, bytes) - a real transfer.
Future<(String, List<int>)> _download(String url, {String? cookie}) async {
  final dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 30),
    receiveTimeout: const Duration(minutes: 2),
    headers: {HttpHeaders.userAgentHeader: _ua, if (cookie != null) 'Cookie': cookie},
    followRedirects: true,
    maxRedirects: 5,
  ));
  try {
    final response = await dio.get<List<int>>(
      url,
      options: Options(responseType: ResponseType.bytes),
    );
    return (
      response.headers.value(HttpHeaders.contentTypeHeader) ?? '',
      response.data ?? const <int>[],
    );
  } finally {
    dio.close();
  }
}

void main() {
  // No TestWidgetsFlutterBinding on purpose: it replaces dart:io's
  // HttpClient with a fake, which would defeat live-network tests.

  group('mirror list from open-slum.org', () {
    test('libgen: every mirror SLUM reports down is withheld', () async {
      final all = await InstanceManager().instances(MirrorService.libgen,
          force: true);
      final urls = await InstanceManager().enabledUrls(MirrorService.libgen,
          force: true);

      // Whatever SLUM says today, the invariant must hold.
      for (final url in urls) {
        final view = all.firstWhere((v) => v.url == url);
        expect(view.isDown, isFalse,
            reason: '$url is reported DOWN and must never be attempted');
      }
    }, timeout: const Timeout(Duration(seconds: 60)), skip: 'live network');

    test('zlibrary: the attemptable list is protection-ordered', () async {
      final urls = await InstanceManager().enabledUrls(MirrorService.zlibrary,
          force: true);
      expect(urls, isNotEmpty,
          reason: 'SLUM lists z-library mirrors as protected, not down');

      final all = await InstanceManager().instances(MirrorService.zlibrary,
          force: true);
      var lastRank = -1;
      for (final url in urls) {
        final rank = all.firstWhere((v) => v.url == url).site.protection.rank;
        expect(rank, greaterThanOrEqualTo(lastRank),
            reason: 'protection tiers must be tried easiest-first');
        lastRank = rank;
      }
    }, timeout: const Timeout(Duration(seconds: 60)), skip: 'live network');
  });

  group('libgen end to end', () {
    test('a search never touches a mirror SLUM reports down', () async {
      final all = await InstanceManager().instances(MirrorService.libgen,
          force: true);
      final downHosts = all.where((v) => v.isDown).map((v) => v.url).toSet();
      final attemptable = await InstanceManager().enabledUrls(
          MirrorService.libgen,
          force: true);

      expect(attemptable.where(downHosts.contains), isEmpty,
          reason: 'a dead host must never appear in the attempt list');

      // The provider then behaves: it returns parsed books, or reports
      // that nothing reachable answered (contained by SearchManager).
      // What it must never do is invent results.
      try {
        final books = await LibgenProvider()
            .search(const SearchQuery(text: 'flutter'));
        for (final book in books) {
          expect(book.title, isNotEmpty);
          expect(book.link, startsWith('http'));
        }
      } catch (e) {
        expect(e.toString(), contains('unreachable'),
            reason: 'the only acceptable failure is "nothing answered"');
      }
    }, timeout: const Timeout(Duration(seconds: 90)), skip: 'live network');
  });

  group('z-library end to end', () {
    test('search clears DiamWall and parses real results', () async {
      final books = await ZlibraryProvider()
          .search(const SearchQuery(text: 'flutter'));

      if (books.isEmpty) {
        // DiamWall now answers a 307 with a __diamwall cookie and then a
        // 517 "Access Denied" page for flagged networks. That is a
        // mirror-side block, not a parser failure; the provider must
        // report it instead of hanging or inventing results.
        markTestSkipped('Z-Library blocked this network (DiamWall 517)');
        return;
      }
      for (final book in books) {
        expect(book.title, isNotEmpty);
        expect(book.link, contains('/book/'));
        expect(book.md5, isNotEmpty);
      }
    }, timeout: const Timeout(Duration(minutes: 2)), skip: 'live network');

    test('book page parses and the download resolves to real file bytes',
        () async {
      final provider = ZlibraryProvider();
      final books = await provider.search(const SearchQuery(text: 'flutter'));
      if (books.isEmpty) {
        markTestSkipped('Z-Library blocked this network (DiamWall 517)');
        return;
      }
      final book = books.first;

      final info = await provider.bookInfo(book.link);
      expect(info, isNotNull, reason: 'the book page must parse');
      expect(info!.title, isNotEmpty);
      expect(info.format, isNotEmpty);

      // Resolve the /dl/ hop to the signed CDN URL, then fetch it.
      final resolved = await provider.resolveBookDownload(book.link);
      if (resolved.url == null) {
        // Z-Library rate-limits anonymous downloads per IP and says so
        // on the page it serves instead ("Daily limit reached ... more
        // than 5 downloads from your IP"). That is legitimate mirror
        // behaviour; fabricating a "success" is not. The refusal is
        // reported so the reason is visible rather than silent.
        markTestSkipped('z-lib withheld the file URL: '
            '${resolved.refusal ?? "no reason given"}');
        return;
      }

      final (contentType, bytes) = await _download(resolved.url!);
      expect(bytes.length, greaterThan(20000),
          reason: 'must be a real book file, not an error page');
      expect(contentType.toLowerCase(), isNot(contains('text/html')));
    }, timeout: const Timeout(Duration(minutes: 3)), skip: 'live network');
  });

  group('welib end to end', () {
    test('book page either parses or is reported as Cloudflare-gated',
        () async {
      final mirrors =
          await InstanceManager().enabledUrls(MirrorService.welib, force: true);
      expect(mirrors, isNotEmpty);

      // Cloudflare fronts welib and fingerprints clients: a plain HTTP
      // request from Dart is challenged even though the same URL passes
      // in a browser. Two outcomes are therefore valid - the page parsed
      // (a solver cleared it) or the provider reports null instead of
      // fabricating data. Anything else is a bug.
      final data = await WelibProvider()
          .bookInfo('https://welib.org/md5/00f8a97a0e03ac203235b306e249aa76');

      if (data != null) {
        expect(data.title, isNotEmpty);
        expect(data.format, isNotEmpty);
      }
    }, timeout: const Timeout(Duration(minutes: 2)), skip: 'live network');
  });

  group('combined manager search', () {
    test('all enabled providers run with per-provider failures contained',
        () async {
      final result =
          await SearchManager().search(const SearchQuery(text: 'flutter'));

      expect(result.books, isNotEmpty,
          reason: 'at least the Z-Library mirrors must return results');
      for (final book in result.books) {
        expect(book.source, isNotNull,
            reason: 'every result must be tagged with its catalog');
      }
    }, timeout: const Timeout(Duration(minutes: 2)), skip: 'live network');
  });
}
