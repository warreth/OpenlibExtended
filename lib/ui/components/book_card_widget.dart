// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// Project imports:
import 'package:openlib/state/state.dart'
    show checkIdExists, languageCodeToDisplay;
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

// Extract language code from book info string
// Info format typically: "[en], pdf, 5.2MB" or "English, pdf, 5.2MB"
String? getLanguage(String? info) {
  if (info == null || info.isEmpty) return null;

  // Try to match [xx] pattern for language code
  final bracketMatch =
      RegExp(r'\[([a-z]{2})\]', caseSensitive: false).firstMatch(info);
  if (bracketMatch != null) {
    final code = bracketMatch.group(1)?.toLowerCase();
    if (code != null && languageCodeToDisplay.containsKey(code)) {
      return languageCodeToDisplay[code];
    }
  }

  // Try to find language code at start of info (common format: "en, pdf, ...")
  final parts = info.split(',');
  if (parts.isNotEmpty) {
    final firstPart = parts[0].trim().toLowerCase();
    if (languageCodeToDisplay.containsKey(firstPart)) {
      return languageCodeToDisplay[firstPart];
    }
  }

  return null;
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
    this.md5,
  });

  final String title;
  final String author;
  final String publisher;
  final String? thumbnail;
  final String? info;
  final String link;
  final VoidCallback onClick;
  final String? md5;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    String? fileType = getFileType(info);
    String? language = getLanguage(info);

    // Check if book is downloaded (only if md5 is provided)
    final isDownloaded = md5 != null
        ? ref.watch(checkIdExists(md5!))
        : const AsyncValue<bool>.data(false);

    return InkWell(
      onTap: onClick,
      child: Container(
        width: double.infinity,
        height: 120,
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
                  height: 120,
                  width: 90,
                  imageUrl: thumbnail ?? "",
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
                    height: 120,
                    width: 90,
                  ),
                  errorWidget: (context, url, error) {
                    return Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(5),
                        color: "#F8C0C8".toColor(),
                      ),
                      height: 120,
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
                      publisher,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color:
                            Theme.of(context).textTheme.headlineMedium?.color,
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
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
                        // Language badge
                        if (language != null)
                          Container(
                            decoration: BoxDecoration(
                              color: "#6b8cce".toColor(),
                              borderRadius: BorderRadius.circular(2.5),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(3, 2, 3, 2),
                              child: Text(
                                language,
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
                        if (language != null)
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
