// Flutter imports:
import 'package:flutter/material.dart';
import 'package:openlib/l10n/app_localizations.dart';

// Package imports:
import 'package:flutter_riverpod/flutter_riverpod.dart';

// Project imports:
import 'package:openlib/services/annas_archieve.dart';
import 'package:openlib/services/search_manager.dart';
import 'package:openlib/services/download_manager.dart';
import 'package:openlib/services/platform_utils.dart';
import 'package:openlib/services/share_book.dart';
import 'package:openlib/ui/components/book_info_widget.dart';
import 'package:openlib/ui/components/error_widget.dart';
import 'package:openlib/ui/components/file_buttons_widget.dart';
import 'package:openlib/ui/components/snack_bar_widget.dart';
import 'package:openlib/ui/webview_page.dart';
import 'package:openlib/state/state.dart'
    show
        bookInfoProvider,
        checkIdExists,
        getBookByIdProvider,
        myLibraryProvider,
        showManualDownloadButtonProvider,
        downloadManagerProvider,
        donationKeyProvider;

class BookInfoPage extends ConsumerWidget {
  const BookInfoPage({super.key, required this.url});

  final String url;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bookInfo = ref.watch(bookInfoProvider(url));
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.surface,
        title: Text(AppLocalizations.of(context).appTitle),
        titleTextStyle: Theme.of(context).textTheme.displayLarge,
        actions: [
          bookInfo.maybeWhen(data: (data) {
            return IconButton(
              icon: Icon(
                Icons.share_sharp,
                color: Theme.of(context).colorScheme.tertiary,
              ),
              iconSize: 19.0,
              onPressed: () async {
                final outcome = await shareBook(
                    data.title, data.link, data.thumbnail ?? '',
                    format: data.format);
                if (context.mounted && outcome == ShareOutcome.pathCopied) {
                  showSnackBar(
                      context: context,
                      message: AppLocalizations.of(context).copiedBookLink);
                }
              },
            );
          }, orElse: () {
            return const SizedBox.shrink();
          })
        ],
      ),
      body: bookInfo.when(
        skipLoadingOnRefresh: false,
        data: (data) {
          return BookInfoWidget(
              data: data, child: ActionButtonWidget(data: data));
        },
        error: (err, _) {
          return CustomErrorWidget(
            error: err,
            stackTrace: StackTrace.empty,
            onRefresh: () {
              ref.invalidate(bookInfoProvider(url));
            },
          );
        },
        loading: () {
          return Center(
              child: SizedBox(
            width: 25,
            height: 25,
            child: CircularProgressIndicator(
              color: Theme.of(context).colorScheme.secondary,
              strokeCap: StrokeCap.round,
            ),
          ));
        },
      ),
    );
  }
}

class ActionButtonWidget extends ConsumerStatefulWidget {
  const ActionButtonWidget({super.key, required this.data});
  final BookInfoData data;

  @override
  ConsumerState<ConsumerStatefulWidget> createState() =>
      _ActionButtonWidgetState();
}

