import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openlib/l10n/app_localizations.dart';
import 'package:openlib/services/download_manager.dart';
import 'package:openlib/state/state.dart';
import 'package:openlib/ui/components/active_downloads_widget.dart';

class _Downloads implements DownloadManager {
  final changes = StreamController<Map<String, DownloadTask>>.broadcast();
  final removed = <String>[];
  final tasks = <String, DownloadTask>{
    'failed': DownloadTask(
        id: 'failed',
        md5: 'failed',
        title: 'Failed book',
        mirrors: [],
        format: 'epub',
        link: 'https://example.com/book',
        status: DownloadStatus.failed,
        errorMessage: 'No working mirrors available!'),
    'active': DownloadTask(
        id: 'active',
        md5: 'active',
        title: 'Active book',
        mirrors: [],
        format: 'epub',
        link: 'https://example.com/other',
        status: DownloadStatus.downloading),
  };

  @override
  void removeDownload(String id) {
    removed.add(id);
    tasks.remove(id);
    changes.add(Map.of(tasks));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('failed cards swipe away and stay removed when panel remounts', (tester) async {
    final manager = _Downloads();
    addTearDown(manager.changes.close);
    Widget panel() => ProviderScope(overrides: [
      downloadManagerProvider.overrideWithValue(manager),
      activeDownloadsProvider.overrideWith((ref) => manager.changes.stream),
    ], child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const Scaffold(body: ActiveDownloadsWidget()),
    ));
    await tester.pumpWidget(panel());
    manager.changes.add(Map.of(manager.tasks));
    await tester.pump();
    await tester.pump();
    await tester.drag(find.text('Failed book'), const Offset(-700, 0));
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump(const Duration(milliseconds: 350));
    expect(manager.removed, ['failed']);
    expect(find.text('Failed book'), findsNothing);
    expect(find.text('Active book'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(panel());
    manager.changes.add(Map.of(manager.tasks));
    await tester.pump();
    await tester.pump();
    expect(find.text('No working mirrors available!'), findsNothing);
    expect(find.text('Active book'), findsOneWidget);
  });

  testWidgets('close removes a failed card while keeping an active download',
      (tester) async {
    final manager = _Downloads();
    addTearDown(manager.changes.close);
    await tester.pumpWidget(ProviderScope(
        overrides: [
          downloadManagerProvider.overrideWithValue(manager),
          activeDownloadsProvider.overrideWith((ref) => manager.changes.stream),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(body: ActiveDownloadsWidget()),
        )));
    manager.changes.add(Map.of(manager.tasks));
    await tester.pump();
    await tester.pump();
    expect(find.text('No working mirrors available!'), findsOneWidget);
    await tester.tap(find.byTooltip('Close'));
    await tester.pump();
    await tester.pump();
    expect(manager.removed, ['failed']);
    expect(find.text('Failed book'), findsNothing);
    expect(find.text('No working mirrors available!'), findsNothing);
    expect(find.text('Active book'), findsOneWidget);
  });
}
