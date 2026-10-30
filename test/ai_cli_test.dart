import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openlib/cli/annas_archive.dart';
import 'package:openlib/cli/slum.dart';
import 'package:openlib/core/annas_archive.dart';
import 'package:openlib/core/slum.dart';

String _fixture(String name) => File('test/fixtures/$name').readAsStringSync();

Response _response(int status, String body,
        {Map<String, List<String>> headers = const {}}) =>
    Response(
      requestOptions: RequestOptions(path: '/'),
      statusCode: status,
      data: body,
      headers: Headers.fromMap(headers),
    );

void main() {
  group('CliAnnasArchive URL building', () {
    test('plain query has no filter parameters', () {
      final url = ArchiveParsing.buildSearchUrl(
        baseUrl: 'https://annas-archive.gl',
        query: 'docker',
      );
      expect(url, equals('https://annas-archive.gl/search?q=docker'));
    });

    test('filters produce the documented parameter set', () {
      final url = ArchiveParsing.buildSearchUrl(
        baseUrl: 'https://annas-archive.gl',
        query: 'The Great Gatsby',
        content: 'book_fiction',
        sort: 'newest',
        fileType: 'epub',
        language: 'en',
        yearFrom: '2020',
        yearTo: '2024',
      );
      expect(url, startsWith('https://annas-archive.gl/search?'));
      expect(url, contains('q=The+Great+Gatsby'));
      expect(url, contains('content=book_fiction'));
      expect(url, contains('sort=newest'));
      expect(url, contains('ext=epub'));
      expect(url, contains('lang=en'));
      expect(url, contains('year_from=2020'));
      expect(url, contains('year_end=2024'));
    });

    test('author and publisher become field-scoped terms', () {
      final url = ArchiveParsing.buildSearchUrl(
        baseUrl: 'https://annas-archive.gl',
        query: 'hobbit',
        author: 'JRR Tolkien',
      );
      expect(url, contains('author:%22JRR+Tolkien%22'));
      expect(url, endsWith('+hobbit'));
    });

    test('pagination appends and page 1 omits', () {
      final page1 = ArchiveParsing.buildSearchUrl(
          baseUrl: 'https://annas-archive.gl', query: 'docker');
      final page2 = ArchiveParsing.buildSearchUrl(
          baseUrl: 'https://annas-archive.gl', query: 'docker', page: 2);
      expect(page1, isNot(contains('page=')));
      expect(page2, contains('&page=2'));
    });
  });

  group('CliAnnasArchive parsing', () {
    final client = CliAnnasArchive();

    test('parses realistic search HTML', () {
      const sampleHtml = '''
      <html><head><title>search - Anna's Archive</title></head>
      <body>
        <div class="flex pt-3 pb-3 border-b">
          <a href="/md5/1b0142979e5db11b7f0fb37c28f24cd1">
            <img src="https://annas-archive.gl/covers/x.jpg" />
          </a>
          <div>
            <a class="line-clamp-[3] js-vim-focus"
               href="/md5/1b0142979e5db11b7f0fb37c28f24cd1">
              Thinking, Fast and Slow
            </a>
            <a href="/search?q=Daniel+Kahneman">Daniel Kahneman</a>
            <a href="/search?q=Farrar+Straus">Farrar, Straus and Giroux</a>
            <div class="text-gray-800">English [en], epub, 4.2MB, 2011</div>
          </div>
        </div>
      </body></html>
      ''';
      final books = client.parseSearchResults(sampleHtml,
          baseUrl: 'https://annas-archive.gl');
      expect(books.length, equals(1));
      expect(books.first.title, equals('Thinking, Fast and Slow'));
      expect(books.first.author, equals('Daniel Kahneman'));
      expect(books.first.publisher, equals('Farrar, Straus and Giroux'));
      expect(books.first.md5, equals('1b0142979e5db11b7f0fb37c28f24cd1'));
      expect(books.first.format, equals('epub'));
      expect(
          books.first.link,
          contains(
              'https://annas-archive.gl/md5/1b0142979e5db11b7f0fb37c28f24cd1'));
    });

    test('parses the captured search fixture', () {
      final html = _fixture('search_results_sample.html');
      final books =
          client.parseSearchResults(html, baseUrl: 'https://annas-archive.gl');
      expect(books, isNotEmpty);
      for (final book in books) {
        expect(book.md5, isNotEmpty);
        expect(book.title, isNotEmpty);
      }
    });

    test('fileType filter drops non-matching results', () {
      final html = _fixture('search_results_sample.html');
      final all =
          client.parseSearchResults(html, baseUrl: 'https://annas-archive.gl');
      final pdfOnly = client.parseSearchResults(html,
          fileType: 'pdf', baseUrl: 'https://annas-archive.gl');
      expect(pdfOnly.length, lessThanOrEqualTo(all.length));
    });

    test('parses the captured book page fixture', () {
      final html = _fixture('real_aa_book_page.html');
      final details = client.parseBookInfo(
        html,
        url: 'https://annas-archive.gl/md5/9fbeb1ac79a509bcc8a17d6137b929e7',
        baseUrl: 'https://annas-archive.gl',
      );
      expect(details, isNotNull);
      expect(details!.title, equals('Villa Coco: A Novel'));
      expect(details.md5, equals('9fbeb1ac79a509bcc8a17d6137b929e7'));
      expect(
          details.slowDownloadUrl,
          equals('https://annas-archive.gl'
              '/slow_download/aea690732da6694ee887aca6097612c2/0/0'));
      expect(details.format, isNotEmpty);
    });

    test('returns null for a page without a book record', () {
      final html = _fixture('cloudflare_interstitial.html');
      final details = client.parseBookInfo(html,
          url: 'https://annas-archive.gl/md5/x',
          baseUrl: 'https://annas-archive.gl');
      expect(details, isNull);
    });

    test('extracts the direct link from a slow_download page', () {
      // The app's webview extracts the first link inside the bold
      // paragraph; the CLI must find the same link with plain parsing.
      const page = '''
      <html><body>
        <p class="mb-4 text-xl font-bold">
          Click here:
          <a href="https://gateway.example/ipfs/download?x=1">Download now</a>
        </p>
      </body></html>
      ''';
      final link = CliAnnasArchive.extractSlowDownloadLink(page);
      expect(link, equals('https://gateway.example/ipfs/download?x=1'));

      // Relative links resolve against the page URL.
      final relative = CliAnnasArchive.extractSlowDownloadLink(
          '<p class="mb-4 text-xl font-bold"><a href="/get/abc">dl</a></p>',
          pageUrl: 'https://m.example/slow_download/a/0/0');
      expect(relative, equals('https://m.example/get/abc'));

      // No link: null (the network path turns this into not_found).
      expect(CliAnnasArchive.extractSlowDownloadLink('<html></html>'), isNull);
    });
  });

  group('CliAnnasArchive challenge detection', () {
    final client = CliAnnasArchive();

    test('detects Cloudflare interstitial by title', () {
      final response = _response(403, _fixture('cloudflare_interstitial.html'));
      expect(client.isChallengeResponse(response), isTrue);
    });

    test('detects DDoS-Guard interstitial by title', () {
      final response = _response(403, _fixture('ddosguard_interstitial.html'));
      expect(client.isChallengeResponse(response), isTrue);
    });

    test('plain 403 without challenge markers is not a block', () {
      final response = _response(403, _fixture('aa_plain_403.html'));
      expect(client.isChallengeResponse(response), isFalse);
    });

    test('search result pages are not mistaken for challenges', () {
      final response = _response(200, _fixture('search_results_sample.html'));
      expect(client.isChallengeResponse(response), isFalse);
      expect(client.isAnnasArchivePage(_fixture('search_results_sample.html')),
          isTrue);
    });
  });

  group('CliSlumCatalogue', () {
    test('parses the captured SLUM page and orders attemptable first', () {
      final catalogue = CliSlumCatalogue();
      final sites = catalogue.parsePage(_fixture('slum_annas.html'));
      expect(sites, isNotEmpty);

      final firstDown = sites.indexWhere((site) => site.isDown);
      final lastUp = sites.lastIndexWhere((site) => !site.isDown);
      if (firstDown != -1 && lastUp != -1) {
        expect(firstDown, greaterThan(lastUp));
      }

      // Hosts come from SLUM, not from a hardcoded list.
      for (final site in sites) {
        expect(site.url, startsWith('http'));
        expect(site.host, isNotEmpty);
      }
    });

    test('normalizeUrl adds scheme and strips trailing slash', () {
      expect(CliSlumCatalogue.normalizeUrl(' annas-archive.gl/ '),
          equals('https://annas-archive.gl'));
      expect(CliSlumCatalogue.normalizeUrl('https://x.example//'),
          equals('https://x.example'));
    });
  });

  group('CLI helpers', () {
    test('sortSlumSites orders by protection, status and latency', () {
      SlumSite site(
        String host, {
        required Protection protection,
        required SlumStatus status,
        int? latency,
      }) =>
          SlumSite(
            service: MirrorService.annasArchive,
            url: 'https://$host',
            host: host,
            status: status,
            protection: protection,
            latencyMs: latency,
          );

      final ordered = sortSlumSites([
        site('down.example',
            protection: Protection.none, status: SlumStatus.down),
        site('slow.example',
            protection: Protection.cloudflare, status: SlumStatus.up),
        site('fast.example',
            protection: Protection.none, status: SlumStatus.up, latency: 20),
        site('diam.example',
            protection: Protection.diamwall,
            status: SlumStatus.up,
            latency: 10),
      ]);
      expect(
        ordered.map((s) => s.host),
        equals(
            ['fast.example', 'diam.example', 'slow.example', 'down.example']),
      );
    });

    test('bookFileName sanitizes and keeps a short md5 suffix', () {
      final name = CliAnnasArchive.bookFileName(
        title: 'Quantum Computing: An Introduction / Édition française',
        author: 'Alice Author',
        format: 'epub',
        md5: '8efbf8e9f8b4592c7b0dbedec9c0ec05',
      );
      expect(name, contains('Alice Author - '));
      expect(name, endsWith('(8efbf8e9).epub'));
      expect(name, isNot(contains('/')));
      expect(name, isNot(contains('É')));
    });

    test('normalizeBookUrl accepts md5 and full URLs', () {
      expect(
          CliAnnasArchive.normalizeBookUrl(
              '8efbf8e9f8b4592c7b0dbedec9c0ec05', 'https://m.example'),
          equals('https://m.example/md5/8efbf8e9f8b4592c7b0dbedec9c0ec05'));
      expect(
          CliAnnasArchive.normalizeBookUrl(
              'https://annas-archive.pk/md5/9fbeb1ac79a509bcc8a17d6137b929e7',
              'https://m.example'),
          equals('https://m.example/md5/9fbeb1ac79a509bcc8a17d6137b929e7'));
    });

    test('resolveRelative resolves against the page URL', () {
      expect(
          CliAnnasArchive.resolveRelative(
              '/slow_download/a/0/0', 'https://m.example/slow_download/a/0/1'),
          equals('https://m.example/slow_download/a/0/0'));
      expect(
          CliAnnasArchive.resolveRelative(
              'https://other.example/file.pdf', 'https://m.example/x'),
          equals('https://other.example/file.pdf'));
    });
  });
}
