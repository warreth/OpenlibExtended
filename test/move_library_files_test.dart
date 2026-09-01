// Real tests for the storage-move path: changing the storage folder must
// carry the books along and leave nothing behind, whichever direction the
// move goes (the old code only moved files out of the internal default).

// Dart imports:
import 'dart:io';

// Flutter imports:
import 'package:flutter_test/flutter_test.dart';

// Project imports:
import 'package:openlib/services/files.dart';

void main() {
  late Directory source;
  late Directory destination;

  setUp(() {
    source = Directory.systemTemp.createTempSync('openlib_move_src');
    destination = Directory.systemTemp.createTempSync('openlib_move_dst');
    // Fresh destination dir content, not the temp root itself.
    destination = Directory('${destination.path}/books')..createSync();
  });

  tearDown(() {
    source.deleteSync(recursive: true);
    destination.deleteSync(recursive: true);
  });

  File _write(String dir, String name) {
    final f = File('$dir/$name');
    f.writeAsBytesSync(List.filled(128, 7));
    return f;
  }

  test('moves book files and leaves non-book files alone', () async {
    final epub = _write(source.path, 'book.epub');
    final pdf = _write(source.path, 'other.pdf');
    _write(source.path, 'notes.txt');

    await moveLibraryFiles(source.path, destination.path);

    expect(File('${destination.path}/book.epub').existsSync(), isTrue,
        reason: 'epub must arrive in the new directory');
    expect(File('${destination.path}/other.pdf').existsSync(), isTrue);
    expect(File('${destination.path}/notes.txt').existsSync(), isFalse,
        reason: 'non-book files are not library content');
    expect(epub.existsSync(), isFalse, reason: 'source must be emptied');
    expect(pdf.existsSync(), isFalse);
  });

  test('does not overwrite an existing file at the destination', () async {
    final src = _write(source.path, 'book.epub');
    final dst = File('${destination.path}/book.epub')
      ..writeAsBytesSync(List.filled(64, 1));

    await moveLibraryFiles(source.path, destination.path);

    expect(dst.lengthSync(), 64, reason: 'the existing destination file wins');
    expect(src.existsSync(), isTrue,
        reason: 'source is kept when the move is a no-op');
  });

  test('missing source directory is a silent no-op', () async {
    // E.g. the folder was on an unmounted SD card.
    await moveLibraryFiles('/nonexistent/openlib/path', destination.path);
    expect(destination.listSync(), isEmpty);
  });

  test('creates the destination directory when it does not exist', () async {
    final nested = Directory('${destination.path}/new/sub');
    _write(source.path, 'book.cbz');

    await moveLibraryFiles(source.path, nested.path);

    expect(File('${nested.path}/book.cbz').existsSync(), isTrue,
        reason: 'nested destinations are created recursively');
  });
}
