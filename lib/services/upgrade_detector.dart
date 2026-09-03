// Dart imports:
import 'package:flutter/foundation.dart';

// Package imports:
import 'package:package_info_plus/package_info_plus.dart';

// Project imports:
import 'package:openlib/services/database.dart';

/// Result of an upgrade check.
@immutable
class UpgradeCheck {
  /// True when the stored last-run version is older than the running
  /// one - i.e. this launch follows an app upgrade. First installs
  /// (no stored version) are NOT upgrades.
  final bool isUpgrade;

  /// Previous version string, '' on first install.
  final String fromVersion;

  /// Current version string.
  final String toVersion;

  const UpgradeCheck({
    required this.isUpgrade,
    this.fromVersion = '',
    required this.toVersion,
  });
}

/// Detects app upgrades by comparing the last-seen version (stored in
/// the preferences) against the running [PackageInfo] build.
class UpgradeDetector {
  UpgradeDetector({MyLibraryDb? database, Future<String> Function()? versionOf})
      : _database = database ?? MyLibraryDb.instance,
        _versionOf = versionOf ?? _platformVersion;

  static const _lastVersionKey = 'lastRunVersion';

  final MyLibraryDb _database;

  /// Running build version; injectable so tests run without the
  /// platform plugin.
  final Future<String> Function() _versionOf;

  static Future<String> _platformVersion() async =>
      (await PackageInfo.fromPlatform()).version;

  /// Compares two dot-separated versions ("1.2.10" vs "1.2.9").
  /// Returns a negative number when [a] is older, 0 when equal,
  /// positive when [a] is newer. Each side may have 1-3 segments;
  /// missing segments count as 0.
  @visibleForTesting
  static int compareVersions(String a, String b) {
    final pa = a.split('.').map(int.tryParse).toList();
    final pb = b.split('.').map(int.tryParse).toList();
    for (var i = 0; i < 3; i++) {
      final na = (i < pa.length ? pa[i] : null) ?? 0;
      final nb = (i < pb.length ? pb[i] : null) ?? 0;
      if (na != nb) return na.compareTo(nb);
    }
    return 0;
  }

  /// Runs one upgrade check: reads the stored version, compares it
  /// against the running build, and stores the running version so the
  /// next check sees THIS version as the baseline.
  ///
  /// Returns [UpgradeCheck.isUpgrade] only for a real version bump; a
  /// downgrade, a fresh install, or an unchanged version returns false.
  Future<UpgradeCheck> checkAndRecord() async {
    final current = await _versionOf();

    String? stored;
    try {
      stored = await _database.getPreference(_lastVersionKey) as String?;
    } catch (_) {
      // First install: no stored version.
    }

    final isUpgrade = stored != null &&
        stored.isNotEmpty &&
        compareVersions(stored, current) < 0;

    await _database.savePreference(_lastVersionKey, current);
    return UpgradeCheck(
      isUpgrade: isUpgrade,
      fromVersion: stored ?? '',
      toVersion: current,
    );
  }
}
