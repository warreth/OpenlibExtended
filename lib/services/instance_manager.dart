// Dart imports:
import 'dart:convert';
import 'dart:async';

// Package imports:
import 'package:dio/dio.dart';

// Project imports:
import 'package:openlib/services/database.dart';
import 'package:openlib/services/logger.dart';

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
  static final List<ArchiveInstance> _defaultInstances = [
    ArchiveInstance(
      id: 'annas_archive_li',
      name: "Anna's Archive (.li)",
      baseUrl: 'https://annas-archive.li',
      priority: 2,
      enabled: true,
    ),
    ArchiveInstance(
      id: 'annas_archive_in',
      name: "Anna's Archive (.in)",
      baseUrl: 'https://annas-archive.in',
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
      final instances =
          jsonList.map((json) => ArchiveInstance.fromJson(json)).toList();

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
    final newPriority = instances.isEmpty
        ? 0
        : instances.map((i) => i.priority).fold<int>(
                0, (max, priority) => priority > max ? priority : max) +
            1;

    final newInstance = ArchiveInstance(
      id: newId,
      name: name,
      baseUrl: baseUrl.endsWith('/')
          ? baseUrl.substring(0, baseUrl.length - 1)
          : baseUrl,
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
  Future<void> reorderInstances(
      List<ArchiveInstance> reorderedInstances) async {
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
  }

  // ====================================================================
  // INSTANCE RANKING / SPEED TESTING
  // ====================================================================

  static const String _autoRankKey = 'auto_rank_instances';
  static const String _lastRankTimeKey = 'last_instance_rank_time';
  final AppLogger _logger = AppLogger();

  /// Check if auto-ranking is enabled (default: true)
  Future<bool> isAutoRankEnabled() async {
    try {
      final value = await _database.getPreference(_autoRankKey);
      return value == 1;
    } catch (e) {
      // Default to enabled if preference doesn't exist
      return true;
    }
  }

  /// Enable or disable auto-ranking
  Future<void> setAutoRankEnabled(bool enabled) async {
    await _database.savePreference(_autoRankKey, enabled);
  }

  /// Get the timestamp of the last ranking
  Future<int?> getLastRankTime() async {
    try {
      final value = await _database.getPreference(_lastRankTimeKey);
      return value as int?;
    } catch (e) {
      return null;
    }
  }

  /// Ping a single instance and return response time in milliseconds
  /// Returns null if the instance is unreachable
  Future<int?> _pingInstance(ArchiveInstance instance) async {
    final dio = Dio();
    dio.options.connectTimeout = const Duration(seconds: 5);
    dio.options.receiveTimeout = const Duration(seconds: 5);

    final stopwatch = Stopwatch()..start();
    try {
      final response = await dio.head(
        instance.baseUrl,
        options: Options(
          headers: {
            "user-agent":
                "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36",
          },
        ),
      );
      stopwatch.stop();
      dio.close();

      if (response.statusCode == 200 ||
          response.statusCode == 301 ||
          response.statusCode == 302) {
        return stopwatch.elapsedMilliseconds;
      }
      return null;
    } catch (e) {
      stopwatch.stop();
      dio.close();
      return null;
    }
  }

  /// Rank all enabled instances by response time in parallel
  /// Updates instance priorities and saves the new order
  /// Returns a map of instance ID to response time (null = unreachable)
  Future<Map<String, int?>> rankInstancesBySpeed() async {
    _logger.info('Starting instance ranking', tag: 'InstanceManager');

    final instances = await getInstances();
    final enabledInstances = instances.where((i) => i.enabled).toList();

    if (enabledInstances.isEmpty) {
      _logger.warning('No enabled instances to rank', tag: 'InstanceManager');
      return {};
    }

    // Ping all instances in parallel
    final futures = enabledInstances.map((instance) async {
      final responseTime = await _pingInstance(instance);
      return MapEntry(instance.id, responseTime);
    });

    final results = await Future.wait(futures);
    final responseTimeMap = Map<String, int?>.fromEntries(results);

    _logger.info('Ranking results', tag: 'InstanceManager', metadata: {
      for (final entry in responseTimeMap.entries)
        entry.key: entry.value != null ? "${entry.value}ms" : "unreachable"
    });

    // Sort enabled instances by response time (reachable first, then by speed)
    enabledInstances.sort((a, b) {
      final timeA = responseTimeMap[a.id];
      final timeB = responseTimeMap[b.id];

      // Both unreachable - keep original order
      if (timeA == null && timeB == null) {
        return a.priority.compareTo(b.priority);
      }
      // A unreachable - B comes first
      if (timeA == null) return 1;
      // B unreachable - A comes first
      if (timeB == null) return -1;
      // Both reachable - sort by speed
      return timeA.compareTo(timeB);
    });

    // Rebuild the full list maintaining disabled instances at their positions
    final disabledInstances = instances.where((i) => !i.enabled).toList();
    final allSorted = [...enabledInstances, ...disabledInstances];

    // Update priorities
    for (int i = 0; i < allSorted.length; i++) {
      allSorted[i] = allSorted[i].copyWith(priority: i);
    }

    await _saveInstances(allSorted);

    // Save the ranking timestamp
    await _database.savePreference(
        _lastRankTimeKey, DateTime.now().millisecondsSinceEpoch);

    _logger
        .info('Instance ranking completed', tag: 'InstanceManager', metadata: {
      'fastest':
          enabledInstances.isNotEmpty ? enabledInstances.first.name : 'none',
    });

    return responseTimeMap;
  }

  /// Rank instances on startup if auto-rank is enabled
  /// Only ranks if more than 1 hour has passed since last ranking
  Future<bool> rankOnStartupIfNeeded() async {
    final autoRankEnabled = await isAutoRankEnabled();
    if (!autoRankEnabled) {
      _logger.debug('Auto-ranking disabled', tag: 'InstanceManager');
      return false;
    }

    final lastRankTime = await getLastRankTime();
    final now = DateTime.now().millisecondsSinceEpoch;

    // Skip if ranked less than 1 hour ago
    if (lastRankTime != null && (now - lastRankTime) < 3600000) {
      _logger.debug('Skipping ranking - ranked recently',
          tag: 'InstanceManager');
      return false;
    }

    await rankInstancesBySpeed();
    return true;
  }
}
