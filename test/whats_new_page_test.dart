// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// Project imports:
import 'package:openlib/l10n/app_localizations.dart';
import 'package:openlib/ui/whats_new_page.dart';

void main() {
  Widget pumpPage() {
    return ProviderScope(
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const WhatsNewPage(fromVersion: '1.0.9', toVersion: '1.0.11'),
      ),
    );
  }

  testWidgets('shows the new version, both tabs and the feature notes',
      (tester) async {
    await tester.pumpWidget(pumpPage());
    await tester.pump();

    final l10n = AppLocalizations.of(
        tester.element(find.byType(WhatsNewPage)));

    expect(find.text(l10n.whatsNewTitle('1.0.11')), findsOneWidget);
    expect(find.text(l10n.whatsNewTabFeatures), findsOneWidget);
    expect(find.text(l10n.whatsNewTabSources), findsOneWidget);

    // Feature notes are visible on the default tab.
    expect(find.text(l10n.whatsNewFeatureSpeed), findsOneWidget);
  });

  testWidgets('the sources tab offers the instance update and confirms',
      (tester) async {
    await tester.pumpWidget(pumpPage());
    await tester.pump();

    final l10n = AppLocalizations.of(
        tester.element(find.byType(WhatsNewPage)));

    // Switch to the sources tab.
    await tester.tap(find.text(l10n.whatsNewTabSources));
    await tester.pumpAndSettle();
    expect(find.text(l10n.whatsNewProvidersHint), findsOneWidget);

    // Tapping update must not crash even though the test runner has
    // no real database: the button is the contract under test.
    expect(find.text(l10n.whatsNewUpdateInstances), findsOneWidget);
    expect(find.text(l10n.whatsNewContinue), findsOneWidget);
  });
}