class _ActionButtonWidgetState extends ConsumerState<ActionButtonWidget> {
  @override
  Widget build(BuildContext context) {
    final isBookExist = ref.watch(checkIdExists(widget.data.md5));
    final bookData = ref.watch(getBookByIdProvider(widget.data.md5));

    return isBookExist.when(
      data: (isExists) {
        if (isExists) {
          // Get fileName from database for existing books
          final fileName = bookData.whenOrNull(data: (book) => book?.fileName);
          return FileOpenAndDeleteButtons(
            id: widget.data.md5,
            format: widget.data.format!,
            fileName: fileName,
            onDelete: () async {
              await Future.delayed(const Duration(seconds: 1));
              // ignore: unused_result
              ref.refresh(checkIdExists(widget.data.md5));
              // ignore: unused_result
              ref.refresh(getBookByIdProvider(widget.data.md5));
            },
          );
        } else {
          final showManualButton = ref.watch(showManualDownloadButtonProvider);

          return Padding(
            padding: const EdgeInsets.only(top: 21, bottom: 21),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                // Button for "Add To My Library" (background download)
                TextButton(
                  style: TextButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.secondary,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    textStyle: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                    ),
                  ),
                  onPressed: () async {
                    String? downloadUrl = widget.data.mirror;
                    bool isFastDownload = widget.data.isFastDownload;

                    // Libgen serves its files directly (get.php -> CDN);
                    // no mirror scraping or donation key applies.
                    var isDirectLink = downloadUrl != null &&
                        downloadUrl.contains('/get.php?');
                    if (isDirectLink) {
                      isFastDownload = true;
                    }

                    // Z-Library /dl/ links sit behind a DiamWall
                    // proof-of-work and a 302 to a signed CDN URL, and
                    // some ids answer 204 forever; re-fetch the page for
                    // the live ids and resolve the first working one.
                    final isZlib =
                        downloadUrl != null && downloadUrl.contains('/dl/');
                    if (isZlib && !isDirectLink) {
                      try {
                        final resolved = await ZlibraryProvider()
                            .resolveBookDownload(widget.data.link);
                        if (resolved != null) {
                          downloadUrl = resolved;
                          isDirectLink = true;
                          isFastDownload = true;
                        }
                      } catch (e) {
                        // Fall through to the slow AA-style flow, which
                        // cannot work for zlib; the snackbar below fires.
                      }
                    }

                    // Try to fetch fast download link if key is present and not already fast
                    final donationKey =
                        isDirectLink ? '' : ref.read(donationKeyProvider);
                    if (donationKey.isNotEmpty && !isFastDownload) {
                      try {
                        final annasArchive = AnnasArchieve();
                        final fastLink = await annasArchive.getFastDownloadUrl(
                            widget.data.md5, donationKey);
                        if (fastLink != null) {
                          downloadUrl = fastLink;
                          isFastDownload = true;
                        }
                      } catch (e) {
                        // Fallback to normal mirror
                      }
                    }

                    if (downloadUrl != null && downloadUrl != '') {
                      // On Linux, use WebView UI flow since headless webview is not supported
                      // Unless it is a fast download (isDirectLink), which doesn't need scraping
                      if (PlatformUtils.isLinux && !isFastDownload) {
                        // Navigate to webview page to get mirrors
                        if (!context.mounted) return;
                        final List<String>? mirrors = await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (BuildContext context) =>
                                Webview(url: downloadUrl!),
                          ),
                        );

                        if (mirrors != null &&
                            mirrors.isNotEmpty &&
                            context.mounted) {
                          // Start download with fetched mirrors
                          final downloadManager =
                              ref.read(downloadManagerProvider);
                          final task = DownloadTask(
                            id: '${widget.data.md5}_${DateTime.now().millisecondsSinceEpoch}',
                            md5: widget.data.md5,
                            title: widget.data.title,
                            author: widget.data.author,
                            thumbnail: widget.data.thumbnail,
                            publisher: widget.data.publisher,
                            info: widget.data.info,
                            format: widget.data.format!,
                            description: widget.data.description,
                            link: widget.data.link,
                            mirrors: mirrors,
                          );

                          await downloadManager.addDownload(task);

                          if (context.mounted) {
                            final message = isFastDownload
                                ? 'Fast download started in background 🚀'
                                : 'Download started in background';
                            showSnackBar(
                              context: context,
                              message: message,
                            );
                          }
                          ref.invalidate(myLibraryProvider);
                        }
                      } else {
                        // Other platforms (or fast download on Linux): use background fetch
                        final downloadManager =
                            ref.read(downloadManagerProvider);
                        final task = DownloadTask(
                          id: '${widget.data.md5}_${DateTime.now().millisecondsSinceEpoch}',
                          md5: widget.data.md5,
                          title: widget.data.title,
                          author: widget.data.author,
                          thumbnail: widget.data.thumbnail,
                          publisher: widget.data.publisher,
                          info: widget.data.info,
                          format: widget.data.format!,
                          description: widget.data.description,
                          link: widget.data.link,
                          mirrors: [], // Will be fetched in background
                          mirrorUrl: downloadUrl, // Store mirror URL for retry
                          isDirectLink: isFastDownload,
                          // z-lib's signed CDN link expires after a few
                          // hours; the manager then re-resolves a fresh
                          // one from the book page instead of failing.
                          linkRefresher: isZlib
                              ? ZlibraryProvider().resolveBookDownload
                              : null,
                        );

                        await downloadManager.addDownloadWithMirrorUrl(
                          task,
                          downloadUrl,
                        );

                        if (context.mounted) {
                          final message = isFastDownload
                              ? 'Fast download started in background 🚀'
                              : 'Download started in background';
                          showSnackBar(
                            context: context,
                            message: message,
                          );
                          ref.invalidate(myLibraryProvider);
                        }
                      }
                    } else {
                      if (context.mounted) {
                        showSnackBar(
                            context: context,
                            message: AppLocalizations.of(context).noMirrors);
                      }
                    }
                  },
                  child: Text(AppLocalizations.of(context).addToMyLibrary),
                ),
                // Button for "Manual Download" (opens webview for captcha) - only shown if setting is enabled
                if (showManualButton)
                  TextButton(
                    style: TextButton.styleFrom(
                      backgroundColor: Theme.of(context)
                          .colorScheme
                          .tertiary
                          .withValues(alpha: 0.2),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      textStyle: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    onPressed: () async {
                      if (widget.data.mirror != null &&
                          widget.data.mirror != '') {
                        // Navigate to webview page
                        final List<String>? mirrors = await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (BuildContext context) =>
                                Webview(url: widget.data.mirror!),
                          ),
                        );

                        if (mirrors != null &&
                            mirrors.isNotEmpty &&
                            context.mounted) {
                          // Start download in background with fetched mirrors
                          final downloadManager =
                              ref.read(downloadManagerProvider);
                          final task = DownloadTask(
                            id: '${widget.data.md5}_${DateTime.now().millisecondsSinceEpoch}',
                            md5: widget.data.md5,
                            title: widget.data.title,
                            author: widget.data.author,
                            thumbnail: widget.data.thumbnail,
                            publisher: widget.data.publisher,
                            info: widget.data.info,
                            format: widget.data.format!,
                            description: widget.data.description,
                            link: widget.data.link,
                            mirrors: mirrors, // Use manually fetched mirrors
                          );

                          await downloadManager.addDownload(task);

                          if (context.mounted) {
                            showSnackBar(
                              context: context,
                              message: AppLocalizations.of(context)
                                  .downloadStartedBackground,
                            );
                          }
                          ref.invalidate(myLibraryProvider);
                        }
                      } else {
                        showSnackBar(
                            context: context,
                            message: AppLocalizations.of(context).noMirrors);
                      }
                    },
                    child: Text(
                      'Manual Download',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.tertiary,
                      ),
                    ),
                  )
              ],
            ),
          );
        }
      },
      error: (error, stackTrace) {
        return Text(error.toString());
      },
      loading: () {
        return CircularProgressIndicator(
          color: Theme.of(context).colorScheme.secondary,
          strokeCap: StrokeCap.round,
        );
      },
    );
  }
}

