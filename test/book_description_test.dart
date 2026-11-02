import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:openlib/l10n/app_localizations.dart';
import 'package:openlib/services/database.dart';
import 'package:openlib/services/library_book_details.dart';
import 'package:openlib/state/state.dart';
import 'package:openlib/ui/components/book_info_widget.dart';
import 'package:openlib/ui/mybook_page.dart';

class _Paths extends PathProviderPlatform {
  final root = Directory.systemTemp.createTempSync('openlib_description_');
  @override
  Future<String?> getApplicationSupportPath() async => root.path;
  @override
  Future<String?> getApplicationDocumentsPath() async => root.path;
  @override
  Future<String?> getTemporaryPath() async => root.path;
  @override
  Future<String?> getLibraryPath() async => root.path;
}

MyBook _book({String? description}) => MyBook(
      id: 'german-pihkal',
      title: 'PiHKAL',
      author: 'Alexander Shulgin',
      thumbnail: '',
      link: 'https://z-lib.gd/book/german-pihkal/pihkal.html',
      publisher: 'Nachtschatten',
      info: 'German, EPUB',
      format: 'epub',
      description: description,
      fileName: 'my-german-book.epub',
    );

class _PendingDetails extends LibraryBookDetails {
  final pending = Completer<MyBook?>();
  int loadCount = 0;
  int refreshCount = 0;
  @override
  Future<MyBook?> load(String id) async {
    loadCount++;
    return _book();
  }

  @override
  Future<MyBook?> refreshDescription(MyBook book) {
    refreshCount++;
    return pending.future;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final paths = _Paths();
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    PathProviderPlatform.instance = paths;
    await MyLibraryDb.instance.database;
  });

  for (final missing in <String?>[null, '', '  ', 'null', ' NULL ']) {
    testWidgets('missing description $missing never renders null',
        (tester) async {
      await tester.pumpWidget(ProviderScope(
        overrides: [
          annaArchiveBaseUrlProvider.overrideWith((ref) async => null)
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
              body: BookInfoWidget(
                  data: _book(description: missing), child: const SizedBox())),
        ),
      ));
      await tester.pump();
      expect(find.text('No description available'), findsOneWidget);
      expect(find.text('null'), findsNothing);
    });
  }

  test(
      'saved missing description is repaired without replacing other book data',
      () async {
    final database = MyLibraryDb.instance;
    final book = _book();
    await database.insert(book);
    await database.saveBookState(book.getFileName(), 'saved-position');
    await database.addTag(book.id, 'Favorites');
    final service = LibraryBookDetails(fetchDescription: (url) async {
      expect(url, book.link);
      return 'Der deutsche Klappentext.';
    });
    final updated = await service.refreshDescription(book);
    expect(updated!.description, 'Der deutsche Klappentext.');
    expect(updated.toMap(),
        {...book.toMap(), 'description': 'Der deutsche Klappentext.'});
    expect((await database.getId(book.id))!.description, updated.description);
    expect(await database.getBookState(book.getFileName()), 'saved-position');
    expect((await database.getTagsForAll())[book.id], {'Favorites'});
  });

  test('existing descriptions are neither fetched nor overwritten', () async {
    final book = _book(description: 'Original blurb.');
    final service = LibraryBookDetails(
        fetchDescription: (_) async => throw StateError('must not fetch'));
    expect(await service.refreshDescription(book), isNull);
  });

  test('failed metadata fetch preserves local record', () async {
    final book = _book();
    await MyLibraryDb.instance.insert(book);
    final service = LibraryBookDetails(
        fetchDescription: (_) async => throw const SocketException('offline'));
    expect(await service.refreshDescription(book), isNull);
    expect((await MyLibraryDb.instance.getId(book.id))!.toMap(), book.toMap());
  });

  testWidgets('local Open stays available while missing description loads once',
      (tester) async {
    final service = _PendingDetails();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        libraryBookDetailsProvider.overrideWithValue(service),
        annaArchiveBaseUrlProvider.overrideWith((ref) async => null),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const BookPage(id: 'german-pihkal'),
      ),
    ));
    await tester.pump();
    await tester.pump();
    expect(find.text('Open'), findsOneWidget);
    final open =
        tester.widget<TextButton>(find.widgetWithText(TextButton, 'Open'));
    expect(open.onPressed, isNotNull);
    expect(find.text('No description available'), findsOneWidget);
    service.pending.complete(_book(description: 'Recovered blurb.'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Recovered blurb.'), findsOneWidget);
    expect(service.loadCount, 1);
    expect(service.refreshCount, 1);
  });
}
