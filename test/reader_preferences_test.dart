import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:openlib/l10n/app_localizations.dart';
import 'package:openlib/services/database.dart';
import 'package:openlib/services/reader_apps.dart';
import 'package:openlib/state/state.dart';
import 'package:openlib/ui/components/reader_app_setting.dart';
import 'package:openlib/ui/epub_viewer.dart';
import 'package:openlib/ui/pdf_viewer.dart';

class _Paths extends PathProviderPlatform {
  final root =
      Directory.systemTemp.createTempSync('openlib_reader_preferences_');
  @override
  Future<String?> getApplicationSupportPath() async => root.path;
  @override
  Future<String?> getApplicationDocumentsPath() async => root.path;
  @override
  Future<String?> getTemporaryPath() async => root.path;
  @override
  Future<String?> getLibraryPath() async => root.path;
}

class _MemoryPreferences extends ReaderPreferences {
  final values = <String, String>{};
  @override
  Future<String> read(String format, {bool legacyExternal = false}) async =>
      values[format] ?? (legacyExternal ? 'ask' : 'internal');
  @override
  Future<void> save(String format, String reader) async {
    values[format] = reader;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final calls = <MethodCall>[];
  final paths = _Paths();
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    PathProviderPlatform.instance = paths;
    await MyLibraryDb.instance
        .savePreference('bookStorageDirectory', paths.root.path);
    File('${paths.root.path}/sample.epub')
        .writeAsStringSync('reader handoff fixture');
    File('${paths.root.path}/sample.pdf')
        .writeAsStringSync('reader handoff fixture');
  });
  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('openlib/readers'),
            (call) async {
      calls.add(call);
      if (call.method == 'readers') {
        return [
          {'id': 'com.example.reader', 'label': 'Example Reader'},
          {'id': 'moon.reader', 'label': 'Moon Reader'},
        ];
      }
      return null;
    });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('openlib/readers'), null);
  });

  test('reader selections persist per format across fresh provider containers',
      () async {
    final db = await MyLibraryDb.instance.database;
    await db.delete('preferences', where: 'name IN (?, ?, ?, ?)', whereArgs: [
      'epubReaderApp',
      'pdfReaderApp',
      'openEpubwithExternalApp',
      'openPdfwithExternalApp'
    ]);
    final first = ProviderContainer();
    expect(
        await first.read(readerPreferenceProvider('epub').future), 'internal');
    await first
        .read(readerPreferencesProvider)
        .save('epub', 'com.example.reader');
    await first.read(readerPreferencesProvider).save('pdf', 'ask');
    first.dispose();
    final restarted = ProviderContainer();
    expect(await restarted.read(readerPreferenceProvider('epub').future),
        'com.example.reader');
    expect(await restarted.read(readerPreferenceProvider('pdf').future), 'ask');
    restarted.dispose();
  });

  test('legacy external preference migrates until a specific reader is saved',
      () async {
    final db = await MyLibraryDb.instance.database;
    await db
        .delete('preferences', where: 'name = ?', whereArgs: ['epubReaderApp']);
    await MyLibraryDb.instance.savePreference('openEpubwithExternalApp', true);
    final preferences = ReaderPreferences();
    expect(await preferences.read('epub'), 'ask');
    await preferences.save('epub', 'internal');
    expect(await preferences.read('epub'), 'internal');
  });

  testWidgets('settings dropdown selects and remembers Example Reader',
      (tester) async {
    final preferences = _MemoryPreferences();
    await tester.pumpWidget(ProviderScope(
        overrides: [
          readerPreferencesProvider.overrideWithValue(preferences),
        ],
        child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const Scaffold(body: ReaderAppSetting(format: 'epub')))));
    await tester.pumpAndSettle();
    expect(find.text('EPUB reader'), findsOneWidget);
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    expect(find.text('Built-in reader').last, findsOneWidget);
    expect(find.text('Ask every time'), findsOneWidget);
    await tester.tap(find.text('Example Reader').last);
    await tester.pumpAndSettle();
    expect(preferences.values['epub'], 'com.example.reader');
    expect(find.text('Example Reader'), findsOneWidget);
  });

  test('iOS external opening presents an app chooser, not document preview',
      () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
        const MethodChannel('openlib/readers'), null);
    MethodCall? externalCall;
    messenger.setMockMethodCallHandler(const MethodChannel('open_file'),
        (call) async {
      externalCall = call;
      return '{"type":0,"message":"done"}';
    });
    addTearDown(() => messenger.setMockMethodCallHandler(
        const MethodChannel('open_file'), null));
    await const ReaderApps()
        .openBook(path: '/tmp/book.epub', format: 'epub', reader: 'ask');
    expect(externalCall!.arguments['isIOSAppOpen'], isTrue);
    expect(externalCall!.arguments['type'], 'application/epub+zip');
  });

  testWidgets('desktop external option describes the system default',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        readerPreferencesProvider.overrideWithValue(_MemoryPreferences())
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(body: ReaderAppSetting(format: 'pdf')),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    expect(find.text('System default app'), findsOneWidget);
    expect(find.text('Ask every time'), findsNothing);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('reader selector uses the chosen app language', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        readerPreferencesProvider.overrideWithValue(_MemoryPreferences())
      ],
      child: MaterialApp(
        locale: const Locale('de'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(body: ReaderAppSetting(format: 'epub')),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('EPUB-Lese-App'), findsOneWidget);
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    expect(find.text('Jedes Mal fragen'), findsOneWidget);
    expect(find.text('Ask every time'), findsNothing);
  });

  for (final format in ['epub', 'pdf']) {
    testWidgets('$format Open targets its saved reader without prompting',
        (tester) async {
      final preferences = _MemoryPreferences()
        ..values[format] = 'com.example.reader';
      late WidgetRef captured;
      await tester.pumpWidget(ProviderScope(
          overrides: [
            readerPreferencesProvider.overrideWithValue(preferences),
          ],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(body: Consumer(builder: (context, ref, _) {
              captured = ref;
              return const Text('reader target');
            })),
          )));
      final context = tester.element(find.text('reader target'));
      await tester.runAsync(() => format == 'epub'
          ? launchEpubViewer(
              fileName: 'sample.epub', context: context, ref: captured)
          : launchPdfViewer(
              fileName: 'sample.pdf', context: context, ref: captured));
      final open = calls.where((call) => call.method == 'open').single;
      expect(open.arguments['reader'], 'com.example.reader');
      expect(open.arguments['mimeType'],
          format == 'epub' ? 'application/epub+zip' : 'application/pdf');
      expect(open.arguments['path'], '${paths.root.path}/sample.$format');
    });
  }
}
