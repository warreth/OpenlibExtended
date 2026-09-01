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
import 'package:openlib/services/tts_service.dart';
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
        if (context.mounted) {
          Navigator.push(context,
              MaterialPageRoute(builder: (BuildContext context) {
            return EpubViewerWidget(fileName: fileName);
          }));
        }
      } catch (e) {
        if (context.mounted) {
          showSnackBar(context: context, message: "Unable to open epub!");
        }
      }
    }
  } catch (e) {
    // File doesn't exist or can't be accessed
    if (context.mounted) {
      showSnackBar(
          context: context,
          message: "File not found. The download may have failed.");
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

  static const _defaultFontSize = 16.0;
  static const _minFontSize = 10.0;
  static const _maxFontSize = 32.0;
  static const _fontSizeStep = 2.0;
  double _fontSize = _defaultFontSize;

  // Text-to-speech (mobile only): speaks the current chapter chunk by
  // chunk and follows the reader along.
  TtsService? _tts;
  TtsState _ttsState = TtsState.idle;
  List<String> _speechChunks = const [];
  int _speechChunkIndex = 0;

  @override
  void initState() {
    super.initState();
    // Initialize with standard options
    _epubReaderController = EpubController(
      document: EpubDocument.openFile(File(widget.filePath)),
      // NOTE: We'll set CFI later in onDocumentLoaded because we need to fetch it async
    );

    _loadFontSize();

    if (ttsAvailableOnPlatform()) {
      _tts = TtsService();
      _tts!.onStateChanged.listen((s) {
        if (mounted) setState(() => _ttsState = s);
      });
      _tts!.onChunkComplete(_speakNextChunk);
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkTutorial();
      _focusNode.requestFocus();
    });
  }

  Future<void> _loadFontSize() async {
    final saved = await MyLibraryDb.instance
        .getPreference('readerFontSize')
        .catchError((_) => null);
    if (saved != null && mounted) {
      final parsed = double.tryParse(saved.toString());
      if (parsed != null && parsed >= _minFontSize && parsed <= _maxFontSize) {
        setState(() => _fontSize = parsed);
      }
    }
  }

  Future<void> _changeFontSize(double delta) async {
    final next = (_fontSize + delta).clamp(_minFontSize, _maxFontSize);
    if (next == _fontSize) return;
    setState(() => _fontSize = next);
    // savePreference only accepts bool/int/String, so the double goes in
    // as text; _loadFontSize parses it back out. Writing here (not on
    // close) keeps tests free of lifecycle writes.
    await MyLibraryDb.instance
        .savePreference('readerFontSize', next.toString())
        .catchError((_) {});
  }

  // ------------------------------------------------------------------
  // Text-to-speech
  // ------------------------------------------------------------------

  /// Speaks the current chapter from wherever the reader is, then keeps
  /// going chunk by chunk until the chapter is done.
  Future<void> _startTts() async {
    final tts = _tts;
    if (tts == null) return;

    final chapter = _epubReaderController.currentValue?.chapter;
    final html = chapter?.HtmlContent ?? '';
    final text = htmlToSpeechText(html);
    if (text.isEmpty) {
      if (mounted) {
        showSnackBar(context: context, message: 'Nothing to read on this page');
      }
      return;
    }

    _speechChunks = splitIntoSpeechChunks(text);
    _speechChunkIndex = 0;
    if (_speechChunks.isEmpty) return;

    final languageOk = await tts.setLanguage('en-US');
    if (!languageOk) {
      if (mounted) {
        showSnackBar(
            context: context, message: 'No voice available for reading aloud');
      }
      return;
    }
    await tts.setRate(TtsService.defaultRate);
    await tts.speak(_speechChunks.first);
  }

  /// Advances to the next chunk, or the next chapter when this one ends.
  void _speakNextChunk() {
    final tts = _tts;
    if (tts == null || tts.state != TtsState.idle) return;

    _speechChunkIndex++;
    if (_speechChunkIndex < _speechChunks.length) {
      tts.speak(_speechChunks[_speechChunkIndex]);
      return;
    }

    // Chapter done: move to the next one; onChapterChanged picks up reading.
    _advanceToNextChapter();
  }

  /// Jumps to the next chapter. Reading continues from onChapterChanged,
  /// which fires once the view lands there.
  void _advanceToNextChapter() {
    final toc = _epubReaderController.tableOfContents();
    final current = _epubReaderController.currentValue;
    if (current == null) return;
    final currentIndex =
        toc.indexWhere((c) => c.title == current.chapter?.Title);
    if (currentIndex < 0 || currentIndex + 1 >= toc.length) {
      // End of book - nothing further to read.
      setState(() => _ttsState = TtsState.idle);
      return;
    }
    _epubReaderController.scrollTo(
      index: toc[currentIndex + 1].startIndex,
      duration: const Duration(milliseconds: 300),
    );
  }

  Future<void> _toggleTts() async {
    final tts = _tts;
    if (tts == null) return;
    switch (_ttsState) {
      case TtsState.idle:
        await _startTts();
        break;
      case TtsState.playing:
        await tts.pause();
        break;
      case TtsState.paused:
        await tts.resume();
        break;
    }
  }

  Future<void> _stopTts() async {
    await _tts?.stop();
  }

  /// Cycles the speech rate between slow / normal / fast.
  Future<void> _cycleTtsRate() async {
    final tts = _tts;
    if (tts == null) return;
    final current = tts.rate;
    final next = current < 0.35
        ? 0.5
        : current < 0.75
            ? 1.0
            : 0.25;
    await tts.setRate(next);
    // Restart the current chunk so the new rate applies immediately.
    if (_ttsState != TtsState.idle &&
        _speechChunkIndex < _speechChunks.length) {
      await tts.speak(_speechChunks[_speechChunkIndex]);
    }
    if (mounted) setState(() {});
  }

  String get _ttsRateLabel {
    final rate = _tts?.rate ?? TtsService.defaultRate;
    if (rate < 0.35) return '0.5x';
    if (rate < 0.75) return '1x';
    return '2x';
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
    _tts?.dispose();
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
        actions: [
          if (_tts != null) ...[
            IconButton(
              tooltip: _ttsState == TtsState.playing
                  ? 'Pause reading aloud'
                  : _ttsState == TtsState.paused
                      ? 'Resume reading aloud'
                      : 'Read aloud',
              icon: Icon(
                _ttsState == TtsState.playing
                    ? Icons.pause_circle
                    : _ttsState == TtsState.paused
                        ? Icons.play_circle
                        : Icons.volume_up,
                color: Theme.of(context).colorScheme.tertiary,
              ),
              onPressed: _toggleTts,
            ),
            if (_ttsState != TtsState.idle)
              IconButton(
                tooltip: 'Stop reading aloud',
                icon: Icon(Icons.stop_circle,
                    color: Theme.of(context).colorScheme.tertiary),
                onPressed: _stopTts,
              ),
            // Speech rate lives between start/stop so it is reachable
            // while listening without crowding the bar when idle.
            IconButton(
              tooltip: 'Speech speed',
              icon: Text(
                _ttsRateLabel,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  color: Theme.of(context).colorScheme.tertiary,
                ),
              ),
              onPressed: _cycleTtsRate,
            ),
          ],
          IconButton(
            tooltip: 'Decrease font size',
            icon: Icon(Icons.text_decrease,
                color: Theme.of(context).colorScheme.tertiary),
            onPressed: () => _changeFontSize(-_fontSizeStep),
          ),
          Text(
            _fontSize.round().toString(),
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w900,
              color: Theme.of(context).colorScheme.tertiary,
            ),
          ),
          IconButton(
            tooltip: 'Increase font size',
            icon: Icon(Icons.text_increase,
                color: Theme.of(context).colorScheme.tertiary),
            onPressed: () => _changeFontSize(_fontSizeStep),
          ),
        ],
      ),
      endDrawer: Drawer(
        child: EpubViewTableOfContents(controller: _epubReaderController),
      ),
      // Use standard EpubView without interfering gestures first to ensure it works
      body: Stack(
        children: [
          // SelectionArea lets readers select and copy text from the book.
          // Buttons and links inside the Html still work: SelectionArea only
          // captures drags that start on text.
          SelectionArea(
            child: Focus(
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
                      // Reading aloud continues into the chapter the
                      // reader just landed on - whether the user swiped
                      // there or TTS advanced itself.
                      if (_tts != null &&
                          _ttsState != TtsState.idle &&
                          value?.chapter?.HtmlContent != null) {
                        _startTts();
                      }
                    },
                    builders: EpubViewBuilders<DefaultBuilderOptions>(
                      options: DefaultBuilderOptions(
                        textStyle: TextStyle(
                          height: 1.25,
                          fontSize: _fontSize,
                          color: isDarkMode
                              ? const Color(0xfff5f5f5)
                              : Colors.black,
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
