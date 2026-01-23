// Dart imports:
import 'dart:io';

// Package imports:
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

// Project imports:
import 'package:openlib/services/database.dart';
import 'package:openlib/state/state.dart' show myLibraryProvider;

MyLibraryDb dataBase = MyLibraryDb.instance;

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

Future<void> deleteFileWithDbData(
    Ref ref, String md5, String format) async {
  try {
    String fileName = '$md5.$format';
    final bookStorageDirectory =
        await dataBase.getPreference('bookStorageDirectory');
    await deleteFile('$bookStorageDirectory/$fileName');
    await dataBase.delete(md5);
    await dataBase.deleteBookState(fileName);
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
        if (extension == 'epub' || extension == 'pdf' || extension == 'cbr' || extension == 'cbz') {
          filesOnDisk.add(fileName);
        }
      }
    }
    
    // Remove database entries for files that no longer exist
    for (var book in booksInDb) {
      final fileName = "${book.id}.${book.format}";
      if (!filesOnDisk.contains(fileName)) {
        await dataBase.delete(book.id);
        await dataBase.deleteBookState(fileName);
        changes++;
      }
    }
    
    // Add new files that are not in database
    final idsInDb = booksInDb.map((b) => b.id).toSet();
    for (var fileName in filesOnDisk) {
      final parts = fileName.split('.');
      if (parts.length >= 2) {
        final extension = parts.last.toLowerCase();
        final md5 = parts.sublist(0, parts.length - 1).join('.');
        
        if (!idsInDb.contains(md5)) {
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
