// What the book page's download button should do with a book's links.

// Flutter imports:
import 'package:flutter/foundation.dart';

/// The outcome of every download-resolution route for one book.
@immutable
class DownloadTarget {
  /// The URL to download, or null when no route produced one.
  final String? url;

  /// True when [url] bypasses mirror scraping (a re-resolved CDN link, a
  /// donation-key fast link, or a libgen `get.php` URL).
  final bool fast;

  /// The mirror's own reason for withholding the file, when it gave one.
  final String? refusal;

  const DownloadTarget({this.url, this.fast = false, this.refusal});

  bool get hasUrl => url != null && url!.isNotEmpty;
}

/// Chooses the download button's target once every resolution route has
/// run: Z-Library's re-resolved `/dl/` hop, a donation-key fast link, or
/// the link carried by the search result itself.
///
/// A [refusal] only wins while no route produced a usable URL. The stored
/// Z-Library `/dl/<id>` link is dead exactly when the mirror refused to
/// resolve it, so starting a download against it fails later with a
/// generic "all mirrors failed" instead of the mirror's own reason
/// ("daily limit reached", "sign in required") - which is the one message
/// the user can act on. A [fast] link (donation-key CDN URL or a
/// re-resolved one) still wins: it does not go through the refused hop.
///
/// With no refusal the stored link is returned unchanged, so the caller's
/// existing attempt-and-report flow stays exactly as it was.
DownloadTarget chooseDownloadTarget({
  required String? url,
  required bool fast,
  String? refusal,
}) {
  final usable = (url != null && url.isNotEmpty) ? url : null;
  if (refusal == null) return DownloadTarget(url: usable, fast: fast);
  if (fast) return DownloadTarget(url: usable, fast: true);
  return DownloadTarget(refusal: refusal);
}

/// True when [url] answers with the file itself instead of a page a
/// WebView could scrape.
///
/// Libgen's `get.php` mints a 307 to a CDN response carrying
/// `Content-Disposition: attachment`. Android's WebView hands that to its
/// download listener instead of loading it as a page, so `onLoadStop`
/// never fires and the manual-download overlay sits on "Preparing
/// download..." forever (issue #117). Such links go straight to the
/// download manager.
bool isDirectFileUrl(String? url) {
  if (url == null || url.isEmpty) return false;
  final uri = Uri.tryParse(url);
  if (uri == null) return false;
  return uri.path.endsWith('/get.php') &&
      uri.queryParameters.containsKey('md5');
}
