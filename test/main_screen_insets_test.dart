import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openlib/l10n/app_localizations.dart';
import 'package:openlib/main.dart';
import 'package:openlib/state/state.dart';
import 'package:openlib/ui/home_page.dart';

void main() {
  testWidgets(
      'scrolling keeps tab content below the status bar without an app-name header',
      (tester) async {
    tester.view.padding = const FakeViewPadding(top: 24);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPadding);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        getTrendingBooks.overrideWith((ref) async => []),
        activeDownloadsProvider.overrideWith((ref) => Stream.value({})),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const MainScreen(),
      ),
    ));
    await tester.pump();
    final scrollContext = tester.element(find.byType(CustomScrollView).first);
    UserScrollNotification(
      metrics: FixedScrollMetrics(
          minScrollExtent: 0,
          maxScrollExtent: 1000,
          pixels: 100,
          viewportDimension: 500,
          axisDirection: AxisDirection.down,
          devicePixelRatio: 1),
      context: scrollContext,
      direction: ScrollDirection.reverse,
    ).dispatch(scrollContext);
    await tester.pumpAndSettle(const Duration(milliseconds: 20));
    expect(tester.getTopLeft(find.byType(HomePage)).dy, 24,
        reason: 'collapsing or scrolling must never remove the system inset');
    expect(find.text('OpenlibExtended'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 3));
  });
  testWidgets('returning to the app refreshes installed reader choices',
      (tester) async {
    var queries = 0;
    await tester.pumpWidget(ProviderScope(
      overrides: [
        getTrendingBooks.overrideWith((ref) async => []),
        activeDownloadsProvider.overrideWith((ref) => Stream.value({})),
        installedReadersProvider.overrideWith((ref, format) async {
          queries++;
          return [];
        }),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const MainScreen(),
      ),
    ));
    await tester.pump();
    final container =
        ProviderScope.containerOf(tester.element(find.byType(MainScreen)));
    await container.read(installedReadersProvider('epub').future);
    expect(queries, 1);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await container.read(installedReadersProvider('epub').future);
    expect(queries, 2);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 3));
  });
}
