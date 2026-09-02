// Real tests for multi-provider search: the libgen table parser against
// the HTML shape libgen.is serves, the fan-out merge with fake providers
// (one succeeding, one failing, one returning dupes), and provider
// toggles persisted through the real sqlite preferences table.

// Dart imports:
import 'dart:io';

// Flutter imports:
import 'package:flutter_test/flutter_test.dart';

// Package imports:
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

// Project imports:
import 'package:openlib/services/annas_archieve.dart';
import 'package:openlib/services/database.dart';
import 'package:openlib/services/search_manager.dart';

class _FakePathProvider extends PathProviderPlatform {
  Future<String> _dir(String name) async {
    final dir = Directory('/tmp/openlib_searchmgr_test/$name');
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

/// A provider the test fully controls.
class _FakeProvider implements SearchProvider {
  _FakeProvider(this.idName, this.results, {this.error});

  final String idName;
  final List<BookData> results;
  final Object? error;

  int calls = 0;

  @override
  SearchProviderId get id =>
      SearchProviderId.values.firstWhere((v) => v.name == idName);

  @override
  String get displayName => idName;

  @override
  Future<List<BookData>> search(SearchQuery query) async {
    calls++;
    if (error != null) throw error!;
    return results;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      PathProviderPlatform.instance = _FakePathProvider();
    }
  });

  // Wipe the preferences between runs so toggle tests start clean.
  setUp(() async {
    final db = MyLibraryDb.instance;
    try {
      await db.savePreference('searchProviders', 'annasArchive');
    } catch (_) {}
  });

  const libgenHtml = '''
  <html><body>
  <table class="c">
    <tbody>
      <tr>
        <td>123456</td>
        <td>Ursula K. Le Guin</td>
        <td><a href="/ads.php?md5=a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4" title="A Wizard of Earthsea">A Wizard of Earthsea</a></td>
        <td>Atheneum</td>
        <td>1968</td>
        <td>183</td>
        <td>English</td>
        <td>2.1MB</td>
        <td>epub</td>
        <td><a href="/get.php?md5=a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4">GET</a></td>
      </tr>
      <tr>
        <td>123457</td>
        <td>J.R.R. Tolkien</td>
        <td><a href="/ads.php?md5=b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5" title="The Hobbit">The Hobbit</a></td>
        <td>Houghton Mifflin</td>
        <td>1937</td>
        <td>310</td>
        <td>English</td>
        <td>1.4MB</td>
        <td>pdf</td>
        <td><a href="/get.php?md5=b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5">GET</a></td>
      </tr>
    </tbody>
  </table>
  </body></html>
  ''';

  group('LibgenProvider.parseResults', () {
    test('parses rows into books with metadata and absolute links', () {
      final provider = LibgenProvider();
      final books = provider.parseResults(libgenHtml, 'https://libgen.is');

      expect(books.length, 2);

      final first = books.first;
      expect(first.title, 'A Wizard of Earthsea');
      expect(first.author, 'Ursula K. Le Guin');
      expect(first.publisher, 'Atheneum');
      expect(first.md5, 'a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4');
      expect(first.link,
          'https://libgen.is/ads.php?md5=a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4');
      expect(first.info, contains('English'));
      expect(first.info, contains('EPUB'));
      expect(first.info, contains('1968'));
    });

    test('returns empty for a page without a results table', () {
      final provider = LibgenProvider();
      expect(
          provider.parseResults(
              '<html><body>no table</body></html>', 'https://libgen.is'),
          isEmpty);
    });

    test('parses the libgen.li/vg table layout from a captured page', () {
      final provider = LibgenProvider();
      final captured =
          File('test/fixtures/libgen_vg_results.html').readAsStringSync();
      final books = provider.parseResults(captured, 'https://libgen.vg');

      // The fixture holds 3 book rows (plus the header row, skipped).
      expect(books.length, 3);

      for (final book in books) {
        expect(book.title, isNotEmpty);
        expect(book.author, isNotEmpty);
        expect(book.link, startsWith('https://libgen.vg'));
        // Info carries language/ext/size/year in some order.
        expect(book.info, isNotNull);
      }

      // First captured row is a known magazine entry.
      expect(books.first.title, 'Pacing and Clinical Electrophysiology');
      expect(books.first.info, contains('English'));
      expect(books.first.info, contains('PDF'));
    });

    test('skips rows with no title link', () {
      final broken = libgenHtml.replaceFirst(
          '<a href="/ads.php?md5=a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4" title="A Wizard of Earthsea">A Wizard of Earthsea</a>',
          'no link here');
      final provider = LibgenProvider();
      final books = provider.parseResults(broken, 'https://libgen.is');
      expect(books.length, 1);
      expect(books.first.title, 'The Hobbit');
    });
  });

