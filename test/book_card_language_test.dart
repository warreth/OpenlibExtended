import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openlib/l10n/app_localizations.dart';
import 'package:openlib/state/state.dart';
import 'package:openlib/ui/components/book_card_widget.dart';

void main() {
  test('language names and codes produce full readable names', () {
    expect(getLanguage('Spanish, EPUB, 3.83 MB, 1991'), 'Spanish');
    expect(getLanguage('German, pdf, 5 MB'), 'German');
    expect(getLanguage('English [en], epub, 5 MB'), 'English');
    expect(getLanguage('de, epub'), 'German');
    expect(getLanguage(' [ES], epub'), 'Spanish');
    expect(getLanguage('EPUB, 5 MB'), isNull);
  });

  for (final scale in [1.0, 1.3]) {
    testWidgets('language is explicit beside publisher at scale $scale',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(ProviderScope(
          overrides: [
            resultCoverProvider.overrideWith((ref, url) async => null),
          ],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(scale)),
                child: child!),
            home: Scaffold(
                body: Column(children: [
              BookInfoCard(
                  title: 'PIHKAL: A Chemical Love Story',
                  author: 'Alexander Shulgin & Ann Shulgin',
                  publisher: '13insurgentes',
                  thumbnail: null,
                  info: 'Spanish, EPUB, 3.83 MB',
                  link: 'https://example.com/book',
                  source: 'Z-Library',
                  onClick: () {}),
              BookInfoCard(
                  title: 'No language metadata',
                  author: 'Author',
                  publisher: '',
                  thumbnail: null,
                  info: 'PDF, 4 MB',
                  link: 'https://example.com/other',
                  onClick: () {}),
            ])),
          )));
      await tester.pump();
      expect(find.text('Language: Spanish'), findsOneWidget);
      expect(find.text('Publisher: 13insurgentes'), findsOneWidget);
      expect(find.text('Language: Unknown'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
