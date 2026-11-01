// The book info page must expose its text for copying: SelectionArea wraps
// the scroll view so title, author, info and description are selectable,
// while buttons inside the child slot keep working.

// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

// Project imports:
import 'package:openlib/l10n/app_localizations.dart';
import 'package:openlib/state/state.dart' show annaArchiveBaseUrlProvider;
import 'package:openlib/ui/components/book_info_widget.dart';

class _FakeBookData {
  final String md5 = '7b2e2c05501894b229e309e39ec0d05d';
  final String link =
      'https://annas-archive.gl/md5/7b2e2c05501894b229e309e39ec0d05d';
  final String title = 'Structure of Scientific Revolutions';
  final String author = 'Thomas S. Kuhn';
  final String publisher = 'University of Chicago Press';
  final String info = 'English [en], EPUB, 1.5MB, 2012';
  final String thumbnail = '';
  final String description;
  _FakeBookData(
      {this.description =
          'A book about paradigm shifts in science and how they reshape whole fields.'});
}

void main() {
  testWidgets(
      'released scroll keeps final description line above system navigation',
      (tester) async {
    tester.view.physicalSize = const Size(400, 700);
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(bottom: 48);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPadding);
    final data = _FakeBookData(
        description:
            '${List.filled(40, "A long book description.").join("\n")}\nFinal line.');
    await tester.pumpWidget(ProviderScope(
      overrides: [annaArchiveBaseUrlProvider.overrideWith((ref) async => null)],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        scrollBehavior: const MaterialScrollBehavior()
            .copyWith(physics: const BouncingScrollPhysics()),
        home: Scaffold(
            appBar: AppBar(),
            body:
                BookInfoWidget(data: data, child: const SizedBox(height: 40))),
      ),
    ));
    await tester.pumpAndSettle();
    final scroll = tester.state<ScrollableState>(find.byType(Scrollable).first);
    scroll.position.jumpTo(scroll.position.maxScrollExtent);
    await tester.fling(
        find.byType(SingleChildScrollView), const Offset(0, -250), 1000);
    await tester.pumpAndSettle();
    expect(tester.getBottomRight(find.text(data.description)).dy,
        lessThanOrEqualTo(700 - 48),
        reason:
            'after bounce settles, the final line must clear Android navigation');
    expect(tester.getBottomRight(find.byType(SingleChildScrollView)).dy,
        lessThanOrEqualTo(700 - 48));
  });

  testWidgets('book info text is selectable for copying', (tester) async {
    final data = _FakeBookData();

    await tester.pumpWidget(ProviderScope(
      overrides: [
        // The "open in site" button resolves its mirror through the
        // catalogue provider; this test is about text selection, so the
        // mirror is stubbed instead of letting build() start I/O.
        annaArchiveBaseUrlProvider.overrideWith((ref) async => null),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: BookInfoWidget(
            data: data,
            child: ElevatedButton(
              onPressed: () {},
              child: const Text('Add To My Library'),
            ),
          ),
        ),
      ),
    ));

    await tester.pump();

    // The selectable region wraps the text content.
    expect(find.byType(SelectionArea), findsOneWidget);

    // Title, author, metadata and description all render inside it.
    expect(find.text(data.title), findsOneWidget);
    expect(find.text(data.author), findsOneWidget);
    expect(find.text(data.info), findsOneWidget);
    expect(find.text(data.description), findsOneWidget);

    // The button in the child slot still exists and is reachable.
    expect(find.byType(ElevatedButton), findsOneWidget);
  });
}
