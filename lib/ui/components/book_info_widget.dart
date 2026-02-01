// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:openlib/services/instance_manager.dart';

class BookInfoWidget extends StatelessWidget {
  /// Returns the current fastest Anna's Archive domain for the given md5.
  static Future<String> _getCurrentAAUrl(String md5) async {
    final instance = await InstanceManager().getCurrentInstance();
    final baseUrl = instance.baseUrl.endsWith('/')
        ? instance.baseUrl.substring(0, instance.baseUrl.length - 1)
        : instance.baseUrl;
    return "$baseUrl/md5/$md5";
  }

  final Widget child;
  final dynamic data;

  const BookInfoWidget({super.key, required this.child, required this.data});

  @override
  Widget build(BuildContext context) {
    String description = data.description.toString().length < 3
        ? "No Description available"
        : data.description.toString();
    return SingleChildScrollView(
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
                imageUrl: data.thumbnail,
                imageBuilder: (context, imageProvider) => Container(
                  decoration: BoxDecoration(
                    borderRadius: const BorderRadius.all(Radius.circular(10)),
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
                  FutureBuilder<String>(
                    future: _getCurrentAAUrl(data.md5),
                    builder: (context, snapshot) {
                      return OutlinedButton.icon(
                        icon: const Icon(Icons.open_in_new, size: 18),
                        label: const Text("Open in site",
                            style: TextStyle(fontSize: 13)),
                        style: OutlinedButton.styleFrom(
                          foregroundColor:
                              Theme.of(context).colorScheme.tertiary,
                          side: BorderSide(
                              color: Theme.of(context).colorScheme.tertiary),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 6),
                          visualDensity: VisualDensity.compact,
                        ),
                        onPressed: snapshot.hasData
                            ? () async {
                                final aaUrl = snapshot.data!;
                                if (await canLaunchUrl(Uri.parse(aaUrl))) {
                                  await launchUrl(Uri.parse(aaUrl),
                                      mode: LaunchMode.externalApplication);
                                } else {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                        content: Text(
                                            "Could not open Anna's Archive.")),
                                  );
                                }
                              }
                            : null,
                      );
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
                      color:
                          Theme.of(context).colorScheme.tertiary.withAlpha(150),
                      letterSpacing: 1.5,
                    ),
                  ),
                )
              ],
            )
          ],
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
