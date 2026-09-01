// Flutter imports:
import 'package:flutter/material.dart';
import 'package:openlib/l10n/app_localizations.dart';

// Package imports:
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';

// Project imports:
import 'package:openlib/services/files.dart' show syncLibraryWithDisk;
import 'package:openlib/services/library_organization.dart';
import 'package:openlib/services/platform_utils.dart';
import 'package:openlib/state/state.dart';
import 'package:openlib/ui/components/active_downloads_widget.dart';
import 'package:openlib/ui/components/book_card_widget.dart';
import 'package:openlib/ui/components/error_widget.dart';
import 'package:openlib/ui/components/page_title_widget.dart';
import 'package:openlib/ui/extensions.dart';
import 'package:openlib/ui/mybook_page.dart';

class MyLibraryPage extends ConsumerStatefulWidget {
  const MyLibraryPage({super.key});

  @override
  ConsumerState<MyLibraryPage> createState() => _MyLibraryPageState();
}

class _MyLibraryPageState extends ConsumerState<MyLibraryPage> {
  bool _isRefreshing = false;
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  bool _hasTriggeredRefresh = false;

  static const _sortPrefKey = 'librarySortMode';

  @override
  void initState() {
    super.initState();
    _restoreSortMode();
    // On desktop, listen for scroll to bottom to trigger refresh
    if (PlatformUtils.isDesktop) {
      _scrollController.addListener(_onScroll);
    }
  }

  /// Loads the persisted sort mode; unknown values fall back to the default.
  Future<void> _restoreSortMode() async {
    try {
      final stored = await dataBase.getPreference(_sortPrefKey);
      if (stored is String) {
        ref.read(librarySortModeProvider.notifier).state =
            LibrarySortMode.fromKey(stored);
      }
    } catch (_) {
      // Not saved yet: default is already in place.
    }
  }

  Future<void> _persistSortMode(LibrarySortMode mode) async {
    ref.read(librarySortModeProvider.notifier).state = mode;
    await dataBase.savePreference(_sortPrefKey, mode.key);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onScroll() {
    // Trigger refresh when scrolled to bottom on desktop
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 50) {
      if (!_hasTriggeredRefresh && !_isRefreshing) {
        _hasTriggeredRefresh = true;
        _refreshLibrary();
      }
    } else {
      _hasTriggeredRefresh = false;
    }
  }

  Future<void> _refreshLibrary() async {
    if (_isRefreshing) return;

    setState(() {
      _isRefreshing = true;
    });

    try {
      // Sync library with disk (remove missing files, add new ones)
      await syncLibraryWithDisk();
      // Invalidate the provider to force UI refresh
      ref.invalidate(myLibraryProvider);
      ref.invalidate(libraryBooksProvider);
      ref.invalidate(libraryTagsProvider);
      await Future.delayed(const Duration(milliseconds: 300));
    } finally {
      if (mounted) {
        setState(() {
          _isRefreshing = false;
        });
      }
    }
  }

