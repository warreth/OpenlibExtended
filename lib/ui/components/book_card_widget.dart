import 'package:openlib/core/book_language.dart';
import 'package:openlib/l10n/app_localizations.dart';
// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// Project imports:
import 'package:openlib/state/state.dart'
    show checkIdExists, resultCoverProvider;
import 'package:openlib/ui/extensions.dart';

// Extract file type from book info string
String? getFileType(String? info) {
  if (info == null || info.isEmpty) return null;
  final infoLower = info.toLowerCase();
  if (infoLower.contains('pdf')) return "PDF";
  if (infoLower.contains('epub')) return "Epub";
  if (infoLower.contains('cbr')) return "Cbr";
  if (infoLower.contains('cbz')) return "Cbz";
  return null;
}

String? getLanguage(String? info) => bookLanguageName(info);

/// Same-host Referer for libgen cover URLs, null for everything else.
/// libgen mirrors serve /covers/ only with an ads.php Referer from the
/// same host; the host is read from the cover URL itself so the app
/// hardcodes no mirror address.
Map<String, String>? _coverHeaders(String? coverUrl) {
  if (coverUrl == null || !coverUrl.contains('libgen')) return null;
  final origin = Uri.tryParse(coverUrl)?.origin;
  if (origin == null) return null;
  return {'Referer': '$origin/ads.php?md5=cover-lookup'};
}

class BookInfoCard extends ConsumerWidget {
  const BookInfoCard({
    super.key,
    required this.title,
    required this.author,
    required this.publisher,
    required this.thumbnail,
    required this.info,
    required this.link,
    required this.onClick,
    this.onLongPress,
    this.md5,
    this.source,
  });

  final String title;
  final String author;
  final String publisher;
  final String? thumbnail;
  final String? info;
  final String link;
  final VoidCallback onClick;
  final VoidCallback? onLongPress;
  final String? md5;

  /// Catalog name this result came from; shown as a small chip.
  final String? source;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    String? fileType = getFileType(info);
    String? language = getLanguage(info);

    // Check if book is downloaded (only if md5 is provided)
    final isDownloaded = md5 != null
        ? ref.watch(checkIdExists(md5!))
        : const AsyncValue<bool>.data(false);

    // LibGen search rows ship without covers; resolve one lazily from
    // the book's ads.php page (it carries the cover URL).
    final hasThumbnail = thumbnail != null && thumbnail!.isNotEmpty;
    final lazyCover =
        hasThumbnail ? null : ref.watch(resultCoverProvider(link)).valueOrNull;
    final coverUrl = hasThumbnail ? thumbnail : lazyCover;

    return InkWell(
      onTap: onClick,
      onLongPress: onLongPress,
      child: Container(
        width: double.infinity,
        height: 140,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(5),
          color: Theme.of(context).colorScheme.tertiaryContainer,
        ),
        margin: const EdgeInsets.only(bottom: 10),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            // Book thumbnail with download indicator
            Stack(
              children: [
                CachedNetworkImage(
                  height: 140,
                  width: 90,
                  imageUrl: coverUrl ?? "",
                  // libgen mirrors serve /covers/ only with a same-host
                  // ads.php Referer; without it the response is 200 but
                  // empty. The host comes from the cover URL itself, so
                  // no mirror address is baked into the app.
                  httpHeaders: _coverHeaders(coverUrl),
                  imageBuilder: (context, imageProvider) => Container(
                    decoration: BoxDecoration(
                      borderRadius: const BorderRadius.all(Radius.circular(5)),
                      image: DecorationImage(
                        image: imageProvider,
                        fit: BoxFit.fill,
                      ),
                    ),
                  ),
                  placeholder: (context, url) => Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(5),
                      color: "#F8C0C8".toColor(),
                    ),
                    height: 140,
                    width: 90,
                  ),
                  errorWidget: (context, url, error) {
                    return Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(5),
                        color: "#F8C0C8".toColor(),
                      ),
                      height: 140,
                      width: 90,
                      child: const Center(
                        child: Icon(Icons.image_rounded),
                      ),
                    );
                  },
                ),
                // Downloaded checkmark indicator
                if (isDownloaded.valueOrNull == true)
                  Positioned(
                    top: 4,
                    right: 4,
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        color: Colors.green,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.check,
                        color: Colors.white,
                        size: 16,
                      ),
                    ),
                  ),
              ],
            ),
            Expanded(
                child: Padding(
              padding: const EdgeInsets.all(5),
              child: SizedBox(
                width: double.infinity,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.tertiary,
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 2,
                    ),
                    Text(
                      publisher.isEmpty
                          ? ''
                          : '${AppLocalizations.of(context).publisher}: $publisher',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color:
                            Theme.of(context).textTheme.headlineMedium?.color,
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                    Text(
                      '${AppLocalizations.of(context).languageSetting}: ${language ?? AppLocalizations.of(context).unknown}',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.tertiary),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        if (source != null && source!.isNotEmpty)
                          Container(
                            decoration: BoxDecoration(
                              color: Theme.of(context)
                                  .colorScheme
                                  .secondary
                                  .withAlpha(200),
                              borderRadius: BorderRadius.circular(2.5),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(3, 2, 3, 2),
                              child: Text(
                                source!,
                                style: const TextStyle(
                                  fontSize: 8.5,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                  letterSpacing: 0.5,
                                ),
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                              ),
                            ),
                          ),
                        if (source != null && source!.isNotEmpty)
                          const SizedBox(
                            width: 3,
                          ),
                        if (fileType != null)
                          Container(
                            decoration: BoxDecoration(
                              color: "#a5a5a5".toColor(),
                              borderRadius: BorderRadius.circular(2.5),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(3, 2, 3, 2),
                              child: Text(
                                fileType,
                                style: const TextStyle(
                                  fontSize: 8.5,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                  letterSpacing: 0.5,
                                ),
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                              ),
                            ),
                          ),
                        if (fileType != null)
                          const SizedBox(
                            width: 3,
                          ),
                        Expanded(
                          child: Text(
                            author,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context)
                                  .textTheme
                                  .headlineSmall
                                  ?.color,
                            ),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ))
          ],
        ),
      ),
    );
  }
}
