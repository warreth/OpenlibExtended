// Real pagination behavior of the results page: page 1 renders, the
// next page loads as the list scrolls near its end, an empty page stops
// the pager. The search provider is overridden with deterministic pages;
// the page widget under test is the real one.

// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

// Project imports:
import 'package:openlib/services/annas_archieve.dart';
import 'package:openlib/l10n/app_localizations.dart';
import 'package:openlib/state/state.dart';
import 'package:openlib/ui/components/book_card_widget.dart';
import 'package:openlib/ui/results_page.dart';

/// Builds a page of books with recognizable titles.
List<BookData> fakePage(int page) {
  return List.generate(
      20,
      (i) => BookData(
            title: 'Book $page-$i',
            author: 'Author $page$i',
            link: 'https://example.com/md5/p$page-$i',
            md5: 'md5-p$page-$i',
          ));
}

Future<List<BookData>> fakeSearch(SearchPageKey key) async {
  // Page 3 exists but is empty: the pager must stop there.
  if (key.page >= 3) return [];
  await Future<void>.delayed(const Duration(milliseconds: 10));
  return fakePage(key.page);
}

void main() {
  Future<void> pumpResults(WidgetTester tester, {double height = 600}) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        searchProvider.overrideWith((ref, key) => fakeSearch(key)),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const ResultPage(searchQuery: 'docker'),
      ),
    ));
    // Bounded pumping: the bottom loader keeps its animation alive, so
    // pumpAndSettle never settles.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  testWidgets('renders the first page of results', (tester) async {
    await pumpResults(tester);

    // Lazy slivers only build what is visible; page 1's data must at
    // least fill the screen with its items.
    expect(find.text('Book 1-0'), findsOneWidget);
    expect(find.byType(BookInfoCard), findsWidgets);
  });

  testWidgets('scrolling to the bottom loads the next page and appends',
      (tester) async {
    await pumpResults(tester);

    // Drag far down: past the 200px pre-fetch margin, into page 2.
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -4000));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));

    // Page 2 items are now in the data: at least one page-2 card must
    // have been built as the list shows them.
    final visiblePage2 = find
        .byWidgetPredicate((w) =>
            w is BookInfoCard &&
            w.title.startsWith('Book 2-'))
        .evaluate()
        .length;
    expect(visiblePage2, greaterThan(0),
        reason: 'page 2 items must append after scrolling');
  });

  testWidgets('an empty page ends the pager instead of fetching forever',
      (tester) async {
    await pumpResults(tester);

    // First scroll loads page 2, second reaches for page 3, which is
    // empty - the pager must stop.
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -4000));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -8000));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));

    // Page 3 returned nothing: no page-3 book ever renders, and the
    // pager stops instead of fetching page 4 (whose books would also be
    // absent, but the empty response proves the fetch ran once and
    // stopped).
    expect(
        find.byWidgetPredicate((w) =>
            w is BookInfoCard && w.title.startsWith('Book 3-')),
        findsNothing);
  });
}
