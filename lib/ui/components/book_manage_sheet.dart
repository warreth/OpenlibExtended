// Flutter imports:
import 'package:flutter/material.dart';
import 'package:openlib/l10n/app_localizations.dart';

// Package imports:
import 'package:flutter_riverpod/flutter_riverpod.dart';

// Project imports:
import 'package:openlib/services/reading_status.dart';
import 'package:openlib/state/state.dart';
import 'package:openlib/ui/components/reading_status_selector.dart';
import 'package:openlib/ui/components/snack_bar_widget.dart';

/// Bottom sheet for one library book: its reading status and its tags.
/// The status choice is manual, so books opened in an external reader can
/// still be marked In Progress or Completed.
class BookManageSheet extends ConsumerStatefulWidget {
  const BookManageSheet({
    super.key,
    required this.bookId,
    required this.fileName,
    required this.title,
    required this.initialStatus,
  });

  final String bookId;
  final String fileName;
  final String title;
  final ReadingStatus initialStatus;

  @override
  ConsumerState<BookManageSheet> createState() => _BookManageSheetState();
}

class _BookManageSheetState extends ConsumerState<BookManageSheet> {
  late Future<Set<String>> _bookTags;
  late ReadingStatus _status;
  bool _savingStatus = false;

  @override
  void initState() {
    super.initState();
    _bookTags = dataBase.getTags(widget.bookId);
    _status = widget.initialStatus;
  }

  void _reloadTags() {
    setState(() {
      _bookTags = dataBase.getTags(widget.bookId);
    });
    ref.invalidate(myLibraryProvider);
    ref.invalidate(libraryBooksProvider);
    ref.invalidate(libraryTagsProvider);
  }

  Future<void> _setStatus(ReadingStatus status) async {
    if (status == _status || _savingStatus) return;
    final previous = _status;
    setState(() {
      _status = status;
      _savingStatus = true;
    });
    try {
      await dataBase.setReadingStatus(widget.fileName, status);
      ref.invalidate(myLibraryProvider);
      ref.invalidate(libraryBooksProvider);
    } catch (_) {
      if (mounted) {
        setState(() => _status = previous);
        showSnackBar(
          context: context,
          message: AppLocalizations.of(context).statusUpdateFailed,
        );
      }
    } finally {
      if (mounted) setState(() => _savingStatus = false);
    }
  }

  Future<void> _addTag(String rawTag) async {
    final tag = rawTag.trim();
    if (tag.isEmpty) return;
    await dataBase.addTag(widget.bookId, tag);
    _reloadTags();
  }

  Future<void> _removeTag(String tag) async {
    await dataBase.removeTag(widget.bookId, tag);
    // Drop the tag from active filters if it just vanished everywhere.
    final remaining = await dataBase.getAllTags();
    if (!remaining.contains(tag)) {
      final filter = Set<String>.of(ref.read(libraryTagFilterProvider));
      filter.remove(tag);
      ref.read(libraryTagFilterProvider.notifier).state = filter;
    }
    _reloadTags();
  }

  Future<void> _createTag() async {
    final controller = TextEditingController();
    final dialogL10n = AppLocalizations.of(context);
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(dialogL10n.newCollection),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(hintText: dialogL10n.collectionNameHint),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(dialogL10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: Text(dialogL10n.add),
          ),
        ],
      ),
    );
    if (name != null && name.trim().isNotEmpty) {
      await _addTag(name);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final allTags =
        ref.watch(libraryTagsProvider).valueOrNull ?? const <String>{};
    return FutureBuilder<Set<String>>(
      future: _bookTags,
      builder: (context, snapshot) {
        final bookTags = snapshot.data ?? const <String>{};
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(
                  l10n.manageCollectionsHint,
                  style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  l10n.readingStatus,
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                ReadingStatusSelector(
                  status: _status,
                  enabled: !_savingStatus,
                  onChanged: _setStatus,
                ),
                const Divider(height: 28),
                Text(
                  l10n.collectionsLabel,
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final tag in allTags)
                      FilterChip(
                        label: Text(tag, style: const TextStyle(fontSize: 12)),
                        selected: bookTags.contains(tag),
                        onSelected: (selected) =>
                            selected ? _addTag(tag) : _removeTag(tag),
                      ),
                    ActionChip(
                      label: Text(l10n.newCollection,
                          style: const TextStyle(fontSize: 12)),
                      avatar: const Icon(Icons.add, size: 15),
                      onPressed: _createTag,
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
