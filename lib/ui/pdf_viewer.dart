// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:flutter_pdfview/flutter_pdfview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_file/open_file.dart';
import 'package:url_launcher/url_launcher.dart';

// Project imports:
import 'package:openlib/services/files.dart' show getFilePath;
import 'package:openlib/services/platform_utils.dart';
import 'package:openlib/ui/components/snack_bar_widget.dart';

import 'package:openlib/state/state.dart'
    show
        filePathProvider,
        pdfCurrentPage,
        totalPdfPage,
        savePdfState,
        openPdfWithExternalAppProvider,
        getBookPosition;

Future<void> launchPdfViewer(
    {required String fileName,
    required BuildContext context,
    required WidgetRef ref}) async {
  bool openWithExternalApp = ref.watch(openPdfWithExternalAppProvider);

  // On desktop, always open with external app since flutter_pdfview is mobile-only
  if (PlatformUtils.isDesktop || openWithExternalApp) {
    try {
      String path = await getFilePath(fileName);
      await OpenFile.open(path, linuxByProcess: true, type: "application/pdf");
    } catch (e) {
      // File doesn't exist or can't be accessed
      // ignore: use_build_context_synchronously
      showSnackBar(
          context: context,
          message: "File not found. The download may have failed.");
    }
  } else {
    Navigator.push(context, MaterialPageRoute(builder: (BuildContext context) {
      return PdfView(
        fileName: fileName,
      );
    }));
  }
}

class PdfView extends ConsumerStatefulWidget {
  const PdfView({super.key, required this.fileName});

  final String fileName;

  @override
  ConsumerState<ConsumerStatefulWidget> createState() => _PdfViewState();
}

class _PdfViewState extends ConsumerState<PdfView> {
  @override
  Widget build(BuildContext context) {
    final filePath = ref.watch(filePathProvider(widget.fileName));
    return filePath.when(data: (data) {
      return PdfViewer(filePath: data, fileName: widget.fileName);
    }, error: (error, stack) {
      return Scaffold(
        appBar: AppBar(
          backgroundColor: Theme.of(context).colorScheme.primary,
          title: const Text("OpenlibExtended"),
          titleTextStyle: Theme.of(context).textTheme.displayLarge,
        ),
        body: Center(child: Text(error.toString())),
      );
    }, loading: () {
      return Scaffold(
        appBar: AppBar(
          backgroundColor: Theme.of(context).colorScheme.primary,
          title: const Text("OpenlibExtended"),
          titleTextStyle: Theme.of(context).textTheme.displayLarge,
        ),
        body: Center(
            child: SizedBox(
          width: 25,
          height: 25,
          child: CircularProgressIndicator(
            color: Theme.of(context).colorScheme.secondary,
          ),
        )),
      );
    });
  }
}

class PdfViewer extends ConsumerStatefulWidget {
  const PdfViewer({super.key, required this.filePath, required this.fileName});

  final String filePath;
  final String fileName;

  @override
  ConsumerState<ConsumerStatefulWidget> createState() => _PdfViewerState();
}

class _PdfViewerState extends ConsumerState<PdfViewer> {
  late PDFViewController controller;
  final Set<int> _activePointers = {};

  @override
  void initState() {
    super.initState();
  }

