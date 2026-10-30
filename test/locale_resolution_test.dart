import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openlib/l10n/app_localizations.dart';
import 'package:openlib/l10n/locale_resolution.dart';

void main() {
  final supported = AppLocalizations.supportedLocales;

  test('unsupported system languages fall back to English', () {
    expect(
      resolveAppLocale(<Locale>[const Locale('el')], supported),
      const Locale('en'),
    );
  });

  test('supported languages win over the English fallback', () {
    expect(
      resolveAppLocale(<Locale>[const Locale('de', 'AT')], supported),
      const Locale('de'),
    );
    expect(
      resolveAppLocale(<Locale>[const Locale('fr')], supported),
      const Locale('fr'),
    );
    expect(
      resolveAppLocale(<Locale>[const Locale('en', 'GB')], supported),
      const Locale('en'),
    );
  });

  test('the first supported preference wins', () {
    expect(
      resolveAppLocale(
        <Locale>[const Locale('el'), const Locale('es')],
        supported,
      ),
      const Locale('es'),
    );
  });

  test('an empty or missing preference list falls back to English', () {
    expect(resolveAppLocale(null, supported), const Locale('en'));
    expect(resolveAppLocale(const <Locale>[], supported), const Locale('en'));
  });
}
