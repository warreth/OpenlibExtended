// Real tests for metadata-aware search: how the provider mappers turn
// advanced-search fields into backend-native parameters, and how the
// local library filter matches across metadata. URL building is pure
// string logic - tested directly, no network.

// Dart imports:
import 'dart:io';

// Flutter imports:
import 'package:flutter_test/flutter_test.dart';

// Package imports:
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

// Project imports:
import 'package:openlib/services/annas_archieve.dart';
import 'package:openlib/services/search_manager.dart';
import 'package:openlib/services/database.dart';
import 'package:openlib/services/library_organization.dart';
import 'package:openlib/state/state.dart'
    show
        libraryBooksProvider,
        librarySearchQueryProvider,
        libraryTagFilterProvider,
        organizedLibraryProvider;

class _FakePathProvider extends PathProviderPlatform {
  Future<String> _dir(String name) async {
    final dir = Directory('/tmp/openlib_meta_test/$name');
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
  TestWidgetsFlutterBinding.ensureInitialized();

  final api = AnnasArchieve();
  const base = 'https://annas-archive.example';

  group("Anna's Archive field-scoped query", () {
    test('author and publisher become q= field terms', () {
      final url = api.urlEncoder(
        searchQuery: 'hobbit',
        content: '',
        sort: '',
        fileType: '',
        language: '',
        year: '',
        author: 'j r r tolkien',
        publisher: 'harper collins',
        enableFilters: true,
        currentBaseUrl: base,
      );
      expect(url, startsWith('$base/search?index=&sort='));
      expect(
          url,
          contains(
              'q=author:%22j+r+r+tolkien%22+publisher:%22harper+collins%22+hobbit'));
    });

    test('fields without values keep the plain query untouched', () {
      final url = api.urlEncoder(
        searchQuery: 'dune',
        content: '',
        sort: '',
        fileType: '',
        language: '',
        year: '',
        author: '',
        publisher: '',
        enableFilters: true,
        currentBaseUrl: base,
      );
      expect(url, contains('q=dune'));
      expect(url, isNot(contains('author:')));
      expect(url, isNot(contains('publisher:')));
    });

    test('whitespace-only fields are ignored', () {
      final url = api.urlEncoder(
        searchQuery: 'dune',
        content: '',
        sort: '',
        fileType: '',
        language: '',
        year: '',
        author: '   ',
        publisher: '',
        enableFilters: true,
        currentBaseUrl: base,
      );
      expect(url, isNot(contains('author:')));
    });
  });

  group('SearchQuery metadata plumbing', () {
    test('isEmpty is false when only metadata fields are set', () {
      const query = SearchQuery(text: '', author: 'tolkien');
      expect(query.isEmpty, isFalse);
      expect(const SearchQuery(text: '').isEmpty, isTrue);
    });
  });

  group('Libgen columns mapping', () {
    test('author-only search targets the author column', () async {
      final requested = <Uri>[];
      final dio = _RecordingDio(requested);
      final provider = LibgenProvider(dio: dio, mirrors: ['https://lg.example']);

      try {
        await provider.search(const SearchQuery(
          text: '',
          author: 'Asimov',
          filtersEnabled: true,
        ));
      } catch (_) {
        // Recording Dio throws after capture; the URL is what matters.
      }

      expect(requested, isNotEmpty);
      final uri = requested.single;
      expect(uri.queryParameters['req'], 'Asimov');
      expect(uri.queryParametersAll['columns[]'], contains('a'));
      expect(uri.queryParametersAll['columns[]'], isNot(contains('p')));
    });

    test('author plus text are folded into req together', () async {
      final requested = <Uri>[];
      final dio = _RecordingDio(requested);
      final provider = LibgenProvider(dio: dio, mirrors: ['https://lg.example']);

      try {
        await provider.search(const SearchQuery(
          text: 'foundation',
          author: 'Asimov',
          filtersEnabled: true,
        ));
      } catch (_) {}

      expect(requested, isNotEmpty);
      expect(requested.single.queryParameters['req'], 'Asimov foundation');
    });

    test('plain searches never send columns', () async {
      final requested = <Uri>[];
      final dio = _RecordingDio(requested);
      final provider = LibgenProvider(dio: dio, mirrors: ['https://lg.example']);

      try {
        await provider.search(const SearchQuery(text: 'foundation'));
      } catch (_) {}

      expect(requested, isNotEmpty);
      expect(requested.single.queryParameters.containsKey('columns'), isFalse);
    });

    test('metadata fields are skipped when filters are disabled', () async {
      final requested = <Uri>[];
      final dio = _RecordingDio(requested);
      final provider = LibgenProvider(dio: dio, mirrors: ['https://lg.example']);

      try {
        await provider.search(const SearchQuery(
          text: 'foundation',
          author: 'Asimov',
          filtersEnabled: false,
        ));
      } catch (_) {}

      expect(requested, isNotEmpty);
      expect(requested.single.queryParameters['req'], 'foundation');
      expect(requested.single.queryParameters.containsKey('columns'), isFalse);
    });
  });

  group('library metadata filter', () {
    test('query matches title, author, publisher and info', () {
      final books = [
        LibraryBook(
            book: MyBook(
                id: 'a',
                title: 'Foundation',
                author: 'Isaac Asimov',
                thumbnail: null,
                link: 'l',
                publisher: 'Doubleday',
                info: '[en], pdf, 5.2MB, 1951',
                format: 'pdf',
                description: null)),
        LibraryBook(
            book: MyBook(
                id: 'b',
                title: 'Dune',
                author: 'Frank Herbert',
                thumbnail: null,
                link: 'l',
                publisher: 'Chilton',
                info: '[en], epub, 1965',
                format: 'epub',
                description: null)),
      ];

      expect(filterLibrary(books, query: 'asimov').map((b) => b.id), ['a']);
      expect(filterLibrary(books, query: 'DUNE').map((b) => b.id), ['b']);
      expect(filterLibrary(books, query: 'chilton').map((b) => b.id), ['b']);
      expect(filterLibrary(books, query: '1951').map((b) => b.id), ['a']);
      expect(filterLibrary(books, query: 'zzz'), isEmpty);
      // Empty and whitespace queries keep everything.
      expect(filterLibrary(books, query: '').length, 2);
      expect(filterLibrary(books, query: '   ').length, 2);
    });

    test('combined with status and tag filters', () async {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      PathProviderPlatform.instance = _FakePathProvider();

      final db = MyLibraryDb.instance;
      final database = await db.database;
      await database.delete('mybooks');
      await database.delete('bookposition');
      await database.delete('booktags');

      await db.insert(MyBook(
          id: 'm1',
          title: 'I, Robot',
          author: 'Asimov',
          thumbnail: null,
          link: 'l',
          publisher: null,
          info: null,
          format: 'pdf',
          description: null));
      await db.addTag('m1', 'Sci-Fi');

      final container = ProviderContainer();
      addTearDown(container.dispose);

      // Wait for the enrichment provider to load the seeded rows.
      await container.read(libraryBooksProvider.future);

      container.read(libraryTagFilterProvider.notifier).state = {'Sci-Fi'};
      container.read(librarySearchQueryProvider.notifier).state = 'asimov';
      final organized = container.read(organizedLibraryProvider);
      expect(organized.map((b) => b.id), ['m1']);

      // Query that contradicts the tag filter clears the list.
      container.read(librarySearchQueryProvider.notifier).state = 'tolkien';
      expect(container.read(organizedLibraryProvider), isEmpty);
    });
  });
}

/// A Dio substitute that records the request URL and throws - the
/// libgen search loop then moves on and reports failure, but the test
/// already captured what it needs: the exact query string.
class _RecordingDio implements Dio {
  _RecordingDio(this.requests);

  final List<Uri> requests;

  @override
  Future<Response<T>> get<T>(String path,
      {Object? data,
      Map<String, dynamic>? queryParameters,
      Options? options,
      CancelToken? cancelToken,
      ProgressCallback? onReceiveProgress}) async {
    requests.add(Uri.parse(path));
    throw Exception('recording stop');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