  // Builds the title row with sort button and optional refresh for desktop
  Widget _buildTitleWithRefresh(BuildContext context) {
    final sortMode = ref.watch(librarySortModeProvider);
    return Padding(
      padding: const EdgeInsets.only(left: 5, right: 5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          TitleText(AppLocalizations.of(context).navMyLibrary),
          Row(
            children: [
              PopupMenuButton<LibrarySortMode>(
                tooltip: AppLocalizations.of(context).sortLibrary,
                icon: Icon(
                  Icons.sort,
                  color: Theme.of(context).colorScheme.secondary,
                ),
                initialValue: sortMode,
                onSelected: _persistSortMode,
                itemBuilder: (BuildContext context) => [
                  for (final mode in LibrarySortMode.values)
                    PopupMenuItem(
                      value: mode,
                      child: Row(
                        children: [
                          if (mode == sortMode)
                            Icon(Icons.check,
                                size: 18,
                                color: Theme.of(context)
                                    .colorScheme
                                    .secondary)
                          else
                            const SizedBox(width: 18),
                          const SizedBox(width: 8),
                          Text(mode.label),
                        ],
                      ),
                    ),
                ],
              ),
              if (PlatformUtils.isDesktop)
                IconButton(
                  onPressed: _isRefreshing ? null : _refreshLibrary,
                  tooltip: "Sync library with storage folder",
                  icon: _isRefreshing
                      ? SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Theme.of(context).colorScheme.secondary,
                          ),
                        )
                      : Icon(
                          Icons.sync,
                          color: Theme.of(context).colorScheme.secondary,
                        ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  /// Metadata search box: filters the library by title, author,
  /// publisher or the info line (year, language) as you type.
  Widget _buildSearchField(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 5, right: 5, top: 4),
      child: TextField(
        controller: _searchController,
        showCursor: true,
        cursorColor: Theme.of(context).colorScheme.secondary,
        decoration: InputDecoration(
          isDense: true,
          hintText: AppLocalizations.of(context).searchLibraryHint,
          hintStyle: const TextStyle(
              color: Colors.grey, fontWeight: FontWeight.bold, fontSize: 11),
          prefixIcon: const Icon(Icons.search, size: 20),
          enabledBorder: const OutlineInputBorder(
            borderSide: BorderSide(color: Colors.grey, width: 1.5),
            borderRadius: BorderRadius.all(Radius.circular(50)),
          ),
          focusedBorder: OutlineInputBorder(
            borderSide: BorderSide(
                color: Theme.of(context).colorScheme.tertiary, width: 2),
            borderRadius: const BorderRadius.all(Radius.circular(50)),
          ),
        ),
        style: TextStyle(
          color: Theme.of(context).colorScheme.tertiary,
          fontWeight: FontWeight.bold,
          fontSize: 12,
        ),
        onChanged: (value) =>
            ref.read(librarySearchQueryProvider.notifier).state = value,
      ),
    );
  }

  /// The horizontal filter row: reading-status chips followed by tag chips.
  Widget _buildFilterChips(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final tagFilter = ref.watch(libraryTagFilterProvider);
    final statusFilter = ref.watch(libraryStatusFilterProvider);
    final allTags = ref.watch(libraryTagsProvider).valueOrNull ?? const <String>{};

    Widget statusChip(String label, ReadingStatus? value) {
      final selected = statusFilter == value;
      return Padding(
        padding: const EdgeInsets.only(right: 6),
        child: FilterChip(
          label: Text(label, style: const TextStyle(fontSize: 11)),
          selected: selected,
          showCheckmark: false,
          onSelected: (_) {
            ref.read(libraryStatusFilterProvider.notifier).state =
                selected ? null : value;
          },
        ),
      );
    }

    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          statusChip(l10n.statusUnread, ReadingStatus.unread),
          statusChip(l10n.statusInProgress, ReadingStatus.inProgress),
          statusChip(l10n.statusCompleted, ReadingStatus.completed),
          for (final tag in allTags)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: FilterChip(
                label: Text(tag, style: const TextStyle(fontSize: 11)),
                avatar: const Icon(Icons.label, size: 13),
                selected: tagFilter.contains(tag),
                showCheckmark: false,
                onSelected: (selected) {
                  final next = Set<String>.of(tagFilter);
                  selected ? next.add(tag) : next.remove(tag);
                  ref.read(libraryTagFilterProvider.notifier).state = next;
                },
              ),
            ),
        ],
      ),
    );
  }

  void _openTagEditor(LibraryBook item) {
    showModalBottomSheet<void>(
      context: context,
      builder: (BuildContext sheetContext) {
        return _TagEditorSheet(bookId: item.id, title: item.title);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final libraryBooks = ref.watch(libraryBooksProvider);
    return libraryBooks.when(
      data: (data) {
        final organized = ref.watch(organizedLibraryProvider);
        final anyFilterActive = ref.watch(libraryTagFilterProvider).isNotEmpty ||
            ref.watch(libraryStatusFilterProvider) != null ||
            ref.watch(librarySearchQueryProvider).trim().isNotEmpty;
        if (data.isNotEmpty) {
          return RefreshIndicator(
            onRefresh: () => _refreshLibrary(),
            child: Padding(
              padding: const EdgeInsets.only(left: 5, right: 5, top: 10),
              child: CustomScrollView(
                controller: _scrollController,
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: <Widget>[
                  const SliverToBoxAdapter(
                    child: SizedBox(height: 8),
                  ),
                  const SliverToBoxAdapter(
                    child: ActiveDownloadsWidget(),
                  ),
                  SliverToBoxAdapter(
                    child: _buildTitleWithRefresh(context),
                  ),
                  SliverToBoxAdapter(
                    child: _buildSearchField(context),
                  ),
                  if (data.length > 1 || anyFilterActive)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.only(left: 5, right: 5),
                        child: _buildFilterChips(context),
                      ),
                    ),
                  if (organized.isEmpty && anyFilterActive)
                    const SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Center(
                          child: Text(
                            "No books match the current filters",
                            style: TextStyle(color: Colors.grey, fontSize: 13),
                          ),
                        ),
                      ),
                    )
                  else
                    SliverPadding(
                      padding:
                          const EdgeInsets.only(left: 5, right: 5, top: 10),
                      sliver: SliverList(
                        delegate: SliverChildListDelegate(organized
                            .map((i) => BookInfoCard(
                                title: i.title,
                                author: i.author,
                                publisher: i.book.publisher ?? "",
                                thumbnail: i.book.thumbnail,
                                info: i.book.info,
                                link: i.book.link,
                                onClick: () {
                                  Navigator.push(context, MaterialPageRoute(
                                      builder: (BuildContext context) {
                                    return BookPage(id: i.id);
                                  }));
                                },
                                onLongPress: () => _openTagEditor(i)))
                            .toList()),
                      ),
                    ),
                  // Add scroll-to-refresh hint for desktop
                  if (PlatformUtils.isDesktop)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Center(
                          child: _isRefreshing
                              ? SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color:
                                        Theme.of(context).colorScheme.secondary,
                                  ),
                                )
                              : Text(
                                  "Scroll down to sync library",
                                  style: TextStyle(
                                    color: Colors.grey[500],
                                    fontSize: 12,
                                  ),
                                ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          );
        } else {
          return RefreshIndicator(
            onRefresh: () => _refreshLibrary(),
            child: SingleChildScrollView(
              controller: _scrollController,
              physics: const AlwaysScrollableScrollPhysics(),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: MediaQuery.of(context).size.height * 0.7,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Add refresh button for desktop when library is empty
                    if (PlatformUtils.isDesktop)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 20),
                        child: Center(
                          child: IconButton(
                            onPressed: _isRefreshing ? null : _refreshLibrary,
                            icon: _isRefreshing
                                ? SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .secondary,
                                    ),
                                  )
                                : Icon(
                                    Icons.refresh,
                                    color:
                                        Theme.of(context).colorScheme.secondary,
                                  ),
                          ),
                        ),
                      ),
                    SizedBox(
                      width: 200,
                      child: SvgPicture.asset(
                        'assets/empty_mylib.svg',
                        width: 200,
                      ),
                    ),
                    const SizedBox(
                      height: 30,
                    ),
                    Text(
                      "My Library Is Empty!",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: "#4D4D4D".toColor(),
                        overflow: TextOverflow.ellipsis,
                      ),
                    )
                  ],
                ),
              ),
            ),
          );
        }
      },
      error: (error, _) {
        return CustomErrorWidget(error: error, stackTrace: StackTrace.empty);
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
    );
  }
}

