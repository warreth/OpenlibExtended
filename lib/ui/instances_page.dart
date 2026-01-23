// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:flutter_riverpod/flutter_riverpod.dart';

// Project imports:
import 'package:openlib/services/instance_manager.dart';
import 'package:openlib/state/state.dart';
import 'package:openlib/ui/components/page_title_widget.dart';

class InstancesPage extends ConsumerStatefulWidget {
  const InstancesPage({super.key});

  @override
  ConsumerState<InstancesPage> createState() => _InstancesPageState();
}

class _InstancesPageState extends ConsumerState<InstancesPage> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _urlController = TextEditingController();
  Map<String, int?> _responseTimes = {};
  bool _isTesting = false;

  @override
  void dispose() {
    _nameController.dispose();
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _testAllInstances() async {
    if (_isTesting) return;

    setState(() {
      _isTesting = true;
      _responseTimes = {};
    });

    final scaffoldMessenger = ScaffoldMessenger.of(context);

    try {
      final manager = ref.read(instanceManagerProvider);
      final results = await manager.rankInstancesBySpeed();

      if (mounted) {
        setState(() {
          _responseTimes = results;
          _isTesting = false;
        });

        // Refresh the list to show new order
        ref.invalidate(archiveInstancesProvider);

        scaffoldMessenger.showSnackBar(
          const SnackBar(
            content: Text('Instances tested and ranked by speed'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isTesting = false;
        });
        scaffoldMessenger.showSnackBar(
          SnackBar(
            content: Text('Testing failed: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _showAddInstanceDialog() {
    _nameController.clear();
    _urlController.clear();

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Add Custom Instance'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Name',
                  hintText: 'e.g., My Custom Mirror',
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _urlController,
                decoration: const InputDecoration(
                  labelText: 'URL',
                  hintText: 'https://example.com',
                ),
                keyboardType: TextInputType.url,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () async {
                final name = _nameController.text.trim();
                final url = _urlController.text.trim();

                if (name.isEmpty || url.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Please fill all fields')),
                  );
                  return;
                }

                final uri = Uri.tryParse(url);
                if (uri == null ||
                    (uri.scheme != 'http' && uri.scheme != 'https') ||
                    uri.host.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                          'Please enter a valid URL with http:// or https://'),
                    ),
                  );
                  return;
                }

                // Capture context-dependent objects before async gap
                final navigator = Navigator.of(context);
                final scaffoldMessenger = ScaffoldMessenger.of(context);

                final manager = ref.read(instanceManagerProvider);
                await manager.addInstance(name, url);

                // Refresh the instances list
                ref.invalidate(archiveInstancesProvider);

                if (mounted) {
                  if (navigator.canPop()) {
                    navigator.pop();
                  }
                  scaffoldMessenger.showSnackBar(
                    const SnackBar(
                        content: Text('Instance added successfully')),
                  );
                }
              },
              child: const Text('Add'),
            ),
          ],
        );
      },
    );
  }

  void _showDeleteConfirmDialog(ArchiveInstance instance) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Delete Instance'),
          content: Text('Are you sure you want to delete "${instance.name}"?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () async {
                // Capture context-dependent objects before async gap
                final navigator = Navigator.of(context);
                final scaffoldMessenger = ScaffoldMessenger.of(context);

                final manager = ref.read(instanceManagerProvider);
                final success = await manager.removeInstance(instance.id);

                if (!mounted) return;

                if (success) {
                  ref.invalidate(archiveInstancesProvider);
                  navigator.pop();
                  scaffoldMessenger.showSnackBar(
                    const SnackBar(content: Text('Instance deleted')),
                  );
                } else {
                  navigator.pop();
                  scaffoldMessenger.showSnackBar(
                    const SnackBar(
                        content: Text('Cannot delete default instances')),
                  );
                }
              },
              child: const Text('Delete', style: TextStyle(color: Colors.red)),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final instancesAsync = ref.watch(archiveInstancesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Manage Instances'),
        actions: [
          IconButton(
            icon: _isTesting
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.speed),
            onPressed: _isTesting ? null : _testAllInstances,
            tooltip: 'Test & Rank All Instances',
          ),
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: _showAddInstanceDialog,
            tooltip: 'Add Custom Instance',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () async {
              // Capture context-dependent objects before async gap
              final scaffoldMessenger = ScaffoldMessenger.of(context);

              final manager = ref.read(instanceManagerProvider);
              await manager.resetToDefaults();
              ref.invalidate(archiveInstancesProvider);
              if (!mounted) return;
              scaffoldMessenger.showSnackBar(
                const SnackBar(content: Text('Reset to default instances')),
              );
            },
            tooltip: 'Reset to Defaults',
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.all(8.0),
              child: TitleText('Archive Instances'),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
              child: Text(
                'Drag to reorder priority. App tries each enabled instance 2x before moving to next.',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ),
            Expanded(
              child: instancesAsync.when(
                data: (instances) {
                  if (instances.isEmpty) {
                    return const Center(
                      child: Text('No instances available'),
                    );
                  }

                  return ReorderableListView.builder(
                    itemCount: instances.length,
                    onReorder: (oldIndex, newIndex) async {
                      if (oldIndex < newIndex) {
                        newIndex -= 1;
                      }

                      final newList = List<ArchiveInstance>.from(instances);
                      final item = newList.removeAt(oldIndex);
                      newList.insert(newIndex, item);

                      final manager = ref.read(instanceManagerProvider);
                      await manager.reorderInstances(newList);
                      ref.invalidate(archiveInstancesProvider);
                    },
                    itemBuilder: (context, index) {
                      final instance = instances[index];
                      final responseTime = _responseTimes[instance.id];

                      return Card(
                        key: ValueKey(instance.id),
                        margin: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        child: ListTile(
                          leading: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.drag_handle,
                                color: Theme.of(context).colorScheme.tertiary,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                '${index + 1}',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Theme.of(context).colorScheme.tertiary,
                                ),
                              ),
                            ],
                          ),
                          title: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  instance.name,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold),
                                ),
                              ),
                              // Show response time badge if available
                              if (_responseTimes.containsKey(instance.id))
                                Container(
                                  margin: const EdgeInsets.only(right: 4),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: responseTime != null
                                        ? (responseTime < 500
                                            ? Colors.green
                                                .withValues(alpha: 0.2)
                                            : responseTime < 1500
                                                ? Colors.orange
                                                    .withValues(alpha: 0.2)
                                                : Colors.red
                                                    .withValues(alpha: 0.2))
                                        : Colors.grey.withValues(alpha: 0.2),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    responseTime != null
                                        ? '${responseTime}ms'
                                        : 'offline',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: responseTime != null
                                          ? (responseTime < 500
                                              ? Colors.green
                                              : responseTime < 1500
                                                  ? Colors.orange
                                                  : Colors.red)
                                          : Colors.grey,
                                    ),
                                  ),
                                ),
                              if (instance.isCustom)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.blue.withValues(alpha: 0.2),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: const Text(
                                    'Custom',
                                    style: TextStyle(
                                        fontSize: 10, color: Colors.blue),
                                  ),
                                ),
                            ],
                          ),
                          subtitle: Text(
                            instance.baseUrl,
                            style: const TextStyle(fontSize: 12),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Switch(
                                value: instance.enabled,
                                thumbColor: WidgetStateProperty.resolveWith(
                                    (states) =>
                                        states.contains(WidgetState.selected)
                                            ? Colors.green
                                            : null),
                                onChanged: (value) async {
                                  final manager =
                                      ref.read(instanceManagerProvider);
                                  await manager.toggleInstance(
                                      instance.id, value);
                                  ref.invalidate(archiveInstancesProvider);
                                },
                              ),
                              if (instance.isCustom)
                                IconButton(
                                  icon: const Icon(Icons.delete,
                                      color: Colors.red),
                                  onPressed: () =>
                                      _showDeleteConfirmDialog(instance),
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  );
                },
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, stack) => Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.error, color: Colors.red, size: 48),
                      const SizedBox(height: 16),
                      Text('Error: $error'),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: () =>
                            ref.invalidate(archiveInstancesProvider),
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
