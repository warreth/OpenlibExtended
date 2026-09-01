// Flutter imports:
import 'package:flutter/material.dart';
import 'package:openlib/l10n/app_localizations.dart';

// Package imports:
import 'package:flutter_riverpod/flutter_riverpod.dart';

// Project imports:
import 'package:openlib/services/instance_manager.dart';
import 'package:openlib/services/slum_health_service.dart';
import 'package:openlib/state/state.dart';
import 'package:openlib/ui/components/page_title_widget.dart';

/// Manages every mirror the app can talk to, grouped by service. Each
/// mirror can be toggled, reordered within its group, and health-
/// checked - both directly (ping) and via open-slum.org, which tracks
/// Cloudflare-protected mirrors the app itself often cannot reach.
class InstancesPage extends ConsumerStatefulWidget {
  const InstancesPage({super.key});

  @override
  ConsumerState<InstancesPage> createState() => _InstancesPageState();
}

class _InstancesPageState extends ConsumerState<InstancesPage> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _urlController = TextEditingController();

  /// Instance id -> measured ping in ms (null = unreachable).
  Map<String, int?> _responseTimes = {};

  /// Mirror host -> open-slum.org health.
  Map<String, SlumHealth> _slumHealth = const {};

  bool _isPinging = false;
  bool _isFetchingSlum = false;

  static const _serviceOrder = [
    MirrorService.annasArchive,
    MirrorService.libgen,
    MirrorService.zlibrary,
  ];

  static const _serviceTitles = {
    MirrorService.annasArchive: "Anna's Archive",
    MirrorService.libgen: 'Library Genesis',
    MirrorService.zlibrary: 'Z-Library',
  };

  static const _serviceSubtitles = {
    MirrorService.annasArchive: 'Main source for reading and downloads',
    MirrorService.libgen: 'Additional search results',
    MirrorService.zlibrary: 'Additional search results',
  };

  @override
  void dispose() {
    _nameController.dispose();
    _urlController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    // SLUM data is cheap and static; load once per visit.
    _loadSlumHealth();
  }

  Future<void> _loadSlumHealth() async {
    if (_isFetchingSlum) return;
    setState(() => _isFetchingSlum = true);
    final health = await SlumHealthService().fetchHealth();
    if (!mounted) return;
    setState(() {
      _slumHealth = health;
      _isFetchingSlum = false;
    });
  }

  Future<void> _pingAllInstances() async {
    if (_isPinging) return;

    setState(() {
      _isPinging = true;
      _responseTimes = {};
    });

    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final rankL10n = AppLocalizations.of(context);
    try {
      final manager = ref.read(instanceManagerProvider);
      final results = await manager.rankInstancesBySpeed();

      if (!mounted) return;
      setState(() {
        _responseTimes = results;
        _isPinging = false;
      });
      ref.invalidate(archiveInstancesProvider);
      if (mounted) {
        scaffoldMessenger.showSnackBar(
          SnackBar(
            content: Text(rankL10n.mirrorsTestedRanked),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isPinging = false);
      scaffoldMessenger.showSnackBar(
        SnackBar(
            content: Text(rankL10n.testingFailed('$e')),
            backgroundColor: Theme.of(context).colorScheme.error),
      );
    }
  }

  void _showAddInstanceDialog(MirrorService service) {
    _nameController.clear();
    _urlController.clear();
    var selectedService = service;
    final dialogL10n = AppLocalizations.of(context);

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: Text(AppLocalizations.of(context).addCustomMirror),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: _nameController,
                  decoration: InputDecoration(
                    labelText: dialogL10n.nameLabel,
                    hintText: dialogL10n.nameHint,
                  ),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<MirrorService>(
                  initialValue: selectedService,
                  decoration: InputDecoration(labelText: dialogL10n.serviceLabel),
                  items: [
                    for (final entry in _serviceTitles.entries)
                      DropdownMenuItem(
                        value: entry.key,
                        child: Text(entry.value),
                      ),
                  ],
                  onChanged: (value) =>
                      setDialogState(() => selectedService = value!),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _urlController,
                  decoration: InputDecoration(
                    labelText: dialogL10n.urlLabel,
                    hintText: dialogL10n.urlHint,
                  ),
                  keyboardType: TextInputType.url,
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(dialogL10n.cancel),
              ),
              TextButton(
                onPressed: () async {
                  final name = _nameController.text.trim();
                  final url = _urlController.text.trim();

                  if (name.isEmpty || url.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(dialogL10n.pleaseFillAllFields)),
                    );
                    return;
                  }

                  final uri = Uri.tryParse(url);
                  if (uri == null ||
                      (uri.scheme != 'http' && uri.scheme != 'https') ||
                      uri.host.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(dialogL10n.enterValidUrl),
                      ),
                    );
                    return;
                  }

                  final navigator = Navigator.of(context);
                  final scaffoldMessenger = ScaffoldMessenger.of(context);

                  await ref
                      .read(instanceManagerProvider)
                      .addInstance(name, url, service: selectedService);
                  ref.invalidate(archiveInstancesProvider);

                  if (mounted) {
                    if (navigator.canPop()) navigator.pop();
                    scaffoldMessenger.showSnackBar(
                      SnackBar(
                          content: Text(dialogL10n.mirrorAdded)),
                    );
                  }
                },
                child: Text(dialogL10n.add),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showDeleteConfirmDialog(ArchiveInstance instance) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(AppLocalizations.of(context).deleteMirror),
          content: Text(AppLocalizations.of(context)
              .deleteMirrorConfirm(instance.name)),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(AppLocalizations.of(context).cancel),
            ),
            TextButton(
              onPressed: () async {
                final navigator = Navigator.of(context);
                final scaffoldMessenger = ScaffoldMessenger.of(context);

                final success =
                    await ref.read(instanceManagerProvider).removeInstance(
                          instance.id,
                        );

                if (!mounted) return;

                ref.invalidate(archiveInstancesProvider);
                navigator.pop();
                scaffoldMessenger.showSnackBar(
                  SnackBar(
                    content: Text(success
                        ? 'Mirror deleted'
                        : 'Cannot delete default mirrors'),
                  ),
                );
              },
              child: Text(AppLocalizations.of(context).delete,
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final instancesAsync = ref.watch(archiveInstancesProvider);
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context).manageMirrors),
        actions: [
          if (_isFetchingSlum)
            const Padding(
              padding: EdgeInsets.all(14),
              child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2)),
            ),
          IconButton(
            icon: _isPinging
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.speed),
            onPressed: _isPinging ? null : _pingAllInstances,
            tooltip: AppLocalizations.of(context).testRankMirrors,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              ref.invalidate(archiveInstancesProvider);
              _loadSlumHealth();
            },
            tooltip: AppLocalizations.of(context).reloadHealthData,
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: TitleText(AppLocalizations.of(context)
                  .mirrorsAndProviders),
            ),
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Drag to reorder priority. Toggles pick which mirrors '
                      'the app actually searches. Health badges come from '
                      'open-slum.org.',
                      style:
                          TextStyle(fontSize: 12, color: colorScheme.tertiary),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: instancesAsync.when(
                data: (instances) {
                  if (instances.isEmpty) {
                    return Center(
                        child: Text(
                            AppLocalizations.of(context).noMirrorsAvailable));
                  }
                  return _buildGroupedList(context, instances);
                },
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, stack) => Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.error, color: colorScheme.error, size: 48),
                      const SizedBox(height: 16),
                      Text(AppLocalizations.of(context)
                          .errorLabel('$error')),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: () =>
                            ref.invalidate(archiveInstancesProvider),
                        child: Text(AppLocalizations.of(context).retry),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddInstanceDialog(MirrorService.annasArchive),
        icon: const Icon(Icons.add),
        label: Text(AppLocalizations.of(context).addMirror),
      ),
    );
  }

  Widget _buildGroupedList(
      BuildContext context, List<ArchiveInstance> instances) {
    return ListView(
      children: [
        for (final service in _serviceOrder) ...[
          _ServiceHeader(
            title: _serviceTitles[service]!,
            subtitle: _serviceSubtitles[service]!,
            onAdd: () => _showAddInstanceDialog(service),
          ),
          for (final instance in instances.where((i) => i.service == service))
            _MirrorCard(
              instance: instance,
              pingMs: _responseTimes[instance.id],
              hasPingData: _responseTimes.isNotEmpty,
              slumHealth:
                  _slumHealth[Uri.tryParse(instance.baseUrl)?.host ?? ''],
              onToggle: (value) async {
                await ref
                    .read(instanceManagerProvider)
                    .toggleInstance(instance.id, value);
                ref.invalidate(archiveInstancesProvider);
              },
              onDelete: () => _showDeleteConfirmDialog(instance),
            ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}

class _ServiceHeader extends StatelessWidget {
  const _ServiceHeader(
      {required this.title, required this.subtitle, required this.onAdd});

  final String title;
  final String subtitle;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 16, 8, 4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold)),
                Text(subtitle,
                    style:
                        TextStyle(fontSize: 12, color: colorScheme.tertiary)),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.add, size: 20),
            onPressed: onAdd,
            tooltip: AppLocalizations.of(context)
                .addServiceMirror(title),
          ),
        ],
      ),
    );
  }
}

