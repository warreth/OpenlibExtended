// Regression test for issue #117: "Manual Download" on a libgen result
// opened a WebView on the get.php link, which answers with a file
// attachment. The WebView never fired onLoadStop, so the "Preparing
// download..." overlay stayed up forever. A direct file link must go
// straight to the download manager instead.

// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

// Project imports:
import 'package:openlib/l10n/app_localizations.dart';
import 'package:openlib/services/annas_archieve.dart';
import 'package:openlib/services/database.dart';
import 'package:openlib/services/download_manager.dart';
import 'package:openlib/state/state.dart';
import 'package:openlib/ui/book_info_page.dart';
import 'package:openlib/ui/webview_page.dart';

const _getPhpUrl =
    'https://libgen.li/get.php?md5=7fa1933240367d50818e83f75867605e'
    '&key=HHTIQRL70FJI3D1U';

class _RecordingManager implements DownloadManager {
  final List<DownloadTask> added = [];

  @override
  Future<void> addDownload(DownloadTask task) async {
    added.add(task);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

BookInfoData _book({String? mirror}) => BookInfoData(
      title: 'The Forever Dog Life',
      author: 'Karen Shaw Becker',
      thumbnail: null,
      publisher: 'HarperCollins',
      info: 'English [en], epub',
      link: 'https://libgen.li/ads.php?md5=7fa1933240367d50818e83f75867605e',
      md5: '7fa1933240367d50818e83f75867605e',
      format: 'epub',
      mirror: mirror,
      description: null,
    );

Future<_RecordingManager> _pumpBook(
    WidgetTester tester, BookInfoData data) async {
  final manager = _RecordingManager();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        checkIdExists.overrideWith((ref, id) async => false),
        getBookByIdProvider.overrideWith((ref, id) async => null),
        showManualDownloadButtonProvider.overrideWith((ref) => true),
        downloadManagerProvider.overrideWithValue(manager),
        myLibraryProvider.overrideWith((ref) async => const <MyBook>[]),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: ActionButtonWidget(data: data)),
      ),
    ),
  );
  // The loading spinner animates forever, so pumpAndSettle would never
  // return; two frames are enough for the overridden futures to resolve.
  await tester.pump();
  await tester.pump();
  return manager;
}

void main() {
  testWidgets('a libgen get.php mirror downloads without the WebView',
      (tester) async {
    final manager = await _pumpBook(tester, _book(mirror: _getPhpUrl));

    await tester.tap(find.text('Manual Download'));
    await tester.pump();
    await tester.pump();

    expect(manager.added, hasLength(1),
        reason: 'the direct link must start a download');
    expect(manager.added.single.mirrors, [_getPhpUrl]);
    expect(manager.added.single.md5, '7fa1933240367d50818e83f75867605e');
    expect(find.byType(Webview), findsNothing,
        reason: 'a file link cannot be scraped in a WebView');
  });

  testWidgets('a book without a mirror reports instead of downloading',
      (tester) async {
    final manager = await _pumpBook(tester, _book());

    await tester.tap(find.text('Manual Download'));
    await tester.pump();

    expect(manager.added, isEmpty);
    expect(find.text('No mirrors available!'), findsOneWidget);
  });
}
