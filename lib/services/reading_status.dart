/// A book's reading state. Automatic progress tracking (a saved position
/// or a completion flag) and a manual choice both resolve to one of these.
enum ReadingStatus {
  unread('unread'),
  inProgress('inProgress'),
  completed('completed');

  const ReadingStatus(this.key);

  /// Stable value stored in the database and backups.
  final String key;

  static ReadingStatus? fromKey(Object? key) {
    if (key is! String) return null;
    for (final status in values) {
      if (status.key == key) return status;
    }
    return null;
  }
}

/// Resolves the status shown for one book.
///
/// A manual choice wins over automatic tracking. Without one, a completed
/// flag means Completed, a saved position means In Progress, and no
/// position means Unread.
ReadingStatus readingStatusFrom({
  Object? manualStatus,
  Object? position,
  Object? completed,
}) {
  final manual = ReadingStatus.fromKey(manualStatus);
  if (manual != null) return manual;
  if (completed == 1 || completed == true || completed == '1') {
    return ReadingStatus.completed;
  }
  final saved = position?.toString();
  if (saved == null || saved.isEmpty) return ReadingStatus.unread;
  return ReadingStatus.inProgress;
}
