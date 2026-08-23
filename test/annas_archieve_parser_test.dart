import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openlib/services/annas_archieve.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AnnasArchieve URL & Parser Tests', () {
    late AnnasArchieve api;

    setUp(() {
      api = AnnasArchieve();
    });

    test('urlEncoder generates correct URL query parameters', () {
      final url = api.urlEncoder(
        searchQuery: 'The Great Gatsby',
        content: 'book_fiction',
        sort: 'newest',
        fileType: 'epub',
        language: 'en',
        year: '2020-2024',
        enableFilters: true,
        currentBaseUrl: 'https://annas-archive.pk',
      );

      expect(url, startsWith('https://annas-archive.pk/search?'));
      expect(url, contains('q=The+Great+Gatsby'));
      expect(url, contains('content=book_fiction'));
      expect(url, contains('sort=newest'));
      expect(url, contains('ext=epub'));
      expect(url, contains('lang=en'));
      expect(url, contains('year_from=2020'));
      expect(url, contains('year_end=2024'));
    });

    test('cleanText removes emojis, non-standard symbols and excess whitespace', () {
      const rawText = ' 📚  Harry Potter & the Philosopher\'s Stone 🔍 ✨   ';
      final cleaned = api.cleanText(rawText);
      expect(cleaned, equals("Harry Potter & the Philosopher's Stone"));
    });

    test('getFormat correctly detects formats from metadata string', () {
      expect(api.getFormat('English [en], epub, 2.4MB, 2021'), equals('epub'));
      expect(api.getFormat('German [de], PDF, 15.1MB'), equals('pdf'));
      expect(api.getFormat('Comic, CBR, 45MB'), equals('cbr'));
      expect(api.getFormat('Comic, CBZ, 30MB'), equals('cbz'));
      expect(api.getFormat('Unknown format string'), equals('epub')); // default fallback
    });

    test('getMd5 extracts md5 from path or URL correctly', () {
      expect(api.getMd5('https://annas-archive.pk/md5/9fbeb1ac79a509bcc8a17d6137b929e7'),
          equals('9fbeb1ac79a509bcc8a17d6137b929e7'));
      expect(api.getMd5('/md5/cda91c52cd7cd89abf2104e265365e07'),
          equals('cda91c52cd7cd89abf2104e265365e07'));
    });

    test('Search results parser parses realistic Anna Archive HTML', () {
      const sampleHtml = '''
      <html>
        <body>
          <div class="flex pt-3 pb-3 border-b">
            <a href="/md5/1b0142979e5db11b7f0fb37c28f24cd1">
              <img src="https://annas-archive.pk/covers/1b0142979e5db11b7f0fb37c28f24cd1.jpg" />
            </a>
            <div>
              <a class="line-clamp-[3] js-vim-focus" href="/md5/1b0142979e5db11b7f0fb37c28f24cd1">
                Thinking, Fast and Slow
              </a>
              <a href="/search?q=Daniel+Kahneman">Daniel Kahneman</a>
              <a href="/search?q=Farrar+Straus+and+Giroux">Farrar, Straus and Giroux</a>
              <div class="text-gray-800">English [en], epub, 4.2MB, 2011</div>
            </div>
          </div>
        </body>
      </html>
      ''';

      final books = api.parser(sampleHtml, '', 'https://annas-archive.pk');
      expect(books.length, equals(1));
      expect(books.first.title, equals('Thinking, Fast and Slow'));
      expect(books.first.author, equals('Daniel Kahneman'));
      expect(books.first.publisher, equals('Farrar, Straus and Giroux'));
      expect(books.first.md5, equals('1b0142979e5db11b7f0fb37c28f24cd1'));
      expect(books.first.link, equals('https://annas-archive.pk/md5/1b0142979e5db11b7f0fb37c28f24cd1'));
    });

    test('Parser parses REAL Anna\'s Archive HTML captured from live site', () {
      // This fixture was extracted from actual live search results
      // (harry potter query, annas-archive.gl, DDoS-Guard challenge solved).
      // It uses the current production markup: note the DOUBLE SPACE in
      // 'flex  pt-3 pb-3 border-b last:border-b-0 border-gray-100'.
      final fixture = File('test/fixtures/search_results_sample.html');
      final realHtml = fixture.readAsStringSync();

      final books = api.parser(realHtml, '', 'https://annas-archive.gl');
      expect(books.length, greaterThan(0),
          reason: 'Parser must find books in real live HTML');
      final book = books.first;
      expect(book.md5, isNotEmpty);
      expect(book.md5.length, equals(32));
      expect(book.link, startsWith('https://annas-archive.gl/md5/'));
      expect(book.title, isNotEmpty);
      expect(book.info, contains('EPUB'));
    });

    test('Book detail parser parses realistic book page HTML', () async {
      const sampleDetailHtml = '''
      <html>
        <body>
          <div class="main-inner">
            <div class="font-semibold text-2xl">
              Clean Code: A Handbook of Agile Software Craftsmanship
            </div>
            <a href="/search?q=Robert+C.+Martin" class="text-base">Robert C. Martin</a>
            <a href="/search?q=Prentice+Hall">Prentice Hall</a>
            <div id="list_cover_123">
              <img src="https://annas-archive.pk/covers/cleancode.jpg" />
            </div>
            <div class="text-gray-800">English [en], pdf, 12.5MB, 2008</div>
            <div class="js-md5-top-box-description">
              <div class="text-xs text-gray-500 uppercase">description</div>
              <div>Even bad code can function. But if code isn't clean, it can bring a development organization to its knees.</div>
            </div>
            <ul class="list-inside">
              <li><a href="/slow_download/cleancode_slow">Slow Partner Server #1</a></li>
            </ul>
          </div>
        </body>
      </html>
      ''';

      final bookInfo = await api.bookInfoParser(
        sampleDetailHtml,
        'https://annas-archive.pk/md5/cleancode123',
        'https://annas-archive.pk',
      );

      expect(bookInfo, isNotNull);
      expect(bookInfo!.title, equals('Clean Code: A Handbook of Agile Software Craftsmanship'));
      expect(bookInfo.author, equals('Robert C. Martin'));
      expect(bookInfo.publisher, equals('Prentice Hall'));
      expect(bookInfo.format, equals('pdf'));
      expect(bookInfo.mirror, equals('https://annas-archive.pk/slow_download/cleancode_slow'));
      expect(bookInfo.description, contains('Even bad code can function'));
    });
  });
}
