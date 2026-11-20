// Flutter imports:
import 'package:flutter/material.dart';
import 'package:openlib/l10n/app_localizations.dart';

// Project imports:
import 'package:openlib/services/reading_status.dart';

/// Localized name of a reading status, used by every status control.
String readingStatusLabel(AppLocalizations l10n, ReadingStatus status) {
  switch (status) {
    case ReadingStatus.unread:
      return l10n.statusUnread;
    case ReadingStatus.inProgress:
      return l10n.statusInProgress;
    case ReadingStatus.completed:
      return l10n.statusCompleted;
  }
}

/// One-choice control for a book's reading status. A Wrap keeps long
/// translations from overflowing a narrow phone in the bottom sheet.
class ReadingStatusSelector extends StatelessWidget {
  const ReadingStatusSelector({
    super.key,
    required this.status,
    required this.onChanged,
    this.enabled = true,
  });

  final ReadingStatus status;
  final ValueChanged<ReadingStatus> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final value in ReadingStatus.values)
          ChoiceChip(
            label: Text(
              readingStatusLabel(l10n, value),
              style: const TextStyle(fontSize: 12),
            ),
            selected: status == value,
            onSelected: enabled ? (_) => onChanged(value) : null,
          ),
      ],
    );
  }
}
