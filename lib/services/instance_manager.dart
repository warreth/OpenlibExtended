// Dart imports:
import 'dart:convert';

// Project imports:
import 'package:openlib/services/database.dart';

// ====================================================================
// INSTANCE DATA MODEL
// ====================================================================

class ArchiveInstance {
  final String id;
  final String name;
  final String baseUrl;
  int priority;
  bool enabled;
  final bool isCustom;

  ArchiveInstance({
    required this.id,
    required this.name,
    required this.baseUrl,
    required this.priority,
    this.enabled = true,
    this.isCustom = false,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'baseUrl': baseUrl,
      'priority': priority,
      'enabled': enabled,
      'isCustom': isCustom,
    };
  }

  factory ArchiveInstance.fromJson(Map<String, dynamic> json) {
    return ArchiveInstance(
      id: json['id'] as String,
      name: json['name'] as String,
      baseUrl: json['baseUrl'] as String,
      priority: json['priority'] as int,
      enabled: json['enabled'] as bool? ?? true,
      isCustom: json['isCustom'] as bool? ?? false,
    );
  }

  ArchiveInstance copyWith({
    String? id,
    String? name,
    String? baseUrl,
    int? priority,
    bool? enabled,
    bool? isCustom,
  }) {
    return ArchiveInstance(
      id: id ?? this.id,
      name: name ?? this.name,
      baseUrl: baseUrl ?? this.baseUrl,
      priority: priority ?? this.priority,
      enabled: enabled ?? this.enabled,
      isCustom: isCustom ?? this.isCustom,
    );
  }
}

// ====================================================================
// INSTANCE MANAGER SERVICE
// ====================================================================

/// Manages archive instances (mirrors) with CRUD operations and priority management.
/// 
/// This singleton service handles:
/// - Loading and storing instance configurations in the database
/// - Managing instance priority ordering
/// - Enabling/disabling instances
/// - Adding and removing custom instances
/// - Tracking the currently selected instance
class InstanceManager {
  static final InstanceManager _instance = InstanceManager._internal();
  factory InstanceManager() => _instance;
  InstanceManager._internal();

  final MyLibraryDb _database = MyLibraryDb.instance;
  static const String _storageKey = 'archive_instances';
  static const String _selectedInstanceKey = 'selected_instance_id';

  // Default instances including all Anna's Archive mirrors and welib.org
  // Note: .org domain removed as it's no longer available
  static final List<ArchiveInstance> _defaultInstances = [
    ArchiveInstance(
      id: 'annas_archive_gs',
      name: "Anna's Archive (.gs)",
      baseUrl: 'https://annas-archive.gs',
      priority: 0,
      enabled: true,
    ),
    ArchiveInstance(
      id: 'annas_archive_se',
      name: "Anna's Archive (.se)",
      baseUrl: 'https://annas-archive.se',
      priority: 1,
      enabled: true,
    ),
    ArchiveInstance(
      id: 'annas_archive_li',
      name: "Anna's Archive (.li)",
      baseUrl: 'https://annas-archive.li',
      priority: 2,
      enabled: true,
    ),
    ArchiveInstance(
      id: 'annas_archive_st',
      name: "Anna's Archive (.st)",
      baseUrl: 'https://annas-archive.st',
      priority: 3,
      enabled: true,
    ),
    ArchiveInstance(
      id: 'annas_archive_pm',
      name: "Anna's Archive (.pm)",
      baseUrl: 'https://annas-archive.pm',
      priority: 4,
      enabled: true,
    ),
    ArchiveInstance(
      id: 'welib_org',
      name: 'Welib.org',
      baseUrl: 'https://welib.org',
      priority: 5,
      enabled: true,
    ),
  ];

  /// Get all instances sorted by priority.
  /// If no instances are stored, initializes with default instances.
  Future<List<ArchiveInstance>> getInstances() async {
    try {
      final stored = await _database.getPreference(_storageKey);
      
      final List<dynamic> jsonList = jsonDecode(stored);
      final instances = jsonList.map((json) => ArchiveInstance.fromJson(json)).toList();
      
      // Sort by priority
      instances.sort((a, b) => a.priority.compareTo(b.priority));
      return instances;
    } catch (e) {
      // If there's an error or preference not found, initialize with defaults
      await _saveInstances(_defaultInstances);
      return List.from(_defaultInstances);
    }
  }