/// Bottom sheet to manage one book's tags: toggle existing tags, create
/// new ones inline, and see the book's current set at a glance.
class _TagEditorSheet extends ConsumerStatefulWidget {
  const _TagEditorSheet({required this.bookId, required this.title});

  final String bookId;
  final String title;

  @override
  ConsumerState<_TagEditorSheet> createState() => _TagEditorSheetState();
}

class _TagEditorSheetState extends ConsumerState<_TagEditorSheet> {
  late Future<Set<String>> _bookTags;

  @override
  void initState() {
    super.initState();
    _bookTags = dataBase.getTags(widget.bookId);
  }

  void _reload() {
    setState(() {
      _bookTags = dataBase.getTags(widget.bookId);
    });
    ref.invalidate(myLibraryProvider);
    ref.invalidate(libraryBooksProvider);
    ref.invalidate(libraryTagsProvider);
  }

  Future<void> _addTag(String rawTag) async {
    final tag = rawTag.trim();
    if (tag.isEmpty) return;
    await dataBase.addTag(widget.bookId, tag);
    _reload();
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
    _reload();
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
          decoration:
              InputDecoration(hintText: dialogL10n.collectionNameHint),
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
    final allTags = ref.watch(libraryTagsProvider).valueOrNull ?? const <String>{};
    return FutureBuilder<Set<String>>(
      future: _bookTags,
      builder: (context, snapshot) {
        final bookTags = snapshot.data ?? const <String>{};
        return SafeArea(
          child: Padding(
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
                  AppLocalizations.of(context).manageCollectionsHint,
                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final tag in allTags)
                      FilterChip(
                        label: Text(tag, style: const TextStyle(fontSize: 12)),
                        selected: bookTags.contains(tag),
                        onSelected: (selected) => selected
                            ? _addTag(tag)
                            : _removeTag(tag),
                      ),
                    ActionChip(
                      label: Text(AppLocalizations.of(context).newCollection,
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
