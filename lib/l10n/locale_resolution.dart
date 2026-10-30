import 'package:flutter/widgets.dart';

/// Picks the app locale for the given system preferences.
///
/// Flutter's default resolution falls back to the first supported locale.
/// The generated list is alphabetical, so an unsupported system language
/// (for example Greek) used to open the app in German. Match the user's
/// language when the app has it and use English, the translation template,
/// for everything else.
Locale resolveAppLocale(
  Iterable<Locale>? preferred,
  Iterable<Locale> supported,
) {
  final supportedLocales = supported.toList(growable: false);
  for (final locale in preferred ?? const <Locale>[]) {
    for (final candidate in supportedLocales) {
      if (candidate.languageCode == locale.languageCode) {
        return candidate;
      }
    }
  }
  return supportedLocales.firstWhere(
    (locale) => locale.languageCode == 'en',
    orElse: () => supportedLocales.first,
  );
}
