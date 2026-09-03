// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

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
  });

  testWidgets('falls back to built-in notes while offline', (tester) async {
    // The test runner has no network: the GitHub fetch fails,
    // fetchReleaseNotes swallows it and the page must still render
    // the built-in notes.
    await tester.pumpWidget(pumpPage());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final l10n = AppLocalizations.of(
        tester.element(find.byType(WhatsNewPage)));

    // No markdown rendered, but every built-in note is visible.
    expect(find.byType(Markdown), findsNothing);
    expect(find.text(l10n.whatsNewFeatureSpeed), findsOneWidget);
    expect(find.text(l10n.whatsNewFeatureCovers), findsOneWidget);
  });

  testWidgets('the sources tab offers the instance update', (tester) async {
    await tester.pumpWidget(pumpPage());
    await tester.pump();

    final l10n = AppLocalizations.of(
        tester.element(find.byType(WhatsNewPage)));

    await tester.tap(find.text(l10n.whatsNewTabSources));
    await tester.pumpAndSettle();
    expect(find.text(l10n.whatsNewProvidersHint), findsOneWidget);
    expect(find.text(l10n.whatsNewUpdateInstances), findsOneWidget);
    expect(find.text(l10n.whatsNewContinue), findsOneWidget);
  });

  testWidgets('markdown release notes render headings, lists and links',
      (tester) async {
    // Direct render of the same markdown a GitHub release body uses,
    // through the same widget the whats-new page uses.
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Markdown(data: '''
## What's new in v1.6.0-beta3

### Faster downloads

- No mirror probing
- Fast hosts first

See the [release page](https://github.com/warreth/OpenlibExtended/releases).
'''),
      ),
    );

    expect(find.byType(Markdown), findsOneWidget);
    expect(find.text("What's new in v1.6.0-beta3"), findsOneWidget);
    expect(find.text('Faster downloads'), findsOneWidget);
    expect(find.text('No mirror probing'), findsOneWidget);
    // Links render as RichText spans, not Text widgets.
    final linkRendered = find
        .byWidgetPredicate((w) =>
            w is RichText &&
            w.text.toPlainText().contains('release page'))
        .evaluate()
        .isNotEmpty;
    expect(linkRendered, isTrue);
  });
}
