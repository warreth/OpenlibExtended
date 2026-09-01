// Flutter imports:
import 'package:flutter/foundation.dart';

// Project imports:
import 'package:openlib/services/database.dart';

/// How the library list is ordered. Each mode has a stable persisted key
/// so the choice survives restarts.
enum LibrarySortMode {
  dateAddedDesc('dateAddedDesc'),
  dateAddedAsc('dateAddedAsc'),
  titleAsc('titleAsc'),
  titleDesc('titleDesc'),
  authorAsc('authorAsc'),
  authorDesc('authorDesc'),
  fileSizeDesc('fileSizeDesc'),
  fileSizeAsc('fileSizeAsc'),
  readingStatus('readingStatus');

  const LibrarySortMode(this.key);

  final String key;

  static LibrarySortMode fromKey(String key) =>
      LibrarySortMode.values.firstWhere(
        (m) => m.key == key,
        orElse: () => LibrarySortMode.dateAddedDesc,
      );

  String get label {
    switch (this) {
      case LibrarySortMode.dateAddedDesc:
        return 'Newest added';
      case LibrarySortMode.dateAddedAsc:
        return 'Oldest added';
      case LibrarySortMode.titleAsc:
        return 'Title A-Z';
      case LibrarySortMode.titleDesc:
        return 'Title Z-A';
      case LibrarySortMode.authorAsc:
        return 'Author A-Z';
      case LibrarySortMode.authorDesc:
        return 'Author Z-A';
      case LibrarySortMode.fileSizeDesc:
        return 'Largest file';
      case LibrarySortMode.fileSizeAsc:
        return 'Smallest file';
      case LibrarySortMode.readingStatus:
        return 'Reading status';
    }
  }
}

/// A book's reading state, derived from the saved position: nothing
/// saved means unread, a saved position marked finished means completed,
/// anything else is in progress.
enum ReadingStatus { unread, inProgress, completed }

/// A [MyBook] enriched with everything sorting and filtering need: the
/// tags it carries, its reading status and its file size in bytes.
@immutable
class LibraryBook {
  final MyBook book;
  final Set<String> tags;
  final ReadingStatus status;
  final int? fileSizeBytes;

  const LibraryBook({
    required this.book,
    this.tags = const {},
    this.status = ReadingStatus.unread,
    this.fileSizeBytes,
  });

  String get id => book.id;
  String get title => book.title;
  String get author => book.author ?? '';
}

/// Sorts books by [mode]. Two books comparing equal fall back to the
/// date-added order (the list as stored), so sorting never shuffles
/// unrelated items.
List<LibraryBook> sortLibrary(List<LibraryBook> books, LibrarySortMode mode) {
  final sorted = List<LibraryBook>.of(books);
  String t(LibraryBook b) => b.title.toLowerCase();
  String a(LibraryBook b) => b.author.toLowerCase();
  switch (mode) {
    case LibrarySortMode.dateAddedDesc:
    case LibrarySortMode.dateAddedAsc:
      break; // stored order already applies
    case LibrarySortMode.titleAsc:
      sorted.sort((x, y) => t(x).compareTo(t(y)));
    case LibrarySortMode.titleDesc:
      sorted.sort((x, y) => t(y).compareTo(t(x)));
    case LibrarySortMode.authorAsc:
      sorted.sort((x, y) {
        final c = a(x).compareTo(a(y));
        return c != 0 ? c : t(x).compareTo(t(y));
      });
    case LibrarySortMode.authorDesc:
      sorted.sort((x, y) {
        final c = a(y).compareTo(a(x));
        return c != 0 ? c : t(x).compareTo(t(y));
      });
    case LibrarySortMode.fileSizeDesc:
      sorted.sort(
          (x, y) => (y.fileSizeBytes ?? -1).compareTo(x.fileSizeBytes ?? -1));
    case LibrarySortMode.fileSizeAsc:
      sorted.sort((x, y) =>
          (x.fileSizeBytes ?? 1 << 40).compareTo(y.fileSizeBytes ?? 1 << 40));
    case LibrarySortMode.readingStatus:
      sorted.sort((x, y) {
        final c = x.status.index.compareTo(y.status.index);
        return c != 0 ? c : t(x).compareTo(t(y));
      });
  }
  if (mode == LibrarySortMode.dateAddedAsc) {
    return sorted.reversed.toList();
  }
  return sorted;
}

/// Keeps only the books matching every active filter. A null tag or
/// status filter means "no filter"; an empty tag filter set also
/// means "no filter".
List<LibraryBook> filterLibrary(
  List<LibraryBook> books, {
  Set<String>? tagFilter,
  ReadingStatus? statusFilter,
}) {
  return books.where((b) {
    if (tagFilter != null && tagFilter.isNotEmpty) {
      if (!tagFilter.any(b.tags.contains)) return false;
    }
    if (statusFilter != null && b.status != statusFilter) return false;
    return true;
  }).toList();
}
