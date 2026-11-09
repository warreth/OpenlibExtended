// Flutter imports:
import 'package:flutter/material.dart';
import 'package:openlib/l10n/app_localizations.dart';
import 'package:openlib/core/book_description.dart';

// Package imports:
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

// Project imports:
import 'package:openlib/state/state.dart' show annaArchiveBaseUrlProvider;

/// The URL the "open in site" button opens for a book.
///
/// A real md5 (32 hex) means Anna's Archive carries the book under that
/// id, so the button opens the AA page. Z-Library results carry a short
/// book id, not an md5, and have no Anna's Archive page - pointing at AA
/// for them lands on the error the user sees as "link expired". Those
/// open their own source page instead. Null (a disabled button) only when
/// neither target is available.
@visibleForTesting
String? openInSiteUrl({
  required String link,
  required String md5,
  String? annaArchiveBaseUrl,
}) {
  final hasMd5 = RegExp(r'^[0-9a-f]{32}$', caseSensitive: false).hasMatch(md5);
  if (hasMd5 && annaArchiveBaseUrl != null && annaArchiveBaseUrl.isNotEmpty) {
    return '$annaArchiveBaseUrl/md5/$md5';
  }
  return link.isEmpty ? null : link;
}

class BookInfoWidget extends ConsumerWidget {
  final Widget child;
  final dynamic data;

  const BookInfoWidget({super.key, required this.child, required this.data});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The Anna's Archive base URL comes from the catalogue provider, so
    // build() starts no I/O of its own (that used to leave pending timers
    // in widget tests) and a test can stub the resolved mirror. It is only
    // used for books that really have an md5; Z-Library books open on
    // their own page instead (see [openInSiteUrl]).
    final aaBaseUrl = ref.watch(annaArchiveBaseUrlProvider).valueOrNull;
    final siteUrl = openInSiteUrl(
      link: (data.link ?? '').toString(),
      md5: (data.md5 ?? '').toString(),
      annaArchiveBaseUrl: aaBaseUrl,
    );
    final description =
        normalizedBookDescription(data.description as String?) ??
            AppLocalizations.of(context).noDescriptionAvailable;
    // Libgen results can have no cover at all; CachedNetworkImage requires
    // a non-null URL and used to crash the whole book page here.
    final thumbnail = (data.thumbnail as String?) ?? '';
    // SelectionArea makes title, author, info and description copyable.
    // The container must not be selectable itself, or taps on buttons in
    // the child slot stop working.
    return SafeArea(
      top: false,
      child: SelectionArea(
        child: SingleChildScrollView(
          scrollDirection: Axis.vertical,
          child: Padding(
            padding: const EdgeInsets.only(left: 15, right: 15, top: 10),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.start,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(
                  width: double.infinity,
                  height: 30,
                ),
                Center(
                  child: CachedNetworkImage(
                    height: 230,
                    width: 170,
                    imageUrl: thumbnail,
                    // libgen.li serves /covers/ only with an ads.php
                    // Referer; the book page itself is a valid one.
                    httpHeaders: thumbnail.contains('libgen')
                        ? {'Referer': data.link}
                        : null,
                    imageBuilder: (context, imageProvider) => Container(
                      decoration: BoxDecoration(
                        borderRadius:
                            const BorderRadius.all(Radius.circular(10)),
                        image: DecorationImage(
                          image: imageProvider,
                          fit: BoxFit.fill,
                        ),
                      ),
                    ),
                    placeholder: (context, url) => Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        color: Colors.grey,
                      ),
                      height: 230,
                      width: 170,
                    ),
                    errorWidget: (context, url, error) {
                      return Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          color: Colors.grey,
                        ),
                        height: 230,
                        width: 170,
                        child: const Center(
                          child: Icon(Icons.image_rounded),
                        ),
                      );
                    },
                  ),
                ),
                // Title row with AA button inline
                Padding(
                  padding: const EdgeInsets.only(top: 15, bottom: 0),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Text(
                          data.title,
                          style: TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w900,
                            color: Theme.of(context).colorScheme.tertiary,
                            letterSpacing: 0.5,
                          ),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.open_in_new, size: 18),
                        label: Text(AppLocalizations.of(context).openInSite,
                            style: const TextStyle(fontSize: 13)),
                        style: OutlinedButton.styleFrom(
                          foregroundColor:
                              Theme.of(context).colorScheme.tertiary,
                          side: BorderSide(
                              color: Theme.of(context).colorScheme.tertiary),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 6),
                          visualDensity: VisualDensity.compact,
                        ),
                        onPressed: siteUrl == null
                            ? null
                            : () async {
                                if (await canLaunchUrl(Uri.parse(siteUrl))) {
                                  await launchUrl(Uri.parse(siteUrl),
                                      mode: LaunchMode.externalApplication);
                                } else if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                        content:
                                            Text('Could not open the link.')),
                                  );
                                }
                              },
                      ),
                    ],
                  ),
                ),
                _TopPaddedText(
                  text: data.publisher ?? "unknown",
                  fontSize: 15,
                  topPadding: 7,
                  color: Theme.of(context).textTheme.headlineMedium!.color!,
                  maxLines: 4,
                ),
                _TopPaddedText(
                  text: data.author ?? "unknown",
                  fontSize: 13,
                  topPadding: 7,
                  color: Theme.of(context).textTheme.headlineSmall!.color!,
                  maxLines: 3,
                ),
                _TopPaddedText(
                  text: data.info ?? "",
                  fontSize: 11,
                  topPadding: 9,
                  color: Theme.of(context)
                      .textTheme
                      .headlineSmall!
                      .color!
                      .withAlpha(155),
                  maxLines: 4,
                ),
                // child slot of page
                child,
                Column(
                  mainAxisAlignment: MainAxisAlignment.start,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Description",
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        color: Theme.of(context).colorScheme.tertiary,
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 7, bottom: 10),
                      child: Text(
                        description,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context)
                              .colorScheme
                              .tertiary
                              .withAlpha(150),
                          letterSpacing: 1.5,
                        ),
                      ),
                    )
                  ],
                )
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TopPaddedText extends StatelessWidget {
  final String text;
  final double fontSize;
  final double topPadding;
  final Color color;
  final int maxLines;

  const _TopPaddedText(
      {required this.text,
      required this.fontSize,
      required this.topPadding,
      required this.color,
      required this.maxLines});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(top: topPadding),
      child: Text(
        text,
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: FontWeight.w900,
          color: color,
          letterSpacing: 0.5,
        ),
        overflow: TextOverflow.ellipsis,
        maxLines: maxLines,
      ),
    );
  }
}