  /// Get only enabled instances sorted by priority.
  Future<List<ArchiveInstance>> getEnabledInstances() async {
    final instances = await getInstances();
    return instances.where((instance) => instance.enabled).toList();
  }

  // Save instances to database
  Future<void> _saveInstances(List<ArchiveInstance> instances) async {
    final jsonString = jsonEncode(instances.map((i) => i.toJson()).toList());
    await _database.savePreference(_storageKey, jsonString);
  }

  /// Add a custom instance to the list.
  /// [name] Display name for the instance.
  /// [baseUrl] Base URL for the instance (will remove trailing slash).
  Future<void> addInstance(String name, String baseUrl) async {
    final instances = await getInstances();
    final newId = 'custom_${DateTime.now().millisecondsSinceEpoch}';
    final newPriority = instances.isEmpty ? 0 : instances.map((i) => i.priority).fold<int>(0, (max, priority) => priority > max ? priority : max) + 1;
    
    final newInstance = ArchiveInstance(
      id: newId,
      name: name,
      baseUrl: baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl,
      priority: newPriority,
      enabled: true,
      isCustom: true,
    );
    
    instances.add(newInstance);
    await _saveInstances(instances);
  }

  /// Remove an instance from the list.
  /// Only custom instances can be removed (default instances cannot be deleted).
  /// Returns true if the instance was removed, false otherwise.
  Future<bool> removeInstance(String id) async {
    final instances = await getInstances();
    final index = instances.indexWhere((i) => i.id == id);
    
    if (index == -1) {
      return false; // Instance not found
    }

    final instance = instances[index];
    
    if (!instance.isCustom) {
      return false; // Cannot remove default instances
    }
    
    instances.removeAt(index);
    await _saveInstances(instances);
    return true;
  }

  /// Update instance enabled state.
  /// [id] ID of the instance to toggle.
  /// [enabled] New enabled state.
  Future<void> toggleInstance(String id, bool enabled) async {
    final instances = await getInstances();
    final index = instances.indexWhere((i) => i.id == id);
    
    if (index != -1) {
      instances[index] = instances[index].copyWith(enabled: enabled);
      await _saveInstances(instances);
    }
  }

  /// Reorder instances by updating their priority based on new order.
  /// [reorderedInstances] List of instances in new order.
  Future<void> reorderInstances(List<ArchiveInstance> reorderedInstances) async {
    // Update priorities based on new order
    for (int i = 0; i < reorderedInstances.length; i++) {
      reorderedInstances[i] = reorderedInstances[i].copyWith(priority: i);
    }
    await _saveInstances(reorderedInstances);
  }

  /// Get the ID of the currently selected instance.
  /// Returns null if no instance has been explicitly selected.
  Future<String?> getSelectedInstanceId() async {
    try {
      final value = await _database.getPreference(_selectedInstanceKey);
      return value as String?;
    } catch (e) {
      // Preference not set yet, return null
      return null;
    }
  }

  /// Set the currently selected instance ID.
  /// [id] ID of the instance to select, or null to clear selection.
  Future<void> setSelectedInstanceId(String? id) async {
    if (id == null) {
      // To reset, we skip saving null to avoid issues
      return;
    }
    await _database.savePreference(_selectedInstanceKey, id);
  }

  /// Get the current active instance.
  /// Returns the selected instance if set, otherwise returns the first enabled instance.
  /// Falls back to the first default instance if no instances are enabled.
  Future<ArchiveInstance> getCurrentInstance() async {
    final selectedId = await getSelectedInstanceId();
    final instances = await getEnabledInstances();
    
    if (instances.isEmpty) {
      // Return default if no enabled instances
      return _defaultInstances.first;
    }
    
    if (selectedId != null) {
      final selected = instances.firstWhere(
        (i) => i.id == selectedId,
        orElse: () => instances.first,
      );
      return selected;
    }
    
    return instances.first;
  }

  /// Get instance by ID.
  /// Returns null if instance with given ID is not found.
  Future<ArchiveInstance?> getInstanceById(String id) async {
    final instances = await getInstances();
    final index = instances.indexWhere((i) => i.id == id);
    return index != -1 ? instances[index] : null;
  }

  /// Reset to default instances, clearing all custom instances.
  Future<void> resetToDefaults() async {
    await _saveInstances(_defaultInstances);
    // Don't save null, just leave the preference as-is or empty
    // The getCurrentInstance() will handle missing selected ID gracefully
  }
}
