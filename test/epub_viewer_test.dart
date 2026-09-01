// Tests the real epub_viewer widget behavior: a missing file surfaces the
// "File not found" snackbar instead of crashing, and the viewer route renders
// the loading state from the real filePathProvider while resolving the path.

// Dart imports:
import 'dart:async';
import 'dart:io';

// Flutter imports:
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Package imports:
import 'package:archive/archive.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

// Project imports:
import 'package:openlib/ui/epub_viewer.dart';
import 'package:openlib/services/database.dart' show MyLibraryDb;
import 'package:openlib/state/state.dart' show filePathProvider;

class _FakePathProvider extends PathProviderPlatform {
  Future<String> _dir(String name) async {
    final dir = Directory('/tmp/openlib_epub_test/$name');
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

  // The real getFilePath flow reads the bookStorageDirectory preference from
  // the sqlite database; give it a real local database so the code path is
  // the production one (preference lookup misses -> error -> snackbar).
  setUpAll(() async {
    if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      PathProviderPlatform.instance = _FakePathProvider();

      // The size label test asserts absolute values, so a font size
      // persisted by an earlier test run must not leak in. setUpAll runs
      // in the plain zone; the same write inside a widget test would
      // hang on real I/O.
      await MyLibraryDb.instance.savePreference('readerFontSize', 16);
    }
  });

  late Directory tmpDir;

  setUp(() {
    // getFilePath resolves under the platform documents directory; without the
    // path_provider plugin in tests it throws, which exercises the viewer's
    // error path. The happy path is covered by overriding the provider.
    tmpDir = Directory.systemTemp.createTempSync('openlib_epub_test');
  });

  tearDown(() {
    tmpDir.deleteSync(recursive: true);
  });

  test('test epub creation helper produces a parseable minimal book', () {
    final file = File('${tmpDir.path}/sample.epub');
    _writeMinimalEpub(file);
    expect(file.existsSync(), isTrue);
    expect(file.lengthSync(), greaterThan(500));

    final archive = ZipDecoder().decodeBytes(file.readAsBytesSync());
    expect(archive.findFile('mimetype'), isNotNull);
    expect(archive.findFile('META-INF/container.xml'), isNotNull);
    expect(archive.findFile('OEBPS/content.opf'), isNotNull);
    expect(archive.findFile('OEBPS/chapter1.xhtml'), isNotNull);
  });

  testWidgets('launchEpubViewer shows snackbar for a missing file',
      (tester) async {
    late WidgetRef capturedRef;
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () {},
              child: Consumer(
                builder: (context, ref, _) {
                  capturedRef = ref;
                  return const Text('open');
                },
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));

    // runAsync: the real flow reads the sqlite database, which uses real
    // async I/O that does not advance inside the widget test's fake zone.
    await tester.runAsync(() => launchEpubViewer(
          fileName: 'no_such_book.epub',
          context: tester.element(find.text('open')),
          ref: capturedRef,
        ));
    await tester.pump();

    // The viewer must degrade to a visible message, never crash the app.
    expect(find.byType(SnackBar), findsOneWidget);
    expect(find.textContaining('File not found'), findsOneWidget);
    expect(find.byType(EpubViewerWidget), findsNothing);
  });

  testWidgets('EpubViewerWidget renders the loading state while resolving',
      (tester) async {
    // A completer (not a timer) keeps the provider pending without leaving
    // pending timers behind at teardown.
    final gate = Completer<String>();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        filePathProvider.overrideWith((ref, fileName) => gate.future),
      ],
      child: const MaterialApp(home: EpubViewerWidget(fileName: 'sample.epub')),
    ));

    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('OpenlibExtended'), findsOneWidget);

    // Unmount so no pending provider work bleeds into the next test -
    // leftover viewers contend on the shared sqlite singleton and leave
    // sqflite busy-watchers that fail teardown.
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });
}

/// Writes a structurally valid minimal EPUB 3 book.
/// (mimetype must be first and stored uncompressed for strict readers.)
void _writeMinimalEpub(File file) {
  final archive = Archive();
  archive.addFile(ArchiveFile('mimetype', 20, 'application/epub+zip'.codeUnits)
    ..compress = false);
  archive.addFile(ArchiveFile.string('META-INF/container.xml', '''
<?xml version="1.0"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles>
    <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
  </rootfiles>
</container>'''));
  archive.addFile(ArchiveFile.string('OEBPS/content.opf', '''
<?xml version="1.0" encoding="UTF-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="bookid">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:identifier id="bookid">urn:uuid:0d3f1a5a-9d0a-4d0e-a4e9-6b6e6f6f6e6e</dc:identifier>
    <dc:title>Sample Book</dc:title>
    <dc:language>en</dc:language>
  </metadata>
  <manifest>
    <item id="nav" href="chapter1.xhtml" media-type="application/xhtml+xml"/>
  </manifest>
  <spine>
    <itemref idref="nav"/>
  </spine>
</package>'''));
  archive.addFile(ArchiveFile.string('OEBPS/chapter1.xhtml', '''
<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops">
  <head><title>Chapter 1</title></head>
  <body><h1>Sample Chapter</h1><p>Hello reader.</p></body>
</html>'''));

  final data = ZipEncoder().encode(archive)!;
  file.writeAsBytesSync(data);
}