  // A page captured live from z-lib.gd (DiamWall cleared) drives the
  // detail parser: no network, no challenge.
  group('ZlibraryProvider.parseBookPage', () {
    test('parses title, author, file info and download link', () {
      final html =
          File('test/fixtures/zlib_book_page.html').readAsStringSync();
      final provider = ZlibraryProvider();

      final data = provider.parseBookPage(
          html, 'https://z-lib.gd',
          'https://z-lib.gd/book/RAZbKkmYAy/americas-test-kitchen.html');

      expect(data, isNotNull);
      expect(data!.title,
          startsWith('America’s Test Kitchen'));
      expect(data.author, "America's Test Kitchen");
      expect(data.format, 'EPUB');
      expect(data.info, contains('English'));
      expect(data.info, contains('2016'));
      expect(data.mirror, isNotNull);
      expect(data.mirror, startsWith('https://z-lib.gd/dl/'));
      // The stable book id doubles as the md5 key in the library db.
      expect(data.md5, 'RAZbKkmYAy');
    });

    test('returns null without a title', () {
      final data = ZlibraryProvider().parseBookPage(
          '<html><body><h1></h1></body></html>', 'https://z-lib.gd', 'x');
      expect(data, isNull);
    });
  });

  group('SearchManager fan-out', () {
    test('stops at the first provider with results, reports failures',
        () async {
      // Libgen first in the chain: fails -> chain moves on to AA, which
      // delivers, and zlib (never reached) stays at 0 calls.
      final failing = _FakeProvider('libgen', [], error: Exception('down'));
      final ok = _FakeProvider('annasArchive', [
        BookData(title: 'AA Book', link: 'https://a/md5/x1', md5: 'md5-1'),
      ]);
      final never = _FakeProvider('zlibrary', [
        BookData(title: 'Z', link: 'https://z/md5/x1', md5: 'md5-z'),
      ]);
      final manager = SearchManager(
        database: MyLibraryDb.instance,
        providers: [failing, ok, never],
      );
      await manager.setProviderEnabled(SearchProviderId.libgen, true);
      await manager.setProviderEnabled(SearchProviderId.annasArchive, true);
      await manager.setProviderEnabled(SearchProviderId.zlibrary, true);

      final result = await manager.search(const SearchQuery(text: 'wizard'));

      expect(result.books.length, 1);
      expect(result.books.first.title, 'AA Book');
      expect(result.failedProviders, ['libgen']);
      expect(failing.calls, 1); // it was tried, not skipped
      expect(never.calls, 0); // chain stopped at the first hit
    });

    test('drops duplicate md5s within one provider result page', () async {
      // The chain stops at the first provider with hits, so dedupe now
      // matters inside a single provider's page (libgen mirrors can
      // return the same edition twice).
      final dupe = BookData(
          title: 'From Libgen', link: 'https://l/md5/x', md5: 'same-md5');
      final provider = _FakeProvider('libgen', [
        dupe,
        BookData(
            title: 'From Mirror 2', link: 'https://l/md5/x2', md5: 'same-md5'),
        BookData(title: 'Unique', link: 'https://l/md5/y', md5: 'other')
      ]);
      final manager = SearchManager(
        database: MyLibraryDb.instance,
        providers: [provider],
      );
      await manager.setProviderEnabled(SearchProviderId.libgen, true);

      final result = await manager.search(const SearchQuery(text: 'dupes'));

      expect(result.books.length, 2);
      expect(result.books.firstWhere((b) => b.md5 == 'same-md5').title,
          'From Libgen');
    });

    test('searches only enabled providers', () async {
      final off = _FakeProvider('zlibrary', [
        BookData(title: 'Z', link: 'https://z/1', md5: 'z-md5'),
      ]);
      final on = _FakeProvider('annasArchive', [
        BookData(title: 'A', link: 'https://a/1', md5: 'a-md5'),
      ]);
      final manager = SearchManager(
        database: MyLibraryDb.instance,
        providers: [on, off],
      );
      // Stored preference (seeded by setUp): annasArchive only.

      final result = await manager.search(const SearchQuery(text: 'q'));

      expect(result.books.length, 1);
      expect(off.calls, 0);
    });

    // A fresh install has no stored preference; the chain must cover
    // every provider, libgen first.
    test('with no stored preference, all providers are on', () async {
      final db = MyLibraryDb.instance;
      final raw = await db.database;
      await raw.delete('preferences',
          where: 'name = ?', whereArgs: ['searchProviders']);
      addTearDown(() async {
        await db.savePreference('searchProviders', 'annasArchive');
      });

      final manager = SearchManager(database: db);
      final enabled = await manager.enabledProviders();

      expect(enabled, containsAll(SearchProviderId.values));
    });

    test('last provider cannot be disabled', () async {
      final manager = SearchManager(database: MyLibraryDb.instance);
      // Default: annasArchive only.
      await manager.setProviderEnabled(SearchProviderId.annasArchive, false);
      final enabled = await manager.enabledProviders();
      expect(enabled, {SearchProviderId.annasArchive});
    });

    test('toggles persist through the preferences table', () async {
      final manager = SearchManager(database: MyLibraryDb.instance);
      await manager.setProviderEnabled(SearchProviderId.libgen, true);
      await manager.setProviderEnabled(SearchProviderId.zlibrary, true);

      final reRead = SearchManager(database: MyLibraryDb.instance);
      final enabled = await reRead.enabledProviders();
      expect(
          enabled,
          containsAll([
            SearchProviderId.annasArchive,
            SearchProviderId.libgen,
            SearchProviderId.zlibrary,
          ]));

      await reRead.setProviderEnabled(SearchProviderId.zlibrary, false);
      final afterOff = await SearchManager(database: MyLibraryDb.instance)
          .enabledProviders();
      expect(afterOff, isNot(contains(SearchProviderId.zlibrary)));
    });
  });
}
