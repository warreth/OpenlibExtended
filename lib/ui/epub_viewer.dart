// Dart imports:
import 'dart:io';

// Flutter imports:
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// Package imports:
import 'package:epub_view/epub_view.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_file/open_file.dart';

// Project imports:
import 'package:openlib/services/files.dart' show getFilePath;
import 'package:openlib/ui/components/snack_bar_widget.dart';
import 'package:openlib/state/state.dart'
    show
        filePathProvider,
        saveEpubState,
        getBookPosition,
        openEpubWithExternalAppProvider;
import 'package:openlib/services/database.dart' show MyLibraryDb;
import 'package:openlib/services/platform_utils.dart';
import 'package:openlib/ui/components/reader_help_overlay.dart';

Future<void> launchEpubViewer({
  required String fileName,
  required BuildContext context,
  required WidgetRef ref,
}) async {
  try {
    String path = await getFilePath(fileName);
    bool openWithExternalApp = ref.watch(openEpubWithExternalAppProvider);

    // Check if user wants external app
    if (openWithExternalApp) {
      await OpenFile.open(path,
          linuxByProcess: true, type: "application/epub+zip");
    } else {
      try {
        // Use internal Epub Viewer for all platforms (epub_view supports desktop)
        // ignore: use_build_context_synchronously
        Navigator.push(context,
            MaterialPageRoute(builder: (BuildContext context) {
          return EpubViewerWidget(fileName: fileName);
        }));
      } catch (e) {
        // ignore: use_build_context_synchronously
        showSnackBar(context: context, message: "Unable to open epub!");
      }
    }
  } catch (e) {
    // File doesn't exist or can't be accessed
    // ignore: use_build_context_synchronously
    showSnackBar(
        context: context,
        message: "File not found. The download may have failed.");
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
            title: const Text("OpenlibExtended"),
            titleTextStyle: Theme.of(context).textTheme.displayLarge,
          ),
          body: Center(child: Text(error.toString())),
        );
      },
      loading: () {
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
  bool _showTutorial = false;
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    // Initialize with standard options
    _epubReaderController = EpubController(
      document: EpubDocument.openFile(File(widget.filePath)),
      // NOTE: We'll set CFI later in onDocumentLoaded because we need to fetch it async
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkTutorial();
      _focusNode.requestFocus();
    });
  }

  Future<void> _checkTutorial() async {
    try {
      final prefs = MyLibraryDb.instance;
      final hasSeen = await prefs
              .getPreference('hasSeenReaderTutorial')
              .catchError((_) => 0) ??
          0;

      if (hasSeen == 0) {
        if (mounted) setState(() => _showTutorial = true);
        await prefs.savePreference('hasSeenReaderTutorial', 1);
      }
    } catch (e) {
      debugPrint("Error checking tutorial: $e");
    }
  }

  @override
  void deactivate() {
    // Save EPUB state when leaving
    final cfi = _epubReaderController.generateEpubCfi();
    saveEpubState(widget.fileName, cfi, ref);
    super.deactivate();
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _epubReaderController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Watch for saved position
    final positionAsync = ref.watch(getBookPosition(widget.fileName));
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        // Use surface color in dark mode so it's not white
        backgroundColor: isDarkMode
            ? Theme.of(context).colorScheme.surface
            : Theme.of(context).colorScheme.primary,
        title: const Text("OpenlibExtended"),
        titleTextStyle: Theme.of(context).textTheme.displayLarge,
        leading: IconButton(
          icon: Icon(Icons.arrow_back,
              color: Theme.of(context).colorScheme.tertiary),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      endDrawer: Drawer(
        child: EpubViewTableOfContents(controller: _epubReaderController),
      ),
      // Use standard EpubView without interfering gestures first to ensure it works
      body: Stack(
        children: [
          Focus(
            focusNode: _focusNode,
            autofocus: true,
            child: positionAsync.when(
              data: (savedCfi) {
                return EpubView(
                  controller: _epubReaderController,
                  onDocumentLoaded: (document) {
                    // Restore position if available
                    if (savedCfi != null && savedCfi.isNotEmpty) {
                      _epubReaderController.gotoEpubCfi(savedCfi);
                    }
                  },
                  onChapterChanged: (value) {
                    // Optional: auto-save on chapter change
                    // saveEpubState(widget.fileName, _epubReaderController.generateEpubCfi(), ref);
                  },
                  builders: EpubViewBuilders<DefaultBuilderOptions>(
                    options: DefaultBuilderOptions(
                      textStyle: TextStyle(
                        height: 1.25,
                        fontSize: 16,
                        color:
                            isDarkMode ? const Color(0xfff5f5f5) : Colors.black,
                      ),
                    ),
                    chapterDividerBuilder: (_) => const Divider(),
                  ),
                );
              },
              loading: () => Center(
                child: CircularProgressIndicator(
                  color: Theme.of(context).colorScheme.secondary,
                ),
              ),
              error: (err, stack) =>
                  Center(child: Text("Error loading book: $err")),
            ),
          ),
          if (_showTutorial)
            ReaderHelpOverlay(
              isDesktop: PlatformUtils.isDesktop,
              onDismiss: () => setState(() => _showTutorial = false),
            ),
        ],
      ),
    );
  }
}
