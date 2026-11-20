import 'dart:async';
// Flutter imports:
import 'package:flutter/material.dart';
import 'package:openlib/l10n/app_localizations.dart';

// Package imports:
import 'package:flutter_riverpod/flutter_riverpod.dart';

// Project imports:
import 'package:openlib/services/database.dart';
import 'package:openlib/services/library_book_details.dart';
import 'package:openlib/services/reading_status.dart';
import 'package:openlib/services/share_book.dart';
import 'package:openlib/state/state.dart'
    show libraryBooksProvider, myLibraryProvider;
import 'package:openlib/ui/components/book_info_widget.dart';
import 'package:openlib/ui/components/file_buttons_widget.dart';
import 'package:openlib/ui/components/reading_status_selector.dart';
import 'package:openlib/ui/components/snack_bar_widget.dart';

final libraryBookDetailsProvider = Provider((ref) => LibraryBookDetails());

class BookPage extends ConsumerStatefulWidget {
  const BookPage({super.key, required this.id});

  final String id;

  @override
  ConsumerState<BookPage> createState() => _BookPageState();
}

class _BookPageState extends ConsumerState<BookPage> {
  late final Future<MyBook?> bookInfo;
  MyBook? _refreshedBook;
  String? _fileName;
  ReadingStatus _status = ReadingStatus.unread;
  int _statusRequest = 0;

  @override
  void initState() {
    super.initState();
    bookInfo = _loadBook();
  }

  Future<MyBook?> _loadBook() async {
    final details = ref.read(libraryBookDetailsProvider);
    final book = await details.load(widget.id);
    if (book != null) {
      _fileName = book.getFileName();
      // The page renders without waiting on the status read; the menu
      // picks up the stored value as soon as it arrives.
      unawaited(_loadStatus());
      if (mounted) unawaited(_refreshDescription(details, book));
    }
    return book;
  }

  Future<void> _loadStatus() async {
    final fileName = _fileName;
    if (fileName == null) return;
    final request = ++_statusRequest;
    try {
      final status = await MyLibraryDb.instance.getReadingStatus(fileName);
      // A choice made while the read was in flight wins.
      if (mounted && request == _statusRequest) {
        setState(() => _status = status);
      }
    } catch (_) {
      // A failed status read leaves the menu usable at its default.
    }
  }

  Future<void> _setStatus(ReadingStatus status) async {
    final fileName = _fileName;
    if (fileName == null) return;
    _statusRequest++;
    final previous = _status;
    setState(() => _status = status);
    try {
      await MyLibraryDb.instance.setReadingStatus(fileName, status);
      if (!mounted) return;
      ref.invalidate(libraryBooksProvider);
      ref.invalidate(myLibraryProvider);
      final l10n = AppLocalizations.of(context);
      showSnackBar(
        context: context,
        message: l10n.markedAsStatus(readingStatusLabel(l10n, status)),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _status = previous);
      showSnackBar(
        context: context,
        message: AppLocalizations.of(context).statusUpdateFailed,
      );
    }
  }

  Future<void> _refreshDescription(
      LibraryBookDetails details, MyBook book) async {
    final updated = await details.refreshDescription(book);
    if (updated != null && mounted) {
      setState(() {
        _refreshedBook = updated;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.surface,
        actions: [
          FutureBuilder<MyBook?>(
              future: bookInfo,
              builder: (BuildContext context, AsyncSnapshot<MyBook?> snapshot) {
                if (!snapshot.hasData) return const SizedBox.shrink();
                final l10n = AppLocalizations.of(context);
                return PopupMenuButton<ReadingStatus>(
                  tooltip: l10n.readingStatus,
                  icon: Icon(
                    Icons.checklist_rtl,
                    color: Theme.of(context).colorScheme.tertiary,
                  ),
                  iconSize: 19.0,
                  initialValue: _status,
                  onSelected: _setStatus,
                  itemBuilder: (BuildContext menuContext) => [
                    for (final status in ReadingStatus.values)
                      PopupMenuItem(
                        value: status,
                        child: Row(
                          children: [
                            if (status == _status)
                              Icon(Icons.check,
                                  size: 18,
                                  color:
                                      Theme.of(context).colorScheme.secondary)
                            else
                              const SizedBox(width: 18),
                            const SizedBox(width: 8),
                            Text(readingStatusLabel(l10n, status)),
                          ],
                        ),
                      ),
                  ],
                );
              }),
          FutureBuilder(
              future: bookInfo,
              builder: (BuildContext context, AsyncSnapshot<MyBook?> snapshot) {
                if (snapshot.hasData &&
                    snapshot.data?.title != null &&
                    snapshot.data?.link != null) {
                  return IconButton(
                    icon: Icon(
                      Icons.share_sharp,
                      color: Theme.of(context).colorScheme.tertiary,
                    ),
                    iconSize: 19.0,
                    onPressed: () async {
                      final outcome = await shareBook(snapshot.data!.title,
                          snapshot.data!.link, snapshot.data?.thumbnail ?? '',
                          fileName: snapshot.data?.fileName,
                          format: snapshot.data?.format);
                      if (context.mounted &&
                          outcome == ShareOutcome.pathCopied) {
                        showSnackBar(
                            context: context,
                            message:
                                AppLocalizations.of(context).copiedBookPath);
                      }
                    },
                  );
                } else {
                  return const SizedBox.shrink();
                }
              })
        ],
      ),
      body: Consumer(
        builder: (BuildContext context, WidgetRef ref, _) {
          return FutureBuilder(
              future: bookInfo,
              builder: (BuildContext context, AsyncSnapshot<MyBook?> snapshot) {
                if (snapshot.hasData) {
                  return BookInfoWidget(
                      data: _refreshedBook ?? snapshot.data,
                      child: FileOpenAndDeleteButtons(
                        id: snapshot.data!.id,
                        format: snapshot.data!.format!,
                        fileName: snapshot.data!.fileName,
                        onDelete: () {
                          Navigator.of(context).pop();
                        },
                      ));
                } else if (snapshot.hasError) {
                  return Center(
                    child: Text(snapshot.toString()),
                  );
                } else {
                  return Center(
                      child: SizedBox(
                    width: 25,
                    height: 25,
                    child: CircularProgressIndicator(
                      color: Theme.of(context).colorScheme.secondary,
                    ),
                  ));
                }
              });
        },
      ),
    );
  }
}
