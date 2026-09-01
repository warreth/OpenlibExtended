// Reader UX tests that mount the viewer with a real epub file: the font
// size controls in the app bar and the SelectionArea around the book text.
// These live apart from epub_viewer_test.dart because mounting the viewer
// against a real document starts sqlite work whose sqflite busy-watchers
// only drain in this file's own test run.

// Dart imports:
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
import 'package:openlib/l10n/app_localizations.dart';
import 'package:openlib/state/state.dart' show filePathProvider;

class _FakePathProvider extends PathProviderPlatform {
  Future<String> _dir(String name) async {
    final dir = Directory('/tmp/openlib_reader_test/$name');
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

  late Directory tmpDir;

  setUp(() {
    tmpDir = Directory.systemTemp.createTempSync('openlib_reader_test');
  });

  tearDown(() {
    tmpDir.deleteSync(recursive: true);
  });

  testWidgets('reader shows font size controls with the default size',
      (tester) async {
    final file = File('${tmpDir.path}/sample.epub');
    _writeMinimalEpub(file);

    await tester.pumpWidget(ProviderScope(
      overrides: [
        filePathProvider.overrideWith((ref, fileName) => file.path),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const EpubViewerWidget(fileName: 'sample.epub'),
      ),
    ));

    await tester.pump();
    await tester.pump();

    // The app bar shows the size between the two buttons and both
    // controls are reachable.
    expect(find.text('16'), findsOneWidget);
    expect(find.byTooltip('Increase font size'), findsOneWidget);
    expect(find.byTooltip('Decrease font size'), findsOneWidget);

    // Font changes stick through a rebuild of the same tree.
    await tester.tap(find.byTooltip('Increase font size'));
    await tester.pump();
    expect(find.text('18'), findsOneWidget);
    await tester.tap(find.byTooltip('Decrease font size'));
    await tester.pump();
    expect(find.text('16'), findsOneWidget);
  });

  testWidgets('book text is wrapped in a SelectionArea', (tester) async {
    final file = File('${tmpDir.path}/sample.epub');
    _writeMinimalEpub(file);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        filePathProvider.overrideWith((ref, fileName) => file.path),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const EpubViewerWidget(fileName: 'sample.epub'),
      ),
    ));

    await tester.pump();
    await tester.pump();
    expect(find.byType(SelectionArea), findsOneWidget);
  });
}

/// Writes a structurally valid minimal EPUB 3 book.
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
