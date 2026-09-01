// Dart imports:
import 'dart:convert';
import 'dart:io';

// Flutter imports:
import 'package:flutter/foundation.dart';

// Package imports:
import 'package:sqflite/sqflite.dart' as sqflite;

// Project imports:
import 'package:openlib/services/database.dart';
import 'package:openlib/services/logger.dart';

/// Creates and restores full JSON backups of the app's local data:
/// preferences (settings, instance list, donation key, storage paths),
/// saved books and their reading positions, and the browser options.
///
/// The format is one JSON object with a version, so future schema
/// changes can migrate old backups instead of guessing.
class BackupService {
  BackupService({MyLibraryDb? database, sqflite.DatabaseFactory? factory})
      : _database = database ?? MyLibraryDb.instance;

  final MyLibraryDb _database;

  static const formatVersion = 1;

  /// Serializes everything user-controlled into a backup JSON string.
  Future<String> createBackupJson() async {
    final db = await _database.database;

    final preferences = await db.query('preferences');
    final books = await db.query('mybooks');
    final bookPositions = await db.query('bookposition');
    final browserOptions = await db.query('browserOptions');
    final bookTags = await db.query('booktags');

    String? encode(List<Map<String, Object?>> rows) =>
        jsonEncode(rows.map((row) {
          return row.map(
              (k, v) => MapEntry(k, v is bool ? v.toString() : v?.toString()));
        }).toList());

    final backup = {
      'format': 'openlib-backup',
      'version': formatVersion,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
      'preferences': jsonDecode(encode(preferences)!),
      'books': jsonDecode(encode(books)!),
      'bookPositions': jsonDecode(encode(bookPositions)!),
      'browserOptions': jsonDecode(encode(browserOptions)!),
      'bookTags': jsonDecode(encode(bookTags)!),
    };

    return const JsonEncoder.withIndent('  ').convert(backup);
  }

  /// Validates that [json] is a backup this app wrote (or a compatible
  /// future version). Returns the parsed map or null when unusable.
  Map<String, dynamic>? validateBackup(String json) {
    try {
      final parsed = jsonDecode(json);
      if (parsed is! Map<String, dynamic>) return null;
      if (parsed['format'] != 'openlib-backup') return null;
      final version = parsed['version'];
      if (version is! int || version > formatVersion) return null;
      return parsed;
    } catch (_) {
      return null;
    }
  }

  /// Restores a backup: replaces the current data. Values are stored as
  /// strings in the backup and written back exactly as sqlite expects.
  Future<bool> restoreBackupJson(String json) async {
    final backup = validateBackup(json);
    if (backup == null) return false;

    final db = await _database.database;

    // All-or-nothing: a half-restored database is worse than none.
    await db.transaction((txn) async {
      await _restoreTable(
          txn, 'preferences', backup['preferences'], ['name', 'value']);
      await _restoreTable(txn, 'mybooks', backup['books'], [
        'id',
        'title',
        'author',
        'thumbnail',
        'link',
        'publisher',
        'info',
        'format',
        'description',
        'fileName'
      ]);
      await _restoreTable(txn, 'bookposition', backup['bookPositions'],
          ['fileName', 'position', 'completed']);
      await _restoreTable(
          txn, 'browserOptions', backup['browserOptions'], ['name', 'value']);
      // Older backups predate tags; restore nothing rather than fail.
      await _restoreTable(
          txn, 'booktags', backup['bookTags'], ['bookId', 'tag']);
    });

    AppLogger().info('Backup restored',
        tag: 'BackupService', metadata: {'books': backup['books']?.length});
    return true;
  }

  Future<void> _restoreTable(sqflite.DatabaseExecutor txn, String table,
      dynamic rows, List<String> columns) async {
    if (rows is! List) return;

    await txn.delete(table);
    for (final row in rows) {
      if (row is! Map) continue;
      final values = <String, Object?>{};
      for (final column in columns) {
        final value = row[column];
        // Everything is TEXT in these tables; nulls stay null.
        values[column] = value?.toString();
      }
      // A row missing its primary key cannot be inserted.
      if (values.values.isEmpty) continue;
      try {
        await txn.insert(table, values,
            conflictAlgorithm: sqflite.ConflictAlgorithm.replace);
      } catch (e) {
        // A malformed row (e.g. missing PK) is skipped, not fatal - the
        // transaction continues with the rest of the backup.
        debugPrint('Backup row skipped for $table: $e');
      }
    }
  }

  /// Writes the backup to [path] on disk.
  Future<File> writeBackupFile(String path) async {
    final json = await createBackupJson();
    final file = File(path);
    return file.writeAsString(json);
  }

  /// Reads and restores a backup file from [path].
  Future<bool> restoreBackupFile(String path) async {
    final file = File(path);
    if (!await file.exists()) return false;
    final json = await file.readAsString();
    return restoreBackupJson(json);
  }
}
