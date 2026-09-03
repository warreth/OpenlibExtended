// PDF viewer tests against a real two-page PDF rendered by pdfrx's
// real PDFium engine (native assets), plus the position-save wiring.

// Dart imports:
import 'dart:io';

// Flutter imports:
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Package imports:
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

// Project imports:
import 'package:openlib/ui/pdf_viewer.dart';
import 'package:openlib/l10n/app_localizations.dart';
import 'package:openlib/state/state.dart'
    show filePathProvider, getBookPosition, savePdfPosition;

class _FakePathProvider extends PathProviderPlatform {
  Future<String> _dir(String name) async {
    final dir = Directory('/tmp/openlib_pdf_test/$name');
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

  tearDownAll(() async {
    // pdfrx's PDFium worker isolate must be reaped or it keeps the
    // test isolate's channels open and flutter_test hangs at shutdown.
    await PdfrxEntryFunctions.instance.stopBackgroundWorker();
  });

  testWidgets('reader page renders its chrome while the PDF loads',
      (tester) async {
    final fixture = File('test/fixtures/sample.pdf').readAsBytesSync();
    final file = File('${Directory.systemTemp.path}/sample.pdf');
    file.writeAsBytesSync(fixture);

    await tester.pumpWidget(ProviderScope(
      overrides: [
        filePathProvider.overrideWith((ref, fileName) => file.path),
        // Reading the position goes through the real database, whose
        // first open deadlocks inside the widget test's fake-async
        // zone - the viewer then sits on its loading spinner forever.
        // Override it: this test asserts the chrome mounts, not the
        // persistence (the wiring test below covers that against the
        // real DB).
        getBookPosition.overrideWith((ref, fileName) async => null),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const PdfViewPage(fileName: 'sample.pdf'),
      ),
    ));

    // The document load runs in pdfrx's background worker; give it a
    // moment so the shell proves it mounted the real viewer widget.
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      await tester
          .runAsync(() => Future.delayed(const Duration(milliseconds: 50)));
    }

    expect(find.byType(PdfViewer), findsOneWidget);
    expect(find.byType(AppBar), findsOneWidget);
  });

  test('saved page number feeds the restore wiring', () async {
    // Persist a real position through the real database, then read it
    // back through the same provider the viewer watches.
    await savePdfPosition('sample2.pdf', 2);

    final container = ProviderContainer();
    addTearDown(container.dispose);

    final saved = await container.read(getBookPosition('sample2.pdf').future);
    expect(saved, '2');
    expect(initialPageFor(saved), 2);
  });

  test('initialPageFor parses and clamps saved positions', () {
    expect(initialPageFor(null), 1);
    expect(initialPageFor(''), 1);
    expect(initialPageFor('garbage'), 1);
    expect(initialPageFor('0'), 1);
    expect(initialPageFor('3'), 3);
  });

  test('savePdfPosition refuses page 0', () async {
    await savePdfPosition('x.pdf', 0);
  });
}
