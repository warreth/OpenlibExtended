// Dart imports:
import 'dart:io';

// Package imports:
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

// Project imports:
import 'package:openlib/services/files.dart';
import 'package:openlib/core/book_description.dart';
import 'package:openlib/services/reading_status.dart';

class MyBook {
  final String id;
  final String title;
  final String? author;
  final String? thumbnail;
  final String link;
  final String? publisher;
  final String? info;
  final String? description;
  final String? format;
  final String? fileName;

  MyBook(
      {required this.id,
      required this.title,
      required this.author,
      required this.thumbnail,
      required this.link,
      required this.publisher,
      required this.info,
      required this.format,
      required this.description,
      this.fileName});

  // Getter for compatibility with BookInfoWidget which expects 'md5'
  String get md5 => id;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'author': author,
      'thumbnail': thumbnail,
      'link': link,
      'publisher': publisher,
      'info': info,
      'format': format,
      'description': normalizedBookDescription(description),
      'fileName': fileName
    };
  }

  @override
  String toString() {
    return 'MyBook{id: $id,title: $title,author: $author,thumbnail: $thumbnail,link: $link,publisher: $publisher,info: $info,format: $format,description:$description,fileName:$fileName}';
  }

  // Get actual filename - uses fileName if available, otherwise falls back to id.format
  String getFileName() {
    if (fileName != null && fileName!.isNotEmpty) {
      return fileName!;
    }
    return "$id.$format";
  }
}

class MyLibraryDb {
  static final MyLibraryDb instance = MyLibraryDb._internal();
  static Database? _database;
  MyLibraryDb._internal();

  Future<Database> get database async {
    if (_database != null) {
      return _database!;
    }
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    String databasePath;
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      final directory = await getApplicationSupportDirectory();
      databasePath = directory.path;
      try {
        await Directory(databasePath).create(recursive: true);
      } catch (_) {}
    } else {
      databasePath = await getDatabasesPath();
    }
    final path = join(databasePath, 'mylibrary.db');