/// A single mirror row: drag-free list position mirrors priority;
/// badges show ping (measured) and SLUM (external) health.
class _MirrorCard extends StatelessWidget {
  const _MirrorCard({
    required this.instance,
    required this.pingMs,
    required this.hasPingData,
    required this.slumHealth,
    required this.onToggle,
    required this.onDelete,
  });

  final ArchiveInstance instance;
  final int? pingMs;
  final bool hasPingData;
  final SlumHealth? slumHealth;
  final ValueChanged<bool> onToggle;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final host = Uri.tryParse(instance.baseUrl)?.host ?? instance.baseUrl;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: ListTile(
        leading: Icon(
          instance.enabled ? Icons.link : Icons.link_off,
          color: instance.enabled ? colorScheme.secondary : colorScheme.outline,
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                instance.name,
                style: const TextStyle(fontWeight: FontWeight.bold),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (slumHealth != null) ...[
              const SizedBox(width: 4),
              _SlumBadge(health: slumHealth!),
            ],
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(host, style: const TextStyle(fontSize: 12)),
            if (pingMs != null)
              Text(
                '$pingMs ms',
                style: TextStyle(
                  fontSize: 11,
                  color: pingMs! < 500
                      ? Colors.green
                      : pingMs! < 1500
                          ? Colors.orange
                          : Colors.red,
                ),
              )
            else if (hasPingData)
              Text(AppLocalizations.of(context).unreachable,
                  style: TextStyle(fontSize: 11, color: colorScheme.error)),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Switch(
              value: instance.enabled,
              onChanged: onToggle,
            ),
            if (instance.isCustom)
              IconButton(
                icon: Icon(Icons.delete, color: colorScheme.error),
                onPressed: onDelete,
                tooltip:
                    AppLocalizations.of(context).deleteMirrorTooltip,
              ),
          ],
        ),
      ),
    );
  }
}

class _SlumBadge extends StatelessWidget {
  const _SlumBadge({required this.health});

  final SlumHealth health;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (health.status) {
      SlumStatus.up => ('UP', Colors.green),
      SlumStatus.protected => ('PROTECTED', Colors.blue),
      SlumStatus.degraded => ('DEGRADED', Colors.orange),
      SlumStatus.down => ('DOWN', Colors.red),
      SlumStatus.unknown => ('?', Colors.grey),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style:
            TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: color),
      ),
    );
  }
}
