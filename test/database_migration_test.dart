// A library database written by schema v7 must open at v8 with the
// manualStatus column added and its saved positions intact. This is the
// upgrade path an existing install takes after this feature ships.

// Dart imports:
import 'dart:io';

// Flutter imports:
import 'package:flutter_test/flutter_test.dart';

// Package imports:
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

// Project imports:
import 'package:openlib/services/database.dart';
import 'package:openlib/services/reading_status.dart';

class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.support);

  final String support;

  @override
  Future<String?> getApplicationSupportPath() async => support;

  @override
  Future<String?> getApplicationDocumentsPath() async => support;

  @override
  Future<String?> getTemporaryPath() async => support;

  @override
  Future<String?> getLibraryPath() async => support;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    root =
        await Directory('/tmp/openlib_migration_test').create(recursive: true);
    PathProviderPlatform.instance = _FakePathProvider(root.path);
  });

  test('v7 bookposition upgrades in place and keeps saved progress', () async {
    final path = p.join(root.path, 'mylibrary.db');
    final oldFile = File(path);
    if (await oldFile.exists()) await oldFile.delete();

    final v7 = await databaseFactory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 7,
        onCreate: (db, version) async {
          await db.execute(
              'CREATE TABLE mybooks (id TEXT PRIMARY KEY, title TEXT,author TEXT,thumbnail TEXT,link TEXT,publisher TEXT,info TEXT,format TEXT,description TEXT,fileName TEXT)');
          await db.execute(
              'CREATE TABLE preferences (name TEXT PRIMARY KEY,value TEXT)');
          await db.execute(
              'CREATE TABLE bookposition (fileName TEXT PRIMARY KEY,position TEXT,completed INTEGER DEFAULT 0)');
          await db.execute(
              'CREATE TABLE browserOptions (name TEXT PRIMARY KEY,value TEXT)');
          await db.execute(
              'CREATE TABLE booktags (bookId TEXT,tag TEXT,PRIMARY KEY (bookId,tag))');
        },
      ),
    );
    await v7.insert('bookposition', {
      'fileName': 'half-read.pdf',
      'position': '42',
      'completed': 0,
    });
    await v7.close();

    // Opening through the app runs onUpgrade to schema v8.
    final db = await MyLibraryDb.instance.database;
    final columns = await db.rawQuery('PRAGMA table_info(bookposition)');
    expect(columns.map((column) => column['name']), contains('manualStatus'));

    expect(await MyLibraryDb.instance.getBookState('half-read.pdf'), '42');
    expect(await MyLibraryDb.instance.getReadingStatus('half-read.pdf'),
        ReadingStatus.inProgress);

    // The new manual override works on the migrated file.
    await MyLibraryDb.instance
        .setReadingStatus('half-read.pdf', ReadingStatus.completed);
    expect(await MyLibraryDb.instance.getReadingStatus('half-read.pdf'),
        ReadingStatus.completed);
    expect(await MyLibraryDb.instance.getBookState('half-read.pdf'), '42');
  });
}
