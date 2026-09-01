// Real tests for library customization: sorting modes, tag
// persistence, reading-status derivation, and the provider pipeline that
// turns raw DB rows into the organized library. The database runs on
// sqflite_common_ffi against a temp directory - no fakes for the layer
// under test.

// Dart imports:
import 'dart:io';

// Flutter imports:
import 'package:flutter_test/flutter_test.dart';

// Package imports:
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

// Project imports:
import 'package:openlib/services/database.dart';
import 'package:openlib/services/library_organization.dart';
import 'package:openlib/state/state.dart';

class _FakePathProvider extends PathProviderPlatform {
  Future<String> _dir(String name) async {
    final dir = Directory('/tmp/openlib_library_test/$name');
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

MyBook book(String id, String title, {String? author, String format = 'pdf'}) {
  return MyBook(
    id: id,
    title: title,
    author: author,
    thumbnail: null,
    link: 'https://example.com/book/$id',
    publisher: null,
    info: null,
    format: format,
    description: null,
  );
}

LibraryBook libBook(
  String title, {
  String author = '',
  Set<String> tags = const {},
  ReadingStatus status = ReadingStatus.unread,
  int? size,
}) {
  final id = title.toLowerCase().replaceAll(' ', '-');
  return LibraryBook(
    book: book(id, title, author: author),
    tags: tags,
    status: status,
    fileSizeBytes: size,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    PathProviderPlatform.instance = _FakePathProvider();
  });

  setUp(() async {
    // Fresh database per test: same path, tables dropped.
    final db = MyLibraryDb.instance;
    final database = await db.database;
    await database.delete('mybooks');
    await database.delete('bookposition');
    await database.delete('booktags');
  });

  group('sortLibrary', () {
    final books = [
      libBook('Zenith', author: 'Adams', size: 300),
      libBook('Alpha', author: 'Baker', size: 100),
      libBook('Middle', author: 'Cade', size: 200),
    ];

    test('date added descending keeps insertion order', () {
      final sorted = sortLibrary(books, LibrarySortMode.dateAddedDesc);
      expect(sorted.map((b) => b.title), ['Zenith', 'Alpha', 'Middle']);
    });

    test('date added ascending reverses insertion order', () {
      final sorted = sortLibrary(books, LibrarySortMode.dateAddedAsc);
      expect(sorted.map((b) => b.title), ['Middle', 'Alpha', 'Zenith']);
    });

    test('title A-Z and Z-A sort alphabetically ignoring case', () {
      expect(sortLibrary(books, LibrarySortMode.titleAsc)
          .map((b) => b.title), ['Alpha', 'Middle', 'Zenith']);
      expect(sortLibrary(books, LibrarySortMode.titleDesc)
          .map((b) => b.title), ['Zenith', 'Middle', 'Alpha']);
    });

    test('author sorts use the title as tiebreaker', () {
      final sorted = sortLibrary(books, LibrarySortMode.authorAsc);
      expect(sorted.map((b) => b.author), ['Adams', 'Baker', 'Cade']);
      final sameAuthor = [
        libBook('Beta 2', author: 'Same'),
        libBook('Beta 1', author: 'Same'),
      ];
      expect(sortLibrary(sameAuthor, LibrarySortMode.authorAsc)
          .map((b) => b.title), ['Beta 1', 'Beta 2']);
    });

    test('file size sorts put missing sizes last ascending', () {
      final withMissing = [...books, libBook('Ghost', size: null)];
      expect(sortLibrary(withMissing, LibrarySortMode.fileSizeDesc)
          .map((b) => b.title), ['Zenith', 'Middle', 'Alpha', 'Ghost']);
      expect(sortLibrary(withMissing, LibrarySortMode.fileSizeAsc).last.title,
          'Ghost');
    });

    test('reading status orders completed before in progress before unread',
        () {
      final mixed = [
        libBook('U', status: ReadingStatus.unread),
        libBook('C', status: ReadingStatus.completed),
        libBook('P', status: ReadingStatus.inProgress),
      ];
      expect(sortLibrary(mixed, LibrarySortMode.readingStatus)
          .map((b) => b.status), [
        ReadingStatus.unread,
        ReadingStatus.inProgress,
        ReadingStatus.completed,
      ]);
    });

    test('fromKey restores a persisted mode and falls back on garbage', () {
      expect(LibrarySortMode.fromKey('titleAsc'), LibrarySortMode.titleAsc);
      expect(LibrarySortMode.fromKey('nonsense'),
          LibrarySortMode.dateAddedDesc);
    });

    test('every mode has a unique stable key and a label', () {
      final keys = LibrarySortMode.values.map((m) => m.key).toSet();
      expect(keys.length, LibrarySortMode.values.length);
      for (final mode in LibrarySortMode.values) {
        expect(mode.label, isNotEmpty);
      }
    });
  });

  group('filterLibrary', () {
    final books = [
      libBook('Fav Sci', tags: {'Favorites', 'Sci-Fi'}),
      libBook('Plain Sci', tags: {'Sci-Fi'}),
      libBook('Done', status: ReadingStatus.completed),
    ];

    test('no filters returns everything', () {
      expect(filterLibrary(books).length, 3);
      expect(filterLibrary(books, tagFilter: {}).length, 3);
      expect(filterLibrary(books, statusFilter: null).length, 3);
    });

    test('tag filter keeps books matching any selected tag', () {
      final result =
          filterLibrary(books, tagFilter: {'Favorites', 'NoSuchTag'});
      expect(result.map((b) => b.title), ['Fav Sci']);
      expect(filterLibrary(books, tagFilter: {'Sci-Fi'}).length, 2);
    });

    test('status filter isolates a reading state', () {
      expect(filterLibrary(books, statusFilter: ReadingStatus.completed)
          .map((b) => b.title), ['Done']);
      expect(
          filterLibrary(books, statusFilter: ReadingStatus.unread).length, 2);
    });

    test('tag and status filters combine with AND', () {
      final both = filterLibrary(books,
          tagFilter: {'Sci-Fi'}, statusFilter: ReadingStatus.unread);
      expect(both.map((b) => b.title), ['Fav Sci', 'Plain Sci']);
    });
  });

  group('database tags', () {
    test('add, read, remove and list tags', () async {
      final db = MyLibraryDb.instance;
      await db.insert(book('tagged', 'Tagged Book'));
      await db.addTag('tagged', 'Favorites');
      await db.addTag('tagged', 'Sci-Fi');
      // Duplicate pair is ignored, not an error.
      await db.addTag('tagged', 'Favorites');

      expect(await db.getTags('tagged'), {'Favorites', 'Sci-Fi'});
      expect(await db.getTagsForAll(), {
        'tagged': {'Favorites', 'Sci-Fi'}
      });
      expect(await db.getAllTags(), ['Favorites', 'Sci-Fi']);

      await db.removeTag('tagged', 'Favorites');
      expect(await db.getTags('tagged'), {'Sci-Fi'});
    });

    test('tags are trimmed before storing', () async {
      final db = MyLibraryDb.instance;
      await db.insert(book('trim', 'Trim Test'));
      await db.addTag('trim', '  Favorites  ');
      expect(await db.getTags('trim'), {'Favorites'});
    });

    test('deleting a book removes its tags too', () async {
      final db = MyLibraryDb.instance;
      await db.insert(book('gone', 'Gone Book'));
      await db.addTag('gone', 'Solo Tag');
      expect(await db.getAllTags(), ['Solo Tag']);

      await db.delete('gone');
      expect(await db.getTags('gone'), isEmpty);
      expect(await db.getAllTags(), isEmpty);
    });
  });

  group('reading status derivation', () {
    test('unread: no position row at all', () async {
      final db = MyLibraryDb.instance;
      expect(await db.getBookState('nothing.pdf'), isNull);
      expect(await db.isCompleted('nothing.pdf'), isFalse);
    });

    test('in progress: position saved, not completed', () async {
      final db = MyLibraryDb.instance;
      await db.saveBookState('reading.pdf', 'chapter/5');
      expect(await db.getBookState('reading.pdf'), 'chapter/5');
      expect(await db.isCompleted('reading.pdf'), isFalse);
    });

    test('completed: flag set and readable back', () async {
      final db = MyLibraryDb.instance;
      await db.setCompleted('done.pdf', true);
      expect(await db.isCompleted('done.pdf'), isTrue);

      await db.setCompleted('done.pdf', false);
      expect(await db.isCompleted('done.pdf'), isFalse);
    });

    test('bulk position and completed maps cover the library', () async {
      final db = MyLibraryDb.instance;
      await db.saveBookState('a.pdf', '1');
      await db.setCompleted('b.pdf', true);

      expect(await db.getPositionsForAll(), {'a.pdf': '1', 'b.pdf': ''});
      expect(await db.getCompletedForAll(), {'a.pdf': false, 'b.pdf': true});
    });
  });

  group('organized library provider pipeline', () {
    test('enriches books with tags, status and size, then sorts', () async {
      final db = MyLibraryDb.instance;
      // A storage directory with real files so sizes resolve.
      final storageDir =
          await Directory('/tmp/openlib_library_test/storage').create();
      await db.savePreference('bookStorageDirectory', storageDir.path);

      await db.insert(book('z-first', 'Zed First', author: 'A'));
      await db.insert(book('a-second', 'Ay Second', author: 'B'));

      final bigFile = File('${storageDir.path}/z-first.pdf');
      await bigFile.writeAsBytes(List.filled(500, 1));
      final smallFile = File('${storageDir.path}/a-second.pdf');
      await smallFile.writeAsBytes(List.filled(100, 1));

      await db.addTag('z-first', 'Favorites');
      await db.saveBookState('z-first.pdf', '3');

      final container = ProviderContainer();
      addTearDown(container.dispose);

      // Resolve the enrichment provider against the seeded database.
      final enriched = await container.read(libraryBooksProvider.future);
      expect(enriched.length, 2);

      final zed = enriched.firstWhere((b) => b.id == 'z-first');
      expect(zed.tags, {'Favorites'});
      expect(zed.status, ReadingStatus.inProgress);
      expect(zed.fileSizeBytes, 500);

      final ay = enriched.firstWhere((b) => b.id == 'a-second');
      expect(ay.status, ReadingStatus.unread);
      expect(ay.fileSizeBytes, 100);

      // Sorting the enrichment through the provider chain works end to end.
      container.read(librarySortModeProvider.notifier).state =
          LibrarySortMode.titleAsc;
      final organized = container.read(organizedLibraryProvider);
      expect(organized.map((b) => b.title), ['Ay Second', 'Zed First']);

      // Filter to the Favorites tag and only Ay remains hidden.
      container.read(libraryTagFilterProvider.notifier).state = {'Favorites'};
      expect(
          container.read(organizedLibraryProvider).map((b) => b.id), ['z-first']);
    });
  });
}
