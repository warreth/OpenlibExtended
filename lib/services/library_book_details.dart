import 'package:openlib/core/book_description.dart';
import 'package:openlib/services/book_detail_routing.dart';
import 'package:openlib/services/database.dart';
import 'package:openlib/services/search_manager.dart';

/// Repairs missing catalogue blurbs independently of opening the local file.
class LibraryBookDetails {
  LibraryBookDetails({Future<String?> Function(String)? fetchDescription})
      : _fetchDescription = fetchDescription ?? _fetchZlibraryDescription;

  final Future<String?> Function(String) _fetchDescription;

  Future<MyBook?> load(String id) => MyLibraryDb.instance.getId(id);

  Future<MyBook?> refreshDescription(MyBook book) async {
    if (normalizedBookDescription(book.description) != null) return null;
    final uri = Uri.tryParse(book.link);
    if (uri == null ||
        !uri.hasAuthority ||
        (uri.scheme != 'http' && uri.scheme != 'https')) {
      return null;
    }
    try {
      final description = normalizedBookDescription(
          await _fetchDescription(book.link)
              .timeout(const Duration(seconds: 8)));
      if (description == null) return null;
      await MyLibraryDb.instance.saveMissingDescription(book.id, description);
      return await MyLibraryDb.instance.getId(book.id);
    } catch (_) {
      // Offline/missing metadata must never stop the user opening their book.
      return null;
    }
  }

  static Future<String?> _fetchZlibraryDescription(String url) async {
    final route =
        await routeBookDetail(url).timeout(const Duration(seconds: 2));
    if (route != BookDetailRoute.zlibrary) return null;
    final data = await ZlibraryProvider()
        .bookInfo(url, timeout: const Duration(seconds: 6));
    return data?.description;
  }
}
