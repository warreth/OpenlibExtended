// The manual reading-status flow, from the picker control to both places
// a user can reach it: the library's long-press sheet and a book's page.
// The database is real (sqflite FFI on a temp directory), so a tap must
// leave the status persisted, not just repaint a chip.

// Dart imports:
import 'dart:io';

// Flutter imports:
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Package imports:
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

// Project imports:
import 'package:openlib/l10n/app_localizations.dart';
import 'package:openlib/services/database.dart';
import 'package:openlib/services/library_book_details.dart';
import 'package:openlib/services/library_organization.dart';
import 'package:openlib/services/reading_status.dart';
import 'package:openlib/state/state.dart'
    show
        activeDownloadsProvider,
        annaArchiveBaseUrlProvider,
        libraryBooksProvider,
        libraryTagsProvider;
import 'package:openlib/ui/components/book_manage_sheet.dart';
import 'package:openlib/ui/components/reading_status_selector.dart';
import 'package:openlib/ui/mybook_page.dart';
import 'package:openlib/ui/mylibrary_page.dart';

class _FakePathProvider extends PathProviderPlatform {
  Future<String> _dir(String name) async {
    final dir = Directory('/tmp/openlib_reading_status_ui/$name');
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

MyBook testBook(String id, String title, {String? fileName}) {
  return MyBook(
    id: id,
    title: title,
    author: 'A. Writer',
    thumbnail: null,
    link: 'https://example.com/book/$id',
    publisher: 'Test Press',
    info: 'English, PDF',
    format: 'pdf',
    description: 'A book used by the reading-status UI tests.',
    fileName: fileName,
  );
}

class _FakeBookDetails extends LibraryBookDetails {
  _FakeBookDetails(this.book) : super(fetchDescription: (_) async => null);

  final MyBook book;

  @override
  Future<MyBook?> load(String id) async => book;
}

Widget localized(Widget child) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: child,
  );
}

Future<void> _pumpFrames(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    PathProviderPlatform.instance = _FakePathProvider();
  });

  setUp(() async {
    final db = MyLibraryDb.instance;
    final database = await db.database;
    await database.delete('mybooks');
    await database.delete('bookposition');
    await database.delete('booktags');
  });

  testWidgets('status selector shows every choice and reports the tapped one',
      (tester) async {
    ReadingStatus? selected;
    await tester.pumpWidget(localized(Scaffold(
      body: ReadingStatusSelector(
        status: ReadingStatus.unread,
        onChanged: (status) => selected = status,
      ),
    )));

    expect(find.text('Unread'), findsOneWidget);
    expect(find.text('In Progress'), findsOneWidget);
    expect(find.text('Completed'), findsOneWidget);

    await tester.tap(find.text('Completed'));
    expect(selected, ReadingStatus.completed);
  });

  testWidgets('library sheet saves a manual status and keeps the position',
      (tester) async {
    final db = MyLibraryDb.instance;
    await tester.runAsync(() async {
      await db.insert(testBook('manage', 'Manage Book'));
      await db.saveBookState('manage.pdf', 'chapter/4');
    });
    await tester.pumpWidget(ProviderScope(
      child: localized(Scaffold(
        body: BookManageSheet(
          bookId: 'manage',
          fileName: 'manage.pdf',
          title: 'Manage Book',
          initialStatus: ReadingStatus.inProgress,
        ),
      )),
    ));
    await _pumpFrames(tester);
    expect(find.text('Reading status'), findsOneWidget);
    expect(find.text('Collections'), findsOneWidget);
    expect(find.text('In Progress'), findsOneWidget);

    await tester.tap(find.text('Completed'));
    await _pumpFrames(tester);
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)));
    await _pumpFrames(tester);
    await tester.runAsync(() async {
      expect(await db.getReadingStatus('manage.pdf'), ReadingStatus.completed);
      expect(await db.getBookState('manage.pdf'), 'chapter/4');
    });
    final chip =
        tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Completed'));
    expect(chip.selected, isTrue);
  });

  testWidgets('book page menu marks a book completed and confirms it',
      (tester) async {
    final db = MyLibraryDb.instance;
    final book = testBook('menu', 'Menu Book');
    await tester.runAsync(() async {
      await db.insert(book);
      await db.saveBookState('menu.pdf', '12');
    });

    await tester.pumpWidget(ProviderScope(
      overrides: [
        annaArchiveBaseUrlProvider.overrideWith((ref) async => null),
        libraryBookDetailsProvider.overrideWithValue(_FakeBookDetails(book)),
      ],
      child: localized(const BookPage(id: 'menu')),
    ));
    await _pumpFrames(tester);

    expect(find.text('Menu Book'), findsOneWidget);
    await tester.tap(find.byTooltip('Reading status'));
    await _pumpFrames(tester);
    await tester.tap(find.text('Completed'));
    await _pumpFrames(tester);

    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)));
    await _pumpFrames(tester);
    await tester.runAsync(() async {
      expect(await db.getReadingStatus('menu.pdf'), ReadingStatus.completed);
      expect(await db.getBookState('menu.pdf'), '12');
    });
    expect(find.text('Marked as Completed'), findsOneWidget);
  });

  testWidgets('long-pressing a library card opens the same status sheet',
      (tester) async {
    final db = MyLibraryDb.instance;
    final book = testBook('library', 'Library Book');
    final library = [
      LibraryBook(book: book, status: ReadingStatus.unread),
    ];

    await tester.pumpWidget(ProviderScope(
      overrides: [
        libraryBooksProvider.overrideWith((ref) async => library),
        libraryTagsProvider.overrideWith((ref) async => <String>{}),
        activeDownloadsProvider.overrideWith((ref) => const Stream.empty()),
      ],
      child: localized(const Scaffold(body: MyLibraryPage())),
    ));
    await _pumpFrames(tester);

    expect(find.text('Library Book'), findsOneWidget);
    await tester.longPress(find.text('Library Book'));
    await _pumpFrames(tester);

    expect(find.text('Reading status'), findsOneWidget);
    await tester.tap(find.text('Completed'));
    await _pumpFrames(tester);

    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.runAsync(() async {
      expect(await db.getReadingStatus('library.pdf'), ReadingStatus.completed);
    });
  });
}
