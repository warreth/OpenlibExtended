// The share flow resolves the real book file when the book is
// downloaded: these tests run the resolver against the actual storage
// preference and disk, so "downloaded shares the file, missing shares
// the link" is genuinely covered.

// Dart imports:
import 'dart:io';

// Flutter imports:
import 'package:flutter_test/flutter_test.dart';

// Package imports:
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

// Project imports:
import 'package:openlib/services/database.dart';
import 'package:openlib/services/share_book.dart' show findBookFileForTesting;

class _FakePathProvider extends PathProviderPlatform {
  Future<String> _dir(String name) async {
    final dir = Directory('/tmp/openlib_share_test/$name');
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

  setUpAll(() {
    if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      PathProviderPlatform.instance = _FakePathProvider();
    }
  });

  test('a downloaded book resolves to its file on disk', () async {
    final storage = await _FakePathProvider().getTemporaryPath();
    await MyLibraryDb.instance.savePreference('bookStorageDirectory', storage);

    final book = File('$storage/Some Great Book-ab12cd34.epub')
      ..writeAsBytesSync(List.filled(64, 3));

    final resolved =
        await findBookFileForTesting('Some Great Book-ab12cd34.epub', 'epub');
    expect(resolved, isNotNull);
    expect(resolved!.path, book.path);
  });

  test('a book that is not downloaded resolves to nothing', () async {
    final storage = await _FakePathProvider().getTemporaryPath();
    await MyLibraryDb.instance.savePreference('bookStorageDirectory', storage);

    expect(await findBookFileForTesting('Missing Book.epub', 'epub'), isNull);
  });

  test('a missing storage preference resolves to nothing, not an error',
      () async {
    final db = await MyLibraryDb.instance.database;
    await db.delete('preferences',
        where: 'name = ?', whereArgs: ['bookStorageDirectory']);

    expect(await findBookFileForTesting('Whatever.epub', 'epub'), isNull);
  });
}