  @override
  void deactivate() {
    // Save PDF state on all platforms (mobile and desktop)
    savePdfState(widget.fileName, ref);
    super.deactivate();
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _openPdfWithDefaultViewer(String fileName) async {
    debugPrint("Opening : $fileName");
    final fileUrl = Uri.parse(fileName);
    if (await canLaunchUrl(fileUrl)) {
      await launchUrl(fileUrl);
    } else {
      // ignore: use_build_context_synchronously
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
          'Could not open the PDF',
          textAlign: TextAlign.center,
        )),
      );
    }
  }

  void _goToNextPage() {
    final currentPage = ref.read(pdfCurrentPage);
    final totalPages = ref.read(totalPdfPage);
    if (currentPage + 1 < totalPages) {
      ref.read(pdfCurrentPage.notifier).state = currentPage + 1;
      controller.setPage(currentPage + 1);
    } else {
      ref.read(pdfCurrentPage.notifier).state = 0;
      controller.setPage(0);
    }
  }

  void _goToPreviousPage() {
    final currentPage = ref.read(pdfCurrentPage);
    final totalPages = ref.read(totalPdfPage);
    if (currentPage != 0) {
      ref.read(pdfCurrentPage.notifier).state = currentPage - 1;
      controller.setPage(currentPage - 1);
    } else {
      ref.read(pdfCurrentPage.notifier).state = totalPages - 1;
      controller.setPage(totalPages - 1);
    }
  }

  @override
  Widget build(BuildContext context) {
    // On desktop, use external PDF viewer with a button
    bool useExternalViewer = PlatformUtils.isDesktop;
    final currentPage = ref.watch(pdfCurrentPage);
    final totalPages = ref.watch(totalPdfPage);
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.primary,
        title: const Text("OpenlibExtended"),
        titleTextStyle: Theme.of(context).textTheme.displayLarge,
        actions: !useExternalViewer
            ? [
                IconButton(
                    onPressed: _goToPreviousPage,
                    icon: const Icon(
                      Icons.arrow_left,
                      size: 25,
                    )),
                Text(
                    '${(currentPage + 1).toString()} / ${totalPages.toString()}'),
                IconButton(
                    onPressed: _goToNextPage,
                    icon: const Icon(
                      Icons.arrow_right,
                      size: 25,
                    )),
              ]
            : [],
      ),
      body: !useExternalViewer
          ? ref.watch(getBookPosition(widget.fileName)).when(
              data: (data) {
                return _buildTapNavigationWrapper(
                  PDFView(
                    swipeHorizontal: true,
                    fitEachPage: true,
                    fitPolicy: FitPolicy.BOTH,
                    filePath: widget.filePath,
                    onViewCreated: (controller) {
                      this.controller = controller;
                    },
                    defaultPage: int.parse(data ?? '0'),
                    onPageChanged: (page, total) {
                      ref.read(pdfCurrentPage.notifier).state = page ?? 0;
                      ref.read(totalPdfPage.notifier).state = total ?? 0;
                    },
                  ),
                );
              },
              error: (error, stackTrace) {
                return _buildTapNavigationWrapper(
                  PDFView(
                    swipeHorizontal: true,
                    fitEachPage: true,
                    fitPolicy: FitPolicy.BOTH,
                    filePath: widget.filePath,
                    onViewCreated: (controller) {
                      this.controller = controller;
                    },
                    onPageChanged: (page, total) {
                      ref.read(pdfCurrentPage.notifier).state = page ?? 0;
                      ref.read(totalPdfPage.notifier).state = total ?? 0;
                    },
                  ),
                );
              },
              loading: () {
                return Center(
                    child: SizedBox(
                  width: 25,
                  height: 25,
                  child: CircularProgressIndicator(
                    color: Theme.of(context).colorScheme.secondary,
                  ),
                ));
              },
            )
          : Center(
              child: TextButton(
                style: TextButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.secondary,
                    textStyle: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                    )),
                onPressed: () async {
                  await _openPdfWithDefaultViewer("file://${widget.filePath}");
                  // ignore: use_build_context_synchronously
                  Navigator.pop(context);
                },
                child: const Padding(
                  padding: EdgeInsets.all(8.0),
                  child: Text(
                    "Open with System's PDF Viewer",
                  ),
                ),
              ),
            ),
    );
  }

  Widget _buildTapNavigationWrapper(Widget child) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (event) => _activePointers.add(event.pointer),
      onPointerUp: (event) {
        _activePointers.remove(event.pointer);

        // Only handle navigation on single-finger taps
        if (_activePointers.isEmpty) {
          final screenWidth = MediaQuery.of(context).size.width;
          final tapPosition = event.position.dx;

          // Divide screen into three zones: left (30%), center (40%), right (30%)
          if (tapPosition < screenWidth * 0.3) {
            // Left zone - previous page
            _goToPreviousPage();
          } else if (tapPosition > screenWidth * 0.7) {
            // Right zone - next page
            _goToNextPage();
          }
          // Center zone (30-70%) - no action, allows zooming and other interactions
        }
      },
      onPointerCancel: (event) => _activePointers.remove(event.pointer),
      child: child, // Direct child, no overlay
    );
  }
}
