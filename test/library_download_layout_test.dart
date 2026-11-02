import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openlib/l10n/app_localizations.dart';
import 'package:openlib/services/download_manager.dart';
import 'package:openlib/state/state.dart';
import 'package:openlib/ui/mylibrary_page.dart';

void main() {
  testWidgets(
      'library downloads scroll below the fixed title in a short window',
      (tester) async {
    tester.view.physicalSize = const Size(800, 300);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        libraryBooksProvider.overrideWith((ref) async => []),
        libraryTagsProvider.overrideWith((ref) async => {}),
        activeDownloadsProvider.overrideWith((ref) => Stream.value({
              for (var i = 0; i < 3; i++)
                '$i': DownloadTask(
                    id: '$i',
                    md5: '$i',
                    title: 'Book $i',
                    mirrors: [],
                    format: 'epub',
                    link: 'https://example.org/$i',
                    status: DownloadStatus.downloading),
            })),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(body: MyLibraryPage()),
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.takeException(), isNull);
    final titleY = tester.getTopLeft(find.text('My Library')).dy;
    // Start beside the downloads' nested list so the page owns the gesture.
    await tester.dragFrom(const Offset(5, 240), const Offset(0, -150));
    await tester.pump(const Duration(milliseconds: 500));
    expect(tester.takeException(), isNull);
    expect(tester.getTopLeft(find.text('My Library')).dy, titleY);
    final pageScroll = tester.state<ScrollableState>(find
        .descendant(
            of: find.byType(SingleChildScrollView).first,
            matching: find.byType(Scrollable))
        .first);
    expect(pageScroll.position.pixels, greaterThan(0));
  });
}
