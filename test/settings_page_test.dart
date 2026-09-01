// Builds the real SettingsPage with a real (ffi-backed) database and provider
// scope. Regression coverage on the page structure: every section header and
// tile renders, and the theme dropdown commits through to the provider.
// The DB persistence of setTheme itself is covered by a plain (real-zone)
// test below, because real sqlite I/O freezes inside the widget-test fake
// async zone.

// Dart imports:
import 'dart:io';

// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

// Project imports:
import 'package:openlib/services/database.dart';
import 'package:openlib/state/state.dart';
import 'package:openlib/ui/settings_page.dart';

class _FakePathProvider extends PathProviderPlatform {
  static const base = '/tmp/openlib_settings_test';

  @override
  Future<String?> getApplicationSupportPath() async => base;

  @override
  Future<String?> getApplicationDocumentsPath() async => base;

  @override
  Future<String?> getTemporaryPath() async => base;

  @override
  Future<String?> getLibraryPath() async => base;
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    PathProviderPlatform.instance = _FakePathProvider();
    Directory(_FakePathProvider.base).createSync(recursive: true);
  });

  Future<void> pumpPage(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: ThemeData.light(),
          darkTheme: ThemeData.dark(),
          home: const Scaffold(body: SettingsPage()),
        ),
      ),
    );
    // Bounded pumping: the page starts async work (instance providers,
    // PackageInfo) that can keep animations running, so pumpAndSettle is
    // not reliable here.
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(seconds: 2));
  }

  testWidgets('renders all sections and tiles', (tester) async {
    await pumpPage(tester);

    for (final label in [
      'Search Providers',
      'Library & Instances',
      'Appearance',
      'General',
      'Reader',
      'Advanced',
      'Updates',
      'About',
    ]) {
      expect(find.text(label), findsOneWidget,
          reason: 'section header "$label" must render');
    }

    for (final label in [
      'Manage Instances',
      'Auto-Rank Instances',
      'Rank Instances Now',
      'Theme',
      'Font Size',
      'Storage Location',
      'Open PDF externally',
      'Open EPUB externally',
      'Manual Download Button',
      "Anna's Archive Donation Key",
      'Include Beta Updates',
      'Check for Updates',
      'About OpenlibExtended',
      'Redo Onboarding',
      'Export Logs',
    ]) {
      expect(find.text(label), findsOneWidget,
          reason: 'tile "$label" must render');
    }
  });

  testWidgets('theme dropdown updates the provider state', (tester) async {
    await pumpPage(tester);

    // The provider defaults to light mode, so the closed dropdown shows
    // "Light theme". The search-provider section pushed it below the
    // default test viewport - drag it into view first.
    await tester.scrollUntilVisible(
      find.text('Light theme'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Light theme'));
    await tester.pump(const Duration(milliseconds: 600));

    await tester.tap(find.text('Dark theme').last);
    await tester.pump(const Duration(milliseconds: 600));

    // The state change inside setTheme is synchronous; only the disk write
    // would freeze in the fake async zone.
    final element = tester.element(find.byType(SettingsPage));
    final container = ProviderScope.containerOf(element);
    expect(container.read(themeModeProvider), ThemeMode.dark,
        reason: 'selecting Dark theme must update the provider state');
  });

  test('setTheme persists the selected mode', () async {
    final notifier = ThemeModeNotifier(ThemeMode.light);
    await notifier.setTheme(ThemeMode.dark);

    final saved = await MyLibraryDb.instance.getPreference('themeMode');
    expect(saved, 'dark',
        reason: 'setTheme must persist the mode to the preferences table');
  });
}
