// Flutter imports:
import 'package:flutter/material.dart';
import 'package:openlib/l10n/app_localizations.dart';

// Package imports:
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';

// Project imports:
import 'package:openlib/services/annas_archieve.dart' show BookData;
import 'package:openlib/state/state.dart' as app_state;
import 'package:openlib/ui/book_info_page.dart';
import 'package:openlib/ui/components/book_card_widget.dart';
import 'package:openlib/ui/components/error_widget.dart';
import 'package:openlib/ui/components/page_title_widget.dart';

// A constant for the 'No Results Found' text color for better theming/readability.
const Color _kNoResultsTextColor = Color(0xFF4D4D4D);

// Custom extension for String to add the missing capitalizeFirst method
extension StringExtension on String {
  String get capitalizeFirst {
    if (isEmpty) return this;
    return '${this[0].toUpperCase()}${substring(1)}';
  }
}

/// Search results with pagination: the first page loads with the page,
/// and scrolling near the bottom quietly fetches the next one and
/// appends it. Anna's Archive serves 50 results per page.
class ResultPage extends ConsumerStatefulWidget {
  const ResultPage({super.key, required this.searchQuery});

  final String searchQuery;

  @override
  ConsumerState<ResultPage> createState() => _ResultPageState();
}

class _ResultPageState extends ConsumerState<ResultPage> {
  final _scrollController = ScrollController();

  /// Results accumulated across all loaded pages.
  final List<BookData> _books = [];

  /// Pages fully merged into [_books]; the next fetch starts at +1.
  int _loadedPages = 0;
  bool _fetchingNextPage = false;

  /// A page that returned nothing stops the pager - there is no page
  /// after the last one, and endless empty fetches would spin forever.
  bool _reachedEnd = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    // Page 1 may resolve before the first build; merge it the moment it
    // does. Once loaded, the pager owns accumulation from there.
    ref.listenManual(
      app_state.searchProvider(app_state.SearchPageKey(widget.searchQuery, 1)),
      (previous, next) {
        final books = next.valueOrNull;
        if (books != null && _loadedPages == 0) {
          setState(() {
            _books.addAll(books);
            _loadedPages = 1;
            if (books.isEmpty) _reachedEnd = true;
          });
        }
      },
      fireImmediately: true,
    );
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 200 &&
        !_fetchingNextPage &&
        !_reachedEnd) {
      _loadNextPage();
    }
  }

  Future<void> _loadNextPage() async {
    if (!mounted) return;
    setState(() => _fetchingNextPage = true);

    final page = _loadedPages + 1;
    final nextPage = await ref.read(app_state
        .searchProvider(app_state.SearchPageKey(widget.searchQuery, page))
        .future);

    if (!mounted) return;
    setState(() {
      if (nextPage.isEmpty) {
        _reachedEnd = true;
      } else {
        _books.addAll(nextPage);
        _loadedPages = page;
      }
      _fetchingNextPage = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    // Page 1 is watched so a fresh query rebuilds everything; deeper
    // pages are read on demand by the pager.
    final firstPage = ref.watch(app_state
        .searchProvider(app_state.SearchPageKey(widget.searchQuery, 1)));
    final String capitalizedQuery = widget.searchQuery.capitalizeFirst;

    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context)
            .resultsFor(capitalizedQuery)),
        titleTextStyle: Theme.of(context)
            .textTheme
            .titleLarge
            ?.copyWith(fontWeight: FontWeight.bold),
        backgroundColor: Theme.of(context).colorScheme.surface,
      ),
      body: firstPage.when(
        data: (pageOne) {
          if (_books.isNotEmpty) {
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: CustomScrollView(
                controller: _scrollController,
                slivers: <Widget>[
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          TitleText(AppLocalizations.of(context).results),
                          if (_books.first.source != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(
                                AppLocalizations.of(context).searchingOn(
                                    _books.first.source!),
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  SliverList.builder(
                    itemCount: _books.length,
                    itemBuilder: (context, index) {
                      final i = _books[index];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10.0),
                        child: BookInfoCard(
                          title: i.title,
                          author: i.author ?? "unknown",
                          publisher: i.publisher ?? "unknown",
                          thumbnail: i.thumbnail ?? '',
                          info: i.info ?? '',
                          link: i.link,
                          md5: i.md5,
                          source: i.source,
                          onClick: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (BuildContext context) {
                                  return BookInfoPage(url: i.link);
                                },
                              ),
                            );
                          },
                        ),
                      );
                    },
                  ),
                  if (_fetchingNextPage || !_reachedEnd)
                    const SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        child: Center(
                          child: SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2.5),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            );
          } else {
            // No Results Found UI
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 200,
                      height: 200,
                      child: SvgPicture.asset(
                        'assets/no_results.svg',
                        width: 200,
                        fit: BoxFit.contain,
                      ),
                    ),
                    const SizedBox(height: 30),
                    Text(
                      AppLocalizations.of(context).noResultsFound,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: _kNoResultsTextColor,
                        overflow: TextOverflow.ellipsis,
                      ),
                    )
                  ],
                ),
              ),
            );
          }
        },
        error: (error, stackTrace) {
          return CustomErrorWidget(
            error: error,
            stackTrace: stackTrace,
            onRefresh: () {
              setState(() {
                _books.clear();
                _loadedPages = 0;
                _reachedEnd = false;
              });
              // ignore: unused_result
              ref.refresh(app_state.searchProvider(
                  app_state.SearchPageKey(widget.searchQuery, 1)));
            },
          );
        },
        loading: () {
          return Column(
            mainAxisAlignment: MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(
                    left: 10, right: 10, top: 10, bottom: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TitleText(AppLocalizations.of(context).results),
                    const SizedBox(height: 4),
                    // The chain tries LibGen, then Z-Library, then
                    // Anna's Archive - an empty page is not the end.
                    Text(
                      AppLocalizations.of(context).tryingNextSource,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color:
                            Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Center(
                  child: SizedBox(
                    width: 25,
                    height: 25,
                    child: CircularProgressIndicator(
                      color: Theme.of(context).colorScheme.secondary,
                      strokeWidth: 3.0,
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
