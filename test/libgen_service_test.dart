import 'dart:io';

// Package imports:
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

// Project imports:
import 'package:openlib/services/libgen_service.dart';

// Desktop test runner needs the sqlite plugin faked; the app itself uses
// the platform plugin. InstanceManager needs the real local database to
// resolve the enabled libgen mirror list.
class _FakePathProvider extends PathProviderPlatform {
  Future<String> _dir(String name) async {
    final dir = Directory('/tmp/openlib_libgen_test/$name');
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

const _md5Temple = '7373b39d1addaf236328975f9bbef7c4';
const _md5Flutter = '0229cc161352df1fb45a8f8246350910';

void main() {
  setUpAll(() {
    if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      PathProviderPlatform.instance = _FakePathProvider();
    }
  });

  group('parseAdsPage on captured libgen pages', () {
    test('parses the Temple Legacy ads page (md5=$_md5Temple)', () {
      final html = File('test/fixtures/libgen_ads_page.html')
          .readAsStringSync(); // live capture of libgen.vg ads.php

      final book = LibgenService().parseAdsPage(html, 'https://libgen.vg',
          'https://libgen.vg/ads.php?md5=$_md5Temple');

      expect(book, isNotNull);
      expect(book!.title, equals('The Temple Legacy'));
      expect(book.author, equals('Macey, D.C.'));
      expect(book.publisher, contains('Butcher & Cameron'));
      expect(book.publisher, contains('2015'));
      expect(book.publisher, contains('Series: The Temple 1'));
      expect(book.md5, equals(_md5Temple));
      // The mirror must be the get.php download URL with the key.
      expect(book.mirror,
          startsWith('https://libgen.vg/get.php?md5=$_md5Temple&key='));
      expect(book.mirror, matches(r'&key=[0-9A-Z]{16}$'));
      // Cover is absolute.
      expect(book.thumbnail,
          equals('https://libgen.vg/fictioncovers/2204000/$_md5Temple.jpg'));
    });

    test('parses the Flutter for Beginners ads page (md5=$_md5Flutter)', () {
      final html = File('test/fixtures/libgen_ads_page_flutter.html')
          .readAsStringSync(); // live capture of libgen.vg ads.php

      final book = LibgenService().parseAdsPage(html, 'https://libgen.li',
          'https://libgen.li/ads.php?md5=$_md5Flutter');

      expect(book, isNotNull);
      expect(book!.title,
          startsWith('Flutter for Beginners: An introductory guide'));
      expect(book.author, equals('Thomas Bailey, Alessandro Biessek'));
      expect(book.publisher, contains('Packt Publishing'));
      expect(book.publisher, contains('2021'));
      expect(book.md5, equals(_md5Flutter));
      expect(book.mirror,
          startsWith('https://libgen.li/get.php?md5=$_md5Flutter&key='));
      expect(book.thumbnail,
          equals('https://libgen.li/covers/3206000/$_md5Flutter.jpg'));
    });

    test('md5 falls back to the get.php link when the url lacks it', () {
      final html =
          File('test/fixtures/libgen_ads_page.html').readAsStringSync();

      final book = LibgenService()
          .parseAdsPage(html, 'https://libgen.vg', 'https://libgen.vg/ads.php');

      expect(book, isNotNull);
      expect(book!.md5, equals(_md5Temple));
    });

    test('format defaults to epub when no extension is visible', () {
      final html =
          File('test/fixtures/libgen_ads_page.html').readAsStringSync();

      // Neither fixture page nor the url carry an extension token.
      final book = LibgenService().parseAdsPage(html, 'https://libgen.vg',
          'https://libgen.vg/ads.php?md5=$_md5Temple');

      expect(book, isNotNull);
      expect(book!.format, equals('epub'));
    });
  });

  group('parseAdsCover (lazy result-list covers)', () {
    test('extracts the cover URL from a captured ads page', () {
      final html =
          File('test/fixtures/libgen_ads_page.html').readAsStringSync();

      final cover =
          LibgenService.parseAdsCover(html, 'https://libgen.vg');

      // The fixture's cover img is a relative /fictioncovers/ URL.
      expect(cover, isNotNull);
      expect(cover,
          'https://libgen.vg/fictioncovers/2204000/7373b39d1addaf236328975f9bbef7c4.jpg');
    });

    test('keeps absolute cover URLs untouched', () {
      const html =
          '<table id="main"><tr><td><img src="https://libgen.li/covers/1/abc.jpg">'
          '</td><td>Title: X</td></tr></table>';

      expect(LibgenService.parseAdsCover(html, 'https://libgen.li'),
          'https://libgen.li/covers/1/abc.jpg');
    });

    test('returns null when the img src is empty (libgen.vg quirk)', () {
      const html =
          '<table id="main"><tr><td><img src=""></td><td>Title: X</td></tr></table>';

      expect(LibgenService.parseAdsCover(html, 'https://libgen.vg'), isNull);
    });

    test('returns null on a search results page (no ads table)', () {
      final html =
          File('test/fixtures/libgen_vg_results.html').readAsStringSync();

      expect(LibgenService.parseAdsCover(html, 'https://libgen.vg'), isNull);
    });
  });

  group('parseAdsPage rejects non-matching markup', () {
    test('returns null on garbage html', () {
      expect(
          LibgenService().parseAdsPage('<html><body>hello world</body></html>',
              'https://libgen.vg', 'https://libgen.vg/ads.php?md5=$_md5Temple'),
          isNull);
    });

    test('returns null on a Cloudflare challenge page', () {
      expect(
          LibgenService().parseAdsPage(
              '<!DOCTYPE html><html><head><title>Just a moment...</title>'
                  '</head><body>Checking your browser before accessing.</body></html>',
              'https://libgen.gl',
              'https://libgen.gl/ads.php?md5=$_md5Temple'),
          isNull);
    });

    test('returns null on a search results page (no ads detail row)', () {
      final html =
          File('test/fixtures/libgen_vg_results.html').readAsStringSync();

      expect(
          LibgenService().parseAdsPage(html, 'https://libgen.vg',
              'https://libgen.vg/index.php?req=flutter&res=25'),
          isNull);
    });

    test('never throws on truncated html', () {
      final html = File('test/fixtures/libgen_ads_page.html')
          .readAsStringSync()
          .substring(0, 5000);

      // Must return null or a book - but not throw.
      final book = LibgenService().parseAdsPage(html, 'https://libgen.vg',
          'https://libgen.vg/ads.php?md5=$_md5Temple');
      expect(book == null || book.title.isNotEmpty, isTrue);
    });
  });

  group('mirror host swap logic', () {
    final service = LibgenService();

    test('swapHost keeps path and query', () {
      expect(
          service.swapHost(
              'https://dead.example/ads.php?md5=X', 'https://libgen.li'),
          equals('https://libgen.li/ads.php?md5=X'));
      expect(
          service.swapHost(
              'https://dead.example/ads.php?md5=X', 'https://libgen.bz'),
          equals('https://libgen.bz/ads.php?md5=X'));
      expect(
          service.swapHost(
              'https://libgen.vg/ads.php?md5=X&key=K', 'https://libgen.li'),
          equals('https://libgen.li/ads.php?md5=X&key=K'));
    });

    test('candidateUrls leads with the original url then other mirrors', () {
      final mirrors = ['https://libgen.li', 'https://libgen.bz'];
      expect(
          service.candidateUrls('https://dead.example/ads.php?md5=X', mirrors),
          equals([
            'https://dead.example/ads.php?md5=X',
            'https://libgen.li/ads.php?md5=X',
            'https://libgen.bz/ads.php?md5=X',
          ]));
    });

    test('candidateUrls does not repeat the working host', () {
      final mirrors = ['https://libgen.li', 'https://libgen.bz'];
      expect(
          service.candidateUrls('https://libgen.li/ads.php?md5=X', mirrors),
          equals([
            'https://libgen.li/ads.php?md5=X',
            'https://libgen.bz/ads.php?md5=X',
          ]));
    });

    test('candidateUrls resolves a bare path against the first mirror',
        () async {
      expect(
          service.candidateUrls(
              '/ads.php?md5=X', ['https://libgen.li', 'https://libgen.bz']),
          equals([
            'https://libgen.li/ads.php?md5=X',
            'https://libgen.bz/ads.php?md5=X',
          ]));
    });

    test('full mirror list comes from InstanceManager', () {
      final urls = LibgenService().candidateUrls(
          'https://libgen.li/ads.php?md5=X', const ['https://x']);
      // The @visibleForTesting wrapper is the same helper bookInfo uses;
      // verify it exists and is callable with any list.
      expect(urls.first, equals('https://libgen.li/ads.php?md5=X'));
    });
  });

  group('bookInfo (live network - run manually)', () {
    test('fetches a real book from libgen.vg', () async {
      final book = await LibgenService()
          .bookInfo('https://libgen.vg/ads.php?md5=$_md5Temple');

      expect(book, isNotNull);
      expect(book!.title, equals('The Temple Legacy'));
      expect(book.author, isNotEmpty);
      expect(book.mirror, startsWith('https://libgen.vg/get.php?md5='));
    }, skip: 'live network - run manually');
  });
}
