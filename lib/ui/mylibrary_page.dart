// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';

// Project imports:
import 'package:openlib/services/files.dart' show syncLibraryWithDisk;
import 'package:openlib/services/platform_utils.dart';
import 'package:openlib/state/state.dart' show myLibraryProvider;
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
  bool _hasTriggeredRefresh = false;

  @override
  void initState() {
    super.initState();
    // On desktop, listen for scroll to bottom to trigger refresh
    if (PlatformUtils.isDesktop) {
      _scrollController.addListener(_onScroll);
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
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
      await Future.delayed(const Duration(milliseconds: 300));
    } finally {
      if (mounted) {
        setState(() {
          _isRefreshing = false;
        });
      }
    }
  }

  // Builds the title row with an optional refresh button for desktop
  Widget _buildTitleWithRefresh(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 5, right: 5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const TitleText("My Library"),
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
    );
  }

  @override
  Widget build(BuildContext context) {
    final myBooks = ref.watch(myLibraryProvider);
    return myBooks.when(
      data: (data) {
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
                  SliverPadding(
                    padding: const EdgeInsets.only(left: 5, right: 5, top: 10),
                    sliver: SliverList(
                      delegate: SliverChildListDelegate(data
                          .map((i) => BookInfoCard(
                              title: i.title,
                              author: i.author ?? "",
                              publisher: i.publisher ?? "",
                              thumbnail: i.thumbnail,
                              info: i.info,
                              link: i.link,
                              onClick: () {
                                Navigator.push(context, MaterialPageRoute(
                                    builder: (BuildContext context) {
                                  return BookPage(id: i.id);
                                }));
                              }))
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
        return CustomErrorWidget(error: error, stackTrace: _);
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
