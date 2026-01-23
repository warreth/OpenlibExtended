// Dart imports:
import 'dart:io';

// Package imports:
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

// Project imports:
import 'package:openlib/services/database.dart';
import 'package:openlib/state/state.dart' show myLibraryProvider;

MyLibraryDb dataBase = MyLibraryDb.instance;

// Generate a safe filename from book metadata: title_author_info.extension
String generateBookFileName({
  required String title,
  String? author,
  String? info,
  required String format,
  required String md5,
}) {
  // Sanitize text by removing/replacing invalid characters for filenames
  String sanitize(String text) {
    return text
        .replaceAll(RegExp(r'[<>:"/\\|?*]'), '')
        .replaceAll(RegExp(r'\s+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .trim();
  }

  // Truncate string to max length
  String truncate(String text, int maxLength) {
    if (text.length <= maxLength) return text;
    return text.substring(0, maxLength);
  }

  String safeTitle = sanitize(title);
  String safeAuthor = author != null ? sanitize(author) : "";
  String safeInfo = info != null ? sanitize(info) : "";

  // Build filename parts
  List<String> parts = [];
  if (safeTitle.isNotEmpty) {
    parts.add(truncate(safeTitle, 80));
  }
  if (safeAuthor.isNotEmpty) {
    parts.add(truncate(safeAuthor, 40));
  }
  if (safeInfo.isNotEmpty) {
    parts.add(truncate(safeInfo, 30));
  }

  // Add md5 suffix for uniqueness
  parts.add(truncate(md5, 8));

  String baseName = parts.join("_");

  // Ensure total filename is not too long (max 200 chars before extension)
  if (baseName.length > 200) {
    baseName = baseName.substring(0, 200);
  }

  // Remove trailing underscores
  baseName = baseName.replaceAll(RegExp(r'_+$'), '');

  return "$baseName.$format";
}

Future<String> get getBookStorageDefaultDirectory async {
  if (Platform.isAndroid) {
    final directory = await getExternalStorageDirectory();
    return directory!.path;
  } else {
    final directory = await getApplicationDocumentsDirectory();
    return directory.path;
  }
}

Future<void> moveFilesToAndroidInternalStorage() async {
  try {
    final directory = await getApplicationDocumentsDirectory();
    final directoryExternal = await getExternalStorageDirectory();
    List<FileSystemEntity> files = Directory(directory.path).listSync();
    for (var element in files) {
      if ((element.path.contains('pdf')) || element.path.contains('epub')) {
        String fileName = element.path.split('/').last;
        File file = File(element.path);
        file.copySync('${directoryExternal!.path}/$fileName');
        file.deleteSync();
      }
    }
  } catch (e) {
    // ignore: avoid_print
    print(e);
  }
}

Future<void> moveFolderContents(
    String sourcePath, String destinationPath) async {
  final source = Directory(sourcePath);
  source.listSync(recursive: false).forEach((var entity) {
    if (entity is Directory) {
      var newDirectory =
          Directory('$destinationPath/${entity.path.split('/').last}');
      newDirectory.createSync();
      moveFolderContents(entity.path, newDirectory.path);
      entity.deleteSync();
    } else if (entity is File) {
      entity.copySync('$destinationPath/${entity.path.split('/').last}');
      entity.deleteSync();
    }
  });
}

Future<bool> isFileExists(String filePath) async {
  return await File(filePath).exists();
}

Future<void> deleteFile(String filePath) async {
  if (await isFileExists(filePath) == true) {
    await File(filePath).delete();
  }
}

Future<String> getFilePath(String fileName) async {
  final bookStorageDirectory =
      await dataBase.getPreference('bookStorageDirectory');
  String filePath = '$bookStorageDirectory/$fileName';
  bool isExists = await isFileExists(filePath);
  if (isExists == true) {
    return filePath;
  }
  throw "File Not Exists";
}

Future<void> deleteFileWithDbData(Ref ref, String md5, String format,
    {String? fileName}) async {
  try {
    // Use provided fileName or fall back to md5.format
    String actualFileName = fileName ?? '$md5.$format';
    final bookStorageDirectory =
        await dataBase.getPreference('bookStorageDirectory');
    await deleteFile('$bookStorageDirectory/$actualFileName');
    await dataBase.delete(md5);
    await dataBase.deleteBookState(actualFileName);
    // ignore: unused_result
    ref.refresh(myLibraryProvider);
  } catch (e) {
    // print(e);
    rethrow;
  }
}

// Syncs the library database with actual files on disk
// Removes entries for files that no longer exist and adds new files found
// Returns the number of changes made
Future<int> syncLibraryWithDisk() async {
  int changes = 0;
  try {
    final bookStorageDirectory =
        await dataBase.getPreference('bookStorageDirectory');
    final directory = Directory(bookStorageDirectory.toString());

    if (!await directory.exists()) {
      return 0;
    }

    // Get all books from database
    final booksInDb = await dataBase.getAll();

    // Get all book files on disk
    final filesOnDisk = <String>{};
    final files = directory.listSync(recursive: false);
    for (var entity in files) {
      if (entity is File) {
        final fileName = entity.path.split('/').last;
        final extension = fileName.split('.').last.toLowerCase();
        if (extension == 'epub' ||
            extension == 'pdf' ||
            extension == 'cbr' ||
            extension == 'cbz') {
          filesOnDisk.add(fileName);
        }
      }
    }

    // Remove database entries for files that no longer exist
    for (var book in booksInDb) {
      // Use actual fileName from database if available, otherwise fall back to id.format
      final fileName = book.getFileName();
      if (!filesOnDisk.contains(fileName)) {
        await dataBase.delete(book.id);
        await dataBase.deleteBookState(fileName);
        changes++;
      }
    }

    // Add new files that are not in database (only for legacy md5.format named files)
    final existingFileNames = booksInDb.map((b) => b.getFileName()).toSet();
    for (var fileName in filesOnDisk) {
      if (!existingFileNames.contains(fileName)) {
        final parts = fileName.split('.');
        if (parts.length >= 2) {
          final extension = parts.last.toLowerCase();
          // Try to extract md5 from filename (either pure md5 or as suffix after last underscore)
          String md5 = parts.sublist(0, parts.length - 1).join('.');

          // For new format files, try to extract md5 suffix
          if (md5.contains('_')) {
            final lastUnderscore = md5.lastIndexOf('_');
            final possibleMd5 = md5.substring(lastUnderscore + 1);
            // MD5 is 32 characters, but we only store 8 in the filename
            if (possibleMd5.length == 8) {
              md5 = possibleMd5;
            }
          }

          // Create a minimal book entry for the new file
          final book = MyBook(
            id: md5,
            title: md5,
            author: "Unknown",
            thumbnail: "",
            link: "",
            publisher: "",
            info: "",
            description: "",
            format: extension,
            fileName: fileName,
          );
          await dataBase.insert(book);
          changes++;
        }
      }
    }
  } catch (e) {
    // Silently fail
  }
  return changes;
}