    return await openDatabase(
      path,
      version: 8,
      onCreate: (Database db, int version) async {
        await db.execute(
            'CREATE TABLE mybooks (id TEXT PRIMARY KEY, title TEXT,author TEXT,thumbnail TEXT,link TEXT,publisher TEXT,info TEXT,format TEXT,description TEXT,fileName TEXT)');
        await db.execute(
            'CREATE TABLE preferences (name TEXT PRIMARY KEY,value TEXT)');
        // Create these tables for all platforms (both mobile and desktop)
        await db.execute(
            'CREATE TABLE bookposition (fileName TEXT PRIMARY KEY,position TEXT,completed INTEGER DEFAULT 0,manualStatus TEXT)');
        await db.execute(
            'CREATE TABLE browserOptions (name TEXT PRIMARY KEY,value TEXT)');
        await db.execute(
            'CREATE TABLE booktags (bookId TEXT,tag TEXT,PRIMARY KEY (bookId,tag))');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        List<dynamic> isTableExist = await db.query('sqlite_master',
            where: 'name = ?', whereArgs: ['bookposition']);
        List<dynamic> isPreferenceTableExist = await db.query('sqlite_master',
            where: 'name = ?', whereArgs: ['preferences']);
        List<dynamic> isbrowserOptionsExist = await db.query('sqlite_master',
            where: 'name = ?', whereArgs: ['browserOptions']);
        if (isPreferenceTableExist.isEmpty) {
          await db.execute(
              'CREATE TABLE preferences (name TEXT PRIMARY KEY,value TEXT)');
        }
        // Create bookposition table on all platforms if not exists
        if (isTableExist.isEmpty) {
          await db.execute(
              'CREATE TABLE bookposition (fileName TEXT PRIMARY KEY,position TEXT,completed INTEGER DEFAULT 0,manualStatus TEXT)');
        }
        // Create browserOptions table on all platforms if not exists
        if (isbrowserOptionsExist.isEmpty) {
          await db.execute(
              'CREATE TABLE browserOptions (name TEXT PRIMARY KEY,value TEXT)');
        }
        // Add fileName column if upgrading from version < 6
        if (oldVersion < 6) {
          try {
            await db.execute('ALTER TABLE mybooks ADD COLUMN fileName TEXT');
          } catch (_) {
            // Column might already exist
          }
        }
        // Tags and reading completion arrive with schema v7
        if (oldVersion < 7) {
          final hasTags = await db.query('sqlite_master',
              where: 'name = ?', whereArgs: ['booktags']);
          if (hasTags.isEmpty) {
            await db.execute(
                'CREATE TABLE booktags (bookId TEXT,tag TEXT,PRIMARY KEY (bookId,tag))');
          }
          try {
            await db.execute(
                'ALTER TABLE bookposition ADD COLUMN completed INTEGER DEFAULT 0');
          } catch (_) {
            // Column might already exist
          }
        }
        // Manual reading-status overrides arrive with schema v8.
        if (oldVersion < 8) {
          try {
            await db.execute(
                'ALTER TABLE bookposition ADD COLUMN manualStatus TEXT');
          } catch (_) {
            // Column might already exist
          }
        }
      },
      onOpen: (db) async {
        final bookStorageDefaultDirectory =
            await getBookStorageDefaultDirectory;
        await db.execute(
            "INSERT OR IGNORE INTO preferences (name, value) VALUES ('darkMode', 0)");
        await db.execute(
            "INSERT OR IGNORE INTO preferences (name, value) VALUES ('themeMode', 'system')");
        await db.execute(
            "INSERT OR IGNORE INTO preferences (name, value) VALUES ('openPdfwithExternalApp', 0)");
        await db.execute(
            "INSERT OR IGNORE INTO preferences (name, value) VALUES ('openEpubwithExternalApp', 0)");
        await db.execute(
            "INSERT OR IGNORE INTO preferences (name, value) VALUES ('bookStorageDirectory', '$bookStorageDefaultDirectory')");
        await db.execute(
            "INSERT OR IGNORE INTO preferences (name, value) VALUES ('showManualDownloadButton', 0)");
      },
    );
  }

  // Database dbInstance;
  String tableName = 'mybooks';

  Future<void> insert(MyBook book) async {
    final dbInstance = await instance.database;
    await dbInstance.insert(
      tableName,
      book.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Fills only absent metadata, preserving the book record, file and progress.
  Future<void> saveMissingDescription(String id, String description) async {
    final normalized = normalizedBookDescription(description);
    if (normalized == null) return;
    final dbInstance = await instance.database;
    await dbInstance.update(
      tableName,
      {'description': normalized},
      where: "id = ? AND (description IS NULL OR trim(description) = '' "
          "OR lower(trim(description)) = 'null')",
      whereArgs: [id],
    );
  }

  Future<void> delete(String id) async {
    final dbInstance = await instance.database;
    await dbInstance.delete(
      'booktags',
      where: 'bookId = ?',
      whereArgs: [id],
    );
    await dbInstance.delete(
      tableName,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<MyBook?> getId(String id) async {
    final dbInstance = await instance.database;
    List<Map<String, dynamic>> data =
        await dbInstance.query(tableName, where: 'id = ?', whereArgs: [id]);
    List<MyBook> book = listMapToMyBook(data);
    if (book.isNotEmpty) {
      return book.first;
    }
    return null;
  }

  Future<bool> checkIdExists(String id) async {
    final dbInstance = await instance.database;
    List<Map<String, dynamic>> data =
        await dbInstance.query(tableName, where: 'id = ?', whereArgs: [id]);
    List<MyBook> book = listMapToMyBook(data);
    if (book.isNotEmpty) {
      return true;
    }
    return false;
  }

  Future<List<MyBook>> getAll() async {
    final dbInstance = await instance.database;
    final List<Map<String, dynamic>> maps = await dbInstance.query(tableName);
    return listMapToMyBook(maps);
  }

  List<MyBook> listMapToMyBook(List<Map<String, dynamic>> maps) {
    List<MyBook> myBookList = List.generate(maps.length, (i) {
      return MyBook(
          id: maps[i]['id'],
          title: maps[i]['title'],
          author: maps[i]['author'],
          thumbnail: maps[i]['thumbnail'],
          link: maps[i]['link'],
          publisher: maps[i]['publisher'],
          info: maps[i]['info'],
          format: maps[i]['format'],
          description:
              normalizedBookDescription(maps[i]['description'] as String?),
          fileName: maps[i]['fileName']);
    });
    return myBookList.reversed.toList();
  }

  /// Stores reader progress without disturbing a manual Completed mark or
  /// the completed flag. Replacing the row used to wipe both. A manual
  /// Unread or In Progress mark is no longer needed once progress exists.
  Future<void> saveBookState(String fileName, String position) async {
    final dbInstance = await instance.database;
    final updated = await dbInstance.rawUpdate(
      "UPDATE bookposition SET position = ?, "
      "manualStatus = CASE WHEN manualStatus = 'completed' "
      "THEN manualStatus ELSE NULL END "
      "WHERE fileName = ?",
      [position, fileName],
    );
    if (updated == 0) {
      await dbInstance.insert(
        'bookposition',
        {'fileName': fileName, 'position': position},
      );
    }
  }

  // ------------------------------------------------------------------
  // Tags: user-defined collections a book can belong to ('Favorites',
  // 'Sci-Fi', 'To Read', ...). One book, many tags; one tag, many books.
  // ------------------------------------------------------------------

  /// Assigns one tag to a book. Adding an existing pair is a no-op.
  Future<void> addTag(String bookId, String tag) async {
    final dbInstance = await instance.database;
    await dbInstance.insert(
      'booktags',
      {'bookId': bookId, 'tag': tag.trim()},
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  /// Removes one tag from a book.
  Future<void> removeTag(String bookId, String tag) async {
    final dbInstance = await instance.database;
    await dbInstance.delete(
      'booktags',
      where: 'bookId = ? AND tag = ?',
      whereArgs: [bookId, tag],
    );
  }

  /// All tags of one book.
  Future<Set<String>> getTags(String bookId) async {
    final dbInstance = await instance.database;
    final rows = await dbInstance
        .query('booktags', where: 'bookId = ?', whereArgs: [bookId]);
    return rows.map((r) => r['tag'].toString()).toSet();
  }

  /// Every distinct tag in use, sorted alphabetically.
  Future<List<String>> getAllTags() async {
    final dbInstance = await instance.database;
    final rows = await dbInstance.query('booktags',
        columns: ['tag'], groupBy: 'tag', orderBy: 'tag COLLATE NOCASE');
    return rows.map((r) => r['tag'].toString()).toList();
  }

  /// Map of bookId to its tag set, in one query - used to enrich the
  /// whole library without N+1 lookups.
  Future<Map<String, Set<String>>> getTagsForAll() async {
    final dbInstance = await instance.database;
    final rows = await dbInstance.query('booktags');
    final map = <String, Set<String>>{};
    for (final row in rows) {
      map
          .putIfAbsent(row['bookId'].toString(), () => {})
          .add(row['tag'].toString());
    }
    return map;
  }

  // ------------------------------------------------------------------
  // Reading status: a manual choice (manualStatus) wins over automatic
  // tracking; otherwise completed means Completed, a saved position means
  // In Progress, and no position means Unread.
  // ------------------------------------------------------------------

  /// Applies a manual status to one book.
  ///
  /// Unread is the reset: it clears the saved position so the reader opens
  /// at the start again. In Progress and Completed keep the position so a
  /// finished book does not lose where the reader left off.
  Future<void> setReadingStatus(String fileName, ReadingStatus status) async {
    final dbInstance = await instance.database;
    final rows = await dbInstance.query(
      'bookposition',
      columns: ['position'],
      where: 'fileName = ?',
      whereArgs: [fileName],
      limit: 1,
    );
    final position =
        rows.isEmpty ? '' : (rows.first['position']?.toString() ?? '');
    await dbInstance.insert(
      'bookposition',
      {
        'fileName': fileName,
        'position': status == ReadingStatus.unread ? '' : position,
        'completed': status == ReadingStatus.completed ? 1 : 0,
        'manualStatus': status.key,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// The status of one book, manual choice included.
  Future<ReadingStatus> getReadingStatus(String fileName) async {
    final dbInstance = await instance.database;
    final rows = await dbInstance.query(
      'bookposition',
      where: 'fileName = ?',
      whereArgs: [fileName],
      limit: 1,
    );
    if (rows.isEmpty) return ReadingStatus.unread;
    final row = rows.first;
    return readingStatusFrom(
      manualStatus: row['manualStatus'],
      position: row['position'],
      completed: row['completed'],
    );
  }

  /// Marks (or unmarks) a book as finished without discarding the saved
  /// position. Unmarking leaves a book with progress In Progress.
  Future<void> setCompleted(String fileName, bool completed) async {
    if (completed) {
      await setReadingStatus(fileName, ReadingStatus.completed);
      return;
    }
    final position = await getBookState(fileName);
    await setReadingStatus(
      fileName,
      position == null || position.isEmpty
          ? ReadingStatus.unread
          : ReadingStatus.inProgress,
    );
  }

  /// True when the book is flagged completed.
  Future<bool> isCompleted(String fileName) async {
    final dbInstance = await instance.database;
    final rows = await dbInstance
        .query('bookposition', where: 'fileName = ?', whereArgs: [fileName]);
    if (rows.isEmpty) return false;
    return rows.first['completed'] == 1;
  }

  /// Map of fileName to saved position for the whole library - used
  /// to derive reading status without N+1 lookups.
  Future<Map<String, String?>> getPositionsForAll() async {
    final dbInstance = await instance.database;
    final rows = await dbInstance.query('bookposition');
    return {
      for (final row in rows)
        row['fileName'].toString(): row['position']?.toString()
    };
  }

  /// Map of fileName to completed flag for the whole library.
  Future<Map<String, bool>> getCompletedForAll() async {
    final dbInstance = await instance.database;
    final rows = await dbInstance.query('bookposition');
    return {
      for (final row in rows) row['fileName'].toString(): row['completed'] == 1
    };
  }

  /// Map of fileName to resolved reading status for the whole library -
  /// used to enrich the library without N+1 lookups.
  Future<Map<String, ReadingStatus>> getStatusesForAll() async {
    final dbInstance = await instance.database;
    final rows = await dbInstance.query('bookposition');
    return {
      for (final row in rows)
        row['fileName'].toString(): readingStatusFrom(
          manualStatus: row['manualStatus'],
          position: row['position'],
          completed: row['completed'],
        )
    };
  }

  Future<void> deleteBookState(String fileName) async {
    final dbInstance = await instance.database;
    await dbInstance.delete(
      'bookposition',
      where: 'fileName = ?',
      whereArgs: [fileName],
    );
  }

  Future<String?> getBookState(String fileName) async {
    final dbInstance = await instance.database;
    List<Map<String, dynamic>> data = await dbInstance
        .query('bookposition', where: 'fileName = ?', whereArgs: [fileName]);
    List<dynamic> dataList = List.generate(data.length, (i) {
      return {'fileName': data[i]['fileName'], 'position': data[i]['position']};
    });
    if (dataList.isNotEmpty) {
      return dataList[0]['position'];
    } else {
      return null;
    }
  }

  Future<void> savePreference(String name, dynamic value) async {
    switch (value) {
      case bool _:
        value = value ? 1 : 0;
        break;
      case int _ || String _:
        break;
      default:
        throw 'Invalid type';
    }
    Database dbInstance = await instance.database;
    await dbInstance.insert(
      'preferences',
      {'name': name, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<dynamic> getPreference(String name) async {
    Database dbInstance = await instance.database;
    List<Map<String, dynamic>> data = await dbInstance
        .query('preferences', where: 'name = ?', whereArgs: [name]);
    List<dynamic> dataList = List.generate(data.length, (i) {
      return {'name': data[i]['name'], 'value': data[i]['value']};
    });
    if (dataList.isNotEmpty) {
      // Convert to int if possible
      int? preference = int.tryParse(dataList[0]['value']);
      if (preference != null) {
        return preference;
      }
      // Return string value if not int
      return dataList[0]['value'];
    }
    throw "Preference $name not found";
  }

  Future<void> setBrowserOptions(String name, String value) async {
    final dbInstance = await instance.database;
    await dbInstance.insert(
      'browserOptions',
      {'name': name, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<String> getBrowserOptions(String name) async {
    final dbInstance = await instance.database;
    List<Map<String, dynamic>> data = await dbInstance
        .query('browserOptions', where: 'name = ?', whereArgs: [name]);
    List<dynamic> dataList = List.generate(data.length, (i) {
      return {'name': data[i]['name'], 'value': data[i]['value']};
    });
    if (dataList.isNotEmpty) {
      return dataList[0]['value'];
    } else {
      return "";
    }
  }
}
