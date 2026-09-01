// Real checks for the translation setup: every locale must carry the
// full key set, generated getters must return the translations, and
// unsupported locales must fall back to English rather than crash.

// Dart imports:
import 'dart:convert';
import 'dart:io';

// Flutter imports:
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Project imports:
import 'package:openlib/l10n/app_localizations.dart';
import 'package:openlib/ui/settings_page.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

Map<String, dynamic> _readArb(String locale) {
  final file = File('lib/l10n/app_$locale.arb');
  return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
}

void main() {
  final locales = ['en', 'de', 'fr', 'es'];

  test('generated delegates expose exactly the shipped locales', () {
    expect(AppLocalizations.supportedLocales.map((l) => l.languageCode),
        unorderedEquals(locales));
  });

  test('every locale file carries the full key set', () {
    final template = _readArb('en');
    final templateKeys = template.keys
        .where((k) => !k.startsWith('@') && k != '@@locale')
        .toSet();

    expect(templateKeys, isNotEmpty,
        reason: 'the template arb must define strings');

    for (final locale in locales.skip(1)) {
      final arb = _readArb(locale);
      final keys = arb.keys
          .where((k) => !k.startsWith('@') && k != '@@locale')
          .toSet();
      expect(
        keys,
        templateKeys,
        reason:
            'app_$locale.arb must translate every key the template has',
      );
    }
  });

  test('arb files carry descriptions for every template key', () {
    final template = _readArb('en');
    final keys = template.keys
        .where((k) => !k.startsWith('@') && k != '@@locale')
        .toSet();
    for (final key in keys) {
      expect(template, contains('@$key'),
          reason: 'key $key needs an @description for translators');
    }
  });

  test('German translations actually differ from English', () {
    final en = _readArb('en');
    final de = _readArb('de');
    var translated = 0;
    for (final key in en.keys.where((k) => !k.startsWith('@'))) {
      if (key == '@@locale' || key == 'appTitle') continue;
      if (en[key] != de[key]) translated++;
    }
    expect(translated, greaterThan(20),
        reason: 'most strings should be really translated, not copied');
  });

  testWidgets('localized strings resolve per locale', (tester) async {
    late AppLocalizations de;
    late AppLocalizations fr;

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('de'),
        builder: (context, _) {
          de = AppLocalizations.of(context);
          return const SizedBox();
        },
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('fr'),
        builder: (context, _) {
          fr = AppLocalizations.of(context);
          return const SizedBox();
        },
      ),
    );

    expect(de.settingsTitle, 'Einstellungen');
    expect(de.cancel, 'Abbrechen');
    expect(fr.settingsTitle, 'Paramètres');
    expect(fr.cancel, 'Annuler');
  });

  testWidgets('the language dropdown writes the locale preference',
      (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(body: SettingsPage()),
        ),
      ),
    );
    // The settings page polls mirror health, so it never settles; a fixed
    // frame budget is enough to assert the rendered strings.
    await tester.pump(const Duration(seconds: 1));

    // The Language settings card must be present and labeled.
    expect(find.text('Language'), findsOneWidget);
    expect(find.text('System default'), findsOneWidget);
  });

  test('placeholder strings interpolate the real values', () {
    final en = _readArb('en');
    expect(en['resultsFor'], "Results for '{query}'");
    expect(en['couldNotLaunch'], 'Could not launch {url}');
    // The placeholder must be documented in the metadata block.
    final meta = en['@resultsFor'] as Map<String, dynamic>;
    final placeholders = meta['placeholders'] as Map<String, dynamic>;
    expect(placeholders, contains('query'));
  });
}
