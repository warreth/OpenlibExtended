// Built-in PDF reader for every platform, powered by pdfrx (PDFium).
// Replaces the old split of mobile-only flutter_pdfview plus a desktop
// shell-out to the system viewer - one interactive viewer everywhere,
// with text selection built in.

// Flutter imports:
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:openlib/l10n/app_localizations.dart';

// Package imports:
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_file/open_file.dart';
import 'package:pdfrx/pdfrx.dart';

// Project imports:
import 'package:openlib/services/files.dart' show getFilePath;
import 'package:openlib/ui/components/snack_bar_widget.dart';

import 'package:openlib/state/state.dart'
    show
        filePathProvider,
        openPdfWithExternalAppProvider,
        getBookPosition,
        savePdfPosition;

Future<void> launchPdfViewer(
    {required String fileName,
    required BuildContext context,
    required WidgetRef ref}) async {
  bool openWithExternalApp = ref.watch(openPdfWithExternalAppProvider);

  // The user can always prefer the external app; pdfrx covers every
  // platform in-app otherwise.
  if (openWithExternalApp) {
    try {
      String path = await getFilePath(fileName);
      await OpenFile.open(path, linuxByProcess: true, type: "application/pdf");
    } catch (e) {
      if (context.mounted) {
        showSnackBar(
            context: context,
            message: "File not found. The download may have failed.");
      }
    }
  } else {
    Navigator.push(context, MaterialPageRoute(builder: (BuildContext context) {
      return PdfViewPage(fileName: fileName);
    }));
  }
}

class PdfViewPage extends ConsumerStatefulWidget {
  const PdfViewPage({super.key, required this.fileName});

  final String fileName;

  @override
  ConsumerState<ConsumerStatefulWidget> createState() => _PdfViewPageState();
}

/// Saved positions are stored as decimal strings; anything unparsable
/// or out of range means "start from the top".
@visibleForTesting
int initialPageFor(String? saved) {
  final page = int.tryParse(saved ?? '');
  if (page == null || page < 1) return 1;
  return page;
}

class _PdfViewPageState extends ConsumerState<PdfViewPage> {
  final PdfViewerController _controller = PdfViewerController();
  Timer? _positionSaveTimer;
  DateTime _lastSaved = DateTime.fromMillisecondsSinceEpoch(0);
  int _page = 0;
  int _pageCount = 0;

  static const _saveInterval = Duration(seconds: 30);
  static const _saveDebounce = Duration(seconds: 5);

  @override
  void initState() {
    super.initState();
    // A dead process must not eat the reading position: save on a timer
    // while reading, on background, and on leave (deactivate).
    _positionSaveTimer = Timer.periodic(_saveInterval, (_) => _savePosition());
  }

  @override
  void dispose() {
    _positionSaveTimer?.cancel();
    super.dispose();
  }

  Future<void> _savePosition() async {
    // Debounce: the timer plus page-change saves must not write more
    // often than the debounce window.
    if (_page < 1) return;
    final now = DateTime.now();
    if (now.difference(_lastSaved) < _saveDebounce) return;
    _lastSaved = now;
    try {
      await savePdfPosition(widget.fileName, _page);
    } catch (_) {
      // A failed position write never takes the reader down.
    }
  }

  @override
  Widget build(BuildContext context) {
    final filePath = ref.watch(filePathProvider(widget.fileName));
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        // Use surface color in dark mode so it's not white
        backgroundColor: isDarkMode
            ? Theme.of(context).colorScheme.surface
            : Theme.of(context).colorScheme.primary,
        title: Text(AppLocalizations.of(context).appTitle),
        titleTextStyle: Theme.of(context).textTheme.displayLarge,
        leading: IconButton(
          icon: Icon(Icons.arrow_back,
              color: Theme.of(context).colorScheme.tertiary),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          IconButton(
            tooltip: AppLocalizations.of(context).previousPage,
            onPressed: () => _controller.goToPage(
                pageNumber: (_controller.pageNumber ?? 1) - 1),
            icon: Icon(Icons.arrow_left,
                size: 25, color: Theme.of(context).colorScheme.tertiary),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Center(
              child: Text(
                '$_page / $_pageCount',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                  color: Theme.of(context).colorScheme.tertiary,
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: AppLocalizations.of(context).nextPage,
            onPressed: () => _controller.goToPage(
                pageNumber: (_controller.pageNumber ?? 0) + 1),
            icon: Icon(Icons.arrow_right,
                size: 25, color: Theme.of(context).colorScheme.tertiary),
          ),
        ],
      ),
      body: filePath.when(
        data: (path) => ref.watch(getBookPosition(widget.fileName)).when(
              data: (saved) {
                return PdfViewer.file(
                  path,
                  controller: _controller,
                  initialPageNumber: initialPageFor(saved),
                  params: PdfViewerParams(
                    behaviorControlParams: const PdfViewerBehaviorControlParams(
                        // Default keeps trailing pages waiting 100ms;
                        // loading them immediately feels snappier.
                        trailingPageLoadingDelay: Duration.zero),
                    onPageChanged: (page) {
                      // Real-time page indicator; _savePosition
                      // debounces the actual disk writes.
                      if (page == null || page < 1) return;
                      setState(() {
                        _page = page;
                        _pageCount = _controller.isReady
                            ? _controller.pageCount
                            : _pageCount;
                      });
                      _savePosition();
                    },
                  ),
                );
              },
              error: (err, stack) =>
                  Center(child: Text("Error loading book: $err")),
              loading: () => Center(
                child: CircularProgressIndicator(
                  color: Theme.of(context).colorScheme.secondary,
                ),
              ),
            ),
        error: (error, stack) {
          return Scaffold(
            appBar: AppBar(
              backgroundColor: Theme.of(context).colorScheme.primary,
              title: Text(AppLocalizations.of(context).appTitle),
              titleTextStyle: Theme.of(context).textTheme.displayLarge,
            ),
            body: Center(child: Text(error.toString())),
          );
        },
        loading: () {
          return Scaffold(
            appBar: AppBar(
              backgroundColor: Theme.of(context).colorScheme.primary,
              title: Text(AppLocalizations.of(context).appTitle),
              titleTextStyle: Theme.of(context).textTheme.displayLarge,
            ),
            body: Center(
              child: SizedBox(
                width: 25,
                height: 25,
                child: CircularProgressIndicator(
                  color: Theme.of(context).colorScheme.secondary,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
