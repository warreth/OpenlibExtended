// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:flutter_riverpod/flutter_riverpod.dart';

// Project imports:
import 'package:openlib/l10n/app_localizations.dart';
import 'package:openlib/main.dart' show MainScreen;
import 'package:openlib/services/instance_manager.dart';
import 'package:openlib/services/search_manager.dart';

/// Shown once after an app upgrade (not on first install): what's
/// new, plus a tab that offers re-syncing the stored mirror list
/// with the shipped defaults and re-enabling all search providers.
/// The feature list is per-release; bump it alongside pubspec when
/// a new version ships.
class WhatsNewPage extends ConsumerStatefulWidget {
  const WhatsNewPage({super.key, required this.fromVersion, required this.toVersion});

  /// Version the user upgraded from ('' when unknown).
  final String fromVersion;

  /// Version now running.
  final String toVersion;

  @override
  ConsumerState<WhatsNewPage> createState() => _WhatsNewPageState();
}

class _WhatsNewPageState extends ConsumerState<WhatsNewPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController = TabController(length: 2, vsync: this);

  bool _instancesUpdated = false;
  List<String> _changes = const [];
  bool _updating = false;

  Future<void> _updateInstances() async {
    setState(() => _updating = true);
    try {
      final changes = await InstanceManager().syncWithDefaults();
      // Upgraders get every search provider back on: a stale saved
      // toggle list must not silently hide a new release's sources.
      await SearchManager().enableAllProviders();
      if (mounted) {
        setState(() {
          _instancesUpdated = true;
          _changes = changes;
        });
      }
    } finally {
      if (mounted) setState(() => _updating = false);
    }
  }

  void _continue() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (context) => const MainScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 28, 20, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.upgrade_rounded,
                          size: 34, color: theme.colorScheme.secondary),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          l10n.whatsNewTitle(widget.toVersion),
                          style: theme.textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.bold),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(l10n.whatsNewIntro,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                ],
              ),
            ),
            TabBar(
              controller: _tabController,
              labelColor: theme.colorScheme.secondary,
              indicatorColor: theme.colorScheme.secondary,
              tabs: [
                Tab(text: l10n.whatsNewTabFeatures),
                Tab(text: l10n.whatsNewTabSources),
              ],
            ),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _FeaturesTab(),
                  _SourcesTab(
                    updated: _instancesUpdated,
                    updating: _updating,
                    changes: _changes,
                    onUpdate: _updateInstances,
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: FilledButton(
                onPressed: _continue,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(l10n.whatsNewContinue),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FeaturesTab extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    final notes = [
      (Icons.speed_rounded, l10n.whatsNewFeatureSpeed),
      (Icons.source_rounded, l10n.whatsNewFeatureSourceLabels),
      (Icons.image_rounded, l10n.whatsNewFeatureCovers),
    ];

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        for (final (icon, text) in notes)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, size: 22, color: theme.colorScheme.secondary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(text,
                      style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant)),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _SourcesTab extends ConsumerWidget {
  const _SourcesTab({
    required this.updated,
    required this.updating,
    required this.changes,
    required this.onUpdate,
  });

  final bool updated;
  final bool updating;
  final List<String> changes;
  final Future<void> Function() onUpdate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(l10n.whatsNewProvidersHint,
            style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant)),
        const SizedBox(height: 16),
        if (updated) ...[
          Row(
            children: [
              Icon(Icons.check_circle_rounded,
                  color: Colors.green.shade600, size: 20),
              const SizedBox(width: 8),
              Text(l10n.whatsNewInstancesUpdated,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(fontWeight: FontWeight.bold)),
            ],
          ),
          if (changes.isNotEmpty) ...[
            const SizedBox(height: 10),
            for (final change in changes)
              Padding(
                padding: const EdgeInsets.only(left: 28, bottom: 4),
                child: Text(change,
                    style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant)),
              ),
          ],
        ] else
          FilledButton.tonalIcon(
            onPressed: updating ? null : () => onUpdate(),
            icon: updating
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.sync_rounded),
            label: Text(l10n.whatsNewUpdateInstances),
          ),
      ],
    );
  }
}
