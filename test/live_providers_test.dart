// Live end-to-end provider tests: search -> book info -> direct download.
// These hit the real libgen and Z-Library mirrors and are skipped in
// normal runs; execute with:
//   flutter test --run-skipped test/live_providers_test.dart

// Dart imports:
import 'dart:io';

// Flutter imports:
import 'package:flutter_test/flutter_test.dart';

// Package imports:
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

// Project imports:
import 'package:openlib/services/database.dart';
import 'package:openlib/services/libgen_service.dart';
import 'package:openlib/services/search_manager.dart';

class _FakePathProvider extends PathProviderPlatform {
  Future<String> _dir(String name) async {
    final dir = Directory('/tmp/openlib_live_test/$name');
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
  // NOTE: no TestWidgetsFlutterBinding here on purpose. That binding
  // replaces dart:io's HttpClient with a fake that returns 400 for
  // every request, defeating the point of live-network tests.

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    PathProviderPlatform.instance = _FakePathProvider();
  });

  group('libgen end to end', () {
    test('search finds books, book info parses, direct link downloads',
        () async {
      // Fresh defaults so the mirror list is the shipped one.
      // (Instances live in the preferences table, not their own.)
      await MyLibraryDb.instance.savePreference('archive_instances', '');

      final books = await LibgenProvider()
          .search(const SearchQuery(text: 'flutter', filtersEnabled: false));
      expect(books, isNotEmpty,
          reason: 'libgen mirrors must serve search results');

      final book = books.first;
      final info = await LibgenService().bookInfo(book.link);
      expect(info, isNotNull, reason: 'ads.php page must parse');
      expect(info!.title, isNotEmpty);
      expect(info.mirror, isNotNull,
          reason: 'ads.php page must expose the get.php download link');
      expect(info.mirror, contains('/get.php?md5='));
      expect(info.format, isNotEmpty);

      // The direct link must serve real file bytes (it 307s to a CDN,
      // so follow redirects with curl outside Dio's default behavior).
      final target = Directory('/tmp/openlib_live_test/download')
        ..createSync(recursive: true);
      final file = File('${target.path}/${book.md5}.bin');
      final proc = await Process.run('curl', [
        '-sL',
        '--max-time',
        '90',
        '-A',
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
            '(KHTML, like Gecko) Chrome/125.0 Safari/537.36',
        '-o',
        file.path,
        '-w',
        '%{http_code} %{size_download} %{content_type}',
        info.mirror!,
      ]);
      final parts = (proc.stdout as String).trim().split(' ');
      expect(parts[0], '200', reason: 'download must succeed');
      expect(int.parse(parts[1]), greaterThan(10000),
          reason: 'a real book file, not an error page');
      expect(parts[2], isNot(contains('text/html')),
          reason: 'must be a file, not an html error');
    },
        timeout: const Timeout(Duration(minutes: 3)),
        skip: 'live network - run with --run-skipped');
  });

  group('zlibrary end to end', () {
    test('search clears DiamWall and returns parsed books', () async {
      final books = await ZlibraryProvider()
          .search(const SearchQuery(text: 'flutter', filtersEnabled: false));
      expect(books, isNotEmpty,
          reason: 'z-lib.gd must serve search after the PoW solve');
      final first = books.first;
      expect(first.title, isNotEmpty);
      expect(first.link, contains('/book/'));
      expect(first.md5, isNotEmpty);
    },
        timeout: const Timeout(Duration(minutes: 2)),
        skip: 'live network - run with --run-skipped');
  });

  group('combined manager search', () {
    test('all providers fan out with per-provider failures contained',
        () async {
      await MyLibraryDb.instance
          .savePreference('searchProviders', 'annasArchive,libgen,zlibrary');

      final result =
          await SearchManager().search(const SearchQuery(text: 'flutter'));
      expect(result.books, isNotEmpty,
          reason: 'at least one provider must return results');
      // Failures are fine (mirrors rotate); silent emptiness is not.
    },
        timeout: const Timeout(Duration(minutes: 2)),
        skip: 'live network - run with --run-skipped');
  });
}
