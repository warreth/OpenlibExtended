// Dart imports:
import 'dart:io';

// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:epub_view/epub_view.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_file/open_file.dart';

// Project imports:
import 'package:openlib/services/files.dart' show getFilePath;
import 'package:openlib/services/platform_utils.dart';
import 'package:openlib/ui/components/snack_bar_widget.dart';
import 'package:openlib/state/state.dart'
    show
        filePathProvider,
        saveEpubState,
        getBookPosition,
        openEpubWithExternalAppProvider;

Future<void> launchEpubViewer({
  required String fileName,
  required BuildContext context,
  required WidgetRef ref,
}) async {
  String path = await getFilePath(fileName);
  bool openWithExternalApp = ref.watch(openEpubWithExternalAppProvider);

  // Check if user wants external app
  if (openWithExternalApp) {
    await OpenFile.open(path, linuxByProcess: true, type: "application/epub+zip");
  } else {
    try {
      // Use internal Epub Viewer for all platforms (epub_view supports desktop)
      // ignore: use_build_context_synchronously
      Navigator.push(context, MaterialPageRoute(builder: (BuildContext context) {
        return EpubViewerWidget(fileName: fileName);
      }));
    } catch (e) {
      // ignore: use_build_context_synchronously
      showSnackBar(context: context, message: "Unable to open epub!");
    }
  }
}

class EpubViewerWidget extends ConsumerStatefulWidget {
  const EpubViewerWidget({super.key, required this.fileName});

  final String fileName;

  @override
  ConsumerState<ConsumerStatefulWidget> createState() => _EpubViewState();
}

class _EpubViewState extends ConsumerState<EpubViewerWidget> {
  @override
  Widget build(BuildContext context) {
    final filePath = ref.watch(filePathProvider(widget.fileName));
    return filePath.when(
      data: (data) {
        return EpubViewer(filePath: data, fileName: widget.fileName);
      },
      error: (error, stack) {
        return Scaffold(
          appBar: AppBar(
            backgroundColor: Theme.of(context).colorScheme.primary,
            title: const Text("Openlib"),
            titleTextStyle: Theme.of(context).textTheme.displayLarge,
          ),
          body: Center(child: Text(error.toString())),
        );
      },
      loading: () {
        return Scaffold(
          appBar: AppBar(
            backgroundColor: Theme.of(context).colorScheme.primary,
            title: const Text("Openlib"),
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
    );
  }
}

class EpubViewer extends ConsumerStatefulWidget {
  const EpubViewer({super.key, required this.filePath, required this.fileName});

  final String filePath;
  final String fileName;

  @override
  ConsumerState<EpubViewer> createState() => _EpubViewerState();
}

class _EpubViewerState extends ConsumerState<EpubViewer> {
  late EpubController _epubReaderController;
  String? epubConf;
  final Set<int> _activePointers = {};

  @override
  void initState() {
    super.initState();
    _epubReaderController = EpubController(
      document: EpubDocument.openFile(File(widget.filePath)),
    );
  }

  @override
  void deactivate() {
    // Save EPUB state on all platforms (mobile and desktop)
    saveEpubState(widget.fileName, epubConf, ref);
    super.deactivate();
  }

  @override
  void dispose() {
    _epubReaderController.dispose();
    super.dispose();
  }

  void _navigateToPreviousChapter() {
    final currentValue = _epubReaderController.currentValue;
    if (currentValue != null && currentValue.chapterNumber > 0) {
      _epubReaderController.jumpTo(index: currentValue.chapterNumber - 1);
    }
  }

  void _navigateToNextChapter() {
    final currentValue = _epubReaderController.currentValue;
    if (currentValue != null) {
      // Try to go to next chapter (will fail silently if at last chapter)
      _epubReaderController.jumpTo(index: currentValue.chapterNumber + 1);
    }
  }

  @override
  Widget build(BuildContext context) {
    final position = ref.watch(getBookPosition(widget.fileName));
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.primary,
        title: const Text("Openlib"),
        titleTextStyle: Theme.of(context).textTheme.displayLarge,
      ),
      endDrawer: Drawer(
        child: EpubViewTableOfContents(controller: _epubReaderController),
      ),
      body: position.when(
        data: (data) {
          return _buildTapNavigationWrapper(
            EpubView(
              onDocumentLoaded: (doc) {
                Future.delayed(const Duration(milliseconds: 20), () {
                  if (data != null && data.isNotEmpty) {
                    _epubReaderController.gotoEpubCfi(data);
                  }
                });
              },
              onChapterChanged: (value) {
                epubConf = _epubReaderController.generateEpubCfi();
              },
              builders: EpubViewBuilders<DefaultBuilderOptions>(
                options: const DefaultBuilderOptions(),
                chapterDividerBuilder: (_) => const Divider(),
              ),
              controller: _epubReaderController,
            ),
          );
        },
        error: (err, _) {
          return _buildTapNavigationWrapper(
            EpubView(
              onChapterChanged: (value) {
                epubConf = _epubReaderController.generateEpubCfi();
              },
              builders: EpubViewBuilders<DefaultBuilderOptions>(
                options: const DefaultBuilderOptions(),
                chapterDividerBuilder: (_) => const Divider(),
              ),
              controller: _epubReaderController,
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
            ),
          );
        },
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
            // Left zone - previous chapter
            _navigateToPreviousChapter();
          } else if (tapPosition > screenWidth * 0.7) {
            // Right zone - next chapter
            _navigateToNextChapter();
          }
          // Center zone (30-70%) - no action, allows text selection
        }
      },
      onPointerCancel: (event) => _activePointers.remove(event.pointer),
      child: child, // Direct child, no overlay
    );
  }
}
