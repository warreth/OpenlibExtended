// Dart imports:
import 'dart:io';

// Flutter imports:
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// Package imports:
import 'package:device_info_plus/device_info_plus.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlib/services/files.dart';
import 'package:openlib/services/platform_utils.dart';
import 'package:openlib/services/update_checker.dart';
import 'package:permission_handler/permission_handler.dart';

// Project imports:
import 'package:openlib/services/database.dart';
import 'package:openlib/ui/about_page.dart';
import 'package:openlib/ui/instances_page.dart';
import 'package:openlib/ui/onboarding/onboarding_page.dart';

import 'package:openlib/state/state.dart'
    show
        themeModeProvider,
        openPdfWithExternalAppProvider,
        openEpubWithExternalAppProvider,
        showManualDownloadButtonProvider,
        autoRankInstancesProvider,
        instanceManagerProvider,
        currentInstanceProvider,
        archiveInstancesProvider,
        myLibraryProvider;

// Scans a directory for book files (epub, pdf) and imports them to the library database
Future<void> scanAndImportBooks(
    String directoryPath, MyLibraryDb database, WidgetRef ref) async {
  try {
    final directory = Directory(directoryPath);
    if (!await directory.exists()) return;

    final files = directory.listSync(recursive: false);
    int importedCount = 0;

    for (var entity in files) {
      if (entity is File) {
        final fileName = entity.path.split('/').last;
        final extension = fileName.split('.').last.toLowerCase();

        // Only process epub and pdf files
        if (extension == 'epub' || extension == 'pdf') {
          // Extract the md5 hash from the filename (the part before the extension)
          final parts = fileName.split('.');
          if (parts.length >= 2) {
            final md5 = parts.sublist(0, parts.length - 1).join('.');

            // Check if this book already exists in the database
            final exists = await database.checkIdExists(md5);
            if (!exists) {
              // Create a minimal book entry for the imported file
              final book = MyBook(
                id: md5,
                title:
                    md5, // Use filename as title since we don't have metadata
                author: "Unknown",
                thumbnail: "",
                link: "",
                publisher: "",
                info: "",
                description: "",
                format: extension,
              );
              await database.insert(book);
              importedCount++;
            }
          }
        }
      }
    }

    // Refresh the library provider to show new books
    if (importedCount > 0) {
      // ignore: unused_result
      ref.refresh(myLibraryProvider);
    }
  } catch (e) {
    // Silently fail - don't interrupt user flow
  }
}

Future<void> requestStoragePermission() async {
  // Desktop platforms don't require runtime storage permissions
  if (PlatformUtils.isDesktop) return;

  // Check whether the device is running Android 11 or higher
  DeviceInfoPlugin plugin = DeviceInfoPlugin();
  AndroidDeviceInfo android = await plugin.androidInfo;
  // Android < 11
  if (android.version.sdkInt < 33) {
    if (await Permission.storage.request().isGranted) {
      // Permission granted
    } else if (await Permission.storage.request().isPermanentlyDenied) {
      await openAppSettings();
    }
  }
  // Android > 11
  else {
    if (await Permission.manageExternalStorage.request().isGranted) {
      // Permission granted
    } else if (await Permission.manageExternalStorage
        .request()
        .isPermanentlyDenied) {
      await openAppSettings();
    } else if (await Permission.manageExternalStorage.request().isDenied) {
      // Permission denied
    }
  }
}

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Watch useful providers
    final themeMode = ref.watch(themeModeProvider);
    final openPdfExternal = ref.watch(openPdfWithExternalAppProvider);
    final openEpubExternal = ref.watch(openEpubWithExternalAppProvider);
    final showManualDownload = ref.watch(showManualDownloadButtonProvider);

    MyLibraryDb dataBase = MyLibraryDb.instance;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 10.0),
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Settings", style: Theme.of(context).textTheme.displayLarge),
            const SizedBox(height: 20),
            _buildSectionHeader(context, "Library & Instances"),
            _buildSettingCard(
              context,
              title: "Archive Instance",
              child: const _InstanceSelectorWidget(),
            ),
            _buildSettingTile(
              context,
              title: "Manage Instances",
              icon: Icons.dns,
              onTap: () {
                Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (context) => const InstancesPage()));
              },
            ),
            const _AutoRankInstancesWidget(),
            const SizedBox(height: 20),
            _buildSectionHeader(context, "General"),
            _buildSwitchTile(
              context,
              title: "Dark Mode",
              value: themeMode == ThemeMode.dark,
              onChanged: (val) {
                ref.read(themeModeProvider.notifier).state =
                    val ? ThemeMode.dark : ThemeMode.light;
                dataBase.savePreference('darkMode', val);
                if (Platform.isAndroid) {
                  SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
                      systemNavigationBarColor:
                          val ? Colors.black : Colors.grey.shade200));
                }
              },
            ),
            FutureBuilder<dynamic>(
              future: dataBase.getPreference('bookStorageDirectory'),
              builder: (context, snapshot) {
                String subtitle = "Change where books are saved";
                if (snapshot.hasData && snapshot.data is String) {
                  subtitle = snapshot.data as String;
                }
                return _buildSettingTile(
                  context,
                  title: "Storage Location",
                  subtitle: subtitle,
                  icon: Icons.folder,
                  onTap: () async {
                    final currentDirectory =
                        await dataBase.getPreference('bookStorageDirectory');
                    final internalDirectory =
                        await getBookStorageDefaultDirectory;
                    String? pickedDirectory =
                        await FilePicker.platform.getDirectoryPath();
                    if (pickedDirectory == null) return;
                    await requestStoragePermission();

                    if (currentDirectory == internalDirectory) {
                      await moveLibraryFiles(currentDirectory, pickedDirectory);
                    }

                    await dataBase.savePreference(
                        'bookStorageDirectory', pickedDirectory);
                    await scanAndImportBooks(pickedDirectory, dataBase, ref);
                    // Force rebuild to show new path
                    // ignore: unused_result
                    ref.refresh(myLibraryProvider);
                    // Since this FutureBuilder depends on the db future directly,
                    // we might need to trigger a setstate or similar if we want it to update immediately
                    // without page reload. But SettingsPage is a ConsumerWidget.
                    // A simple hack is to rely on the fact that we're rebuilding the parent or
                    // just let it update on next entry.
                    // For better UX, we should probably watch a provider that updates when preference changes.
                    // But for now, this matches the existing pattern.
                    (context as Element).markNeedsBuild();
                  },
                );
              },
            ),
            const SizedBox(height: 20),
            _buildSectionHeader(context, "Reader"),
            _buildSwitchTile(
              context,
              title: "Open PDF externally",
              subtitle: "Use your default PDF viewer",
              value: openPdfExternal,
              onChanged: (val) {
                ref.read(openPdfWithExternalAppProvider.notifier).state = val;
                dataBase.savePreference('openPdfwithExternalApp', val);
              },
            ),
            _buildSwitchTile(
              context,
              title: "Open EPUB externally",
              subtitle: "Use your default EPUB reader",
              value: openEpubExternal,
              onChanged: (val) {
                ref.read(openEpubWithExternalAppProvider.notifier).state = val;
                dataBase.savePreference('openEpubwithExternalApp', val);
              },
            ),
            const SizedBox(height: 20),
            _buildSectionHeader(context, "Advanced"),
            _buildSwitchTile(
              context,
              title: "Manual Download Button",
              subtitle: "Show button to manually trigger downloads",
              value: showManualDownload,
              onChanged: (val) {
                ref.read(showManualDownloadButtonProvider.notifier).state = val;
                dataBase.savePreference('showManualDownloadButton', val);
              },
            ),
            const SizedBox(height: 20),
            _buildSectionHeader(context, "About"),
            _buildSettingTile(
              context,
              title: "About OpenlibExtended",
              icon: Icons.info_outline,
              onTap: () {
                Navigator.push(context,
                    MaterialPageRoute(builder: (context) => const AboutPage()));
              },
            ),
            const SizedBox(height: 20),
            _buildSectionHeader(context, "Developer"),
            _buildSettingTile(
              context,
              title: "Redo Onboarding",
              subtitle: "Reset app setup and start over",
              icon: Icons.restart_alt,
              onTap: () async {
                // Clear relevant preferences
                await dataBase.savePreference('onboardingCompleted', 0);

                if (context.mounted) {
                  Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute(
                        builder: (context) => const OnboardingPage()),
                    (route) => false,
                  );
                }
              },
            ),
            const Padding(
              padding: EdgeInsets.only(left: 5, right: 5, top: 20, bottom: 5),
              child: Text(
                "Updates",
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const _UpdateSettingsWidget(),
            const SizedBox(height: 40),
            Center(
              child: Text(
                "Version 1.0.11+14",
                style: TextStyle(
                  color: Theme.of(context).colorScheme.tertiary,
                  fontSize: 12,
                ),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10, left: 4),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.bold,
          color: Theme.of(context).colorScheme.primary.withOpacity(0.8),
        ),
      ),
    );
  }

  Widget _buildSettingCard(BuildContext context,
      {required String title, required Widget child}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }

  Widget _buildSettingTile(BuildContext context,
      {required String title,
      String? subtitle,
      IconData? icon,
      Widget? trailing,
      required VoidCallback onTap}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        onTap: onTap,
        leading: icon != null
            ? Icon(icon, color: Theme.of(context).colorScheme.secondary)
            : null,
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: subtitle != null
            ? Text(subtitle, style: const TextStyle(fontSize: 12))
            : null,
        trailing: trailing ?? const Icon(Icons.chevron_right),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  Widget _buildSwitchTile(BuildContext context,
      {required String title,
      String? subtitle,
      required bool value,
      required ValueChanged<bool> onChanged}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: SwitchListTile(
        value: value,
        onChanged: onChanged,
        activeColor: Theme.of(context).colorScheme.secondary,
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: subtitle != null
            ? Text(subtitle, style: const TextStyle(fontSize: 12))
            : null,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}

class _InstanceSelectorWidget extends ConsumerStatefulWidget {
  const _InstanceSelectorWidget();

  @override
  ConsumerState<_InstanceSelectorWidget> createState() =>
      _InstanceSelectorWidgetState();
}

class _InstanceSelectorWidgetState
    extends ConsumerState<_InstanceSelectorWidget> {
  String? _selectedInstanceId;

  @override
  void initState() {
    super.initState();
    // Load selected instance after widget is mounted
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadSelectedInstance();
    });
  }

  Future<void> _loadSelectedInstance() async {
    final manager = ref.read(instanceManagerProvider);
    final id = await manager.getSelectedInstanceId();
    if (mounted) {
      setState(() {
        _selectedInstanceId = id;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentInstanceAsync = ref.watch(currentInstanceProvider);
    final allInstancesAsync = ref.watch(archiveInstancesProvider);

    return currentInstanceAsync.when(
      data: (currentInstance) {
        return allInstancesAsync.when(
          data: (instances) {
            final selectedId = _selectedInstanceId ?? currentInstance.id;

            // Ensure selected instance is in the list (handle disabled instances)
            final selectedInstanceExists =
                instances.any((i) => i.id == selectedId);
            final effectiveSelectedId =
                selectedInstanceExists ? selectedId : currentInstance.id;

            return Padding(
              padding: const EdgeInsets.only(left: 5, right: 5, top: 10),
              child: Container(
                height: 61,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(5),
                  color: Theme.of(context).colorScheme.tertiaryContainer,
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          "Current Instance",
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.tertiary,
                          ),
                        ),
                      ),
                      Expanded(
                        child: DropdownButton<String>(
                          isExpanded: true,
                          value: effectiveSelectedId,
                          underline: Container(),
                          items: instances.map((instance) {
                            return DropdownMenuItem<String>(
                              value: instance.id,
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      instance.name,
                                      style: const TextStyle(fontSize: 13),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  if (!instance.enabled)
                                    const Padding(
                                      padding: EdgeInsets.only(left: 4.0),
                                      child: Text(
                                        '(disabled)',
                                        style: TextStyle(
                                            fontSize: 10, color: Colors.grey),
                                      ),
                                    ),
                                ],
                              ),
                            );
                          }).toList(),
                          onChanged: (String? newValue) async {
                            if (newValue != null) {
                              // Capture context-dependent objects before async gap
                              final scaffoldMessenger =
                                  ScaffoldMessenger.of(context);

                              setState(() {
                                _selectedInstanceId = newValue;
                              });
                              final manager = ref.read(instanceManagerProvider);
                              await manager.setSelectedInstanceId(newValue);
                              ref.invalidate(currentInstanceProvider);

                              if (!mounted) return;
                              scaffoldMessenger.showSnackBar(
                                const SnackBar(
                                  content:
                                      Text('Instance changed successfully'),
                                  duration: Duration(seconds: 2),
                                ),
                              );
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
          loading: () => Padding(
            padding: const EdgeInsets.only(left: 5, right: 5, top: 10),
            child: Container(
              height: 61,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(5),
                color: Theme.of(context).colorScheme.tertiaryContainer,
              ),
              child: const Center(child: CircularProgressIndicator()),
            ),
          ),
          error: (error, stack) => Padding(
            padding: const EdgeInsets.only(left: 5, right: 5, top: 10),
            child: Container(
              height: 61,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(5),
                color: Theme.of(context).colorScheme.tertiaryContainer,
              ),
              child: Center(
                child: Text(
                  'Error loading instances',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            ),
          ),
        );
      },
      loading: () => Padding(
        padding: const EdgeInsets.only(left: 5, right: 5, top: 10),
        child: Container(
          height: 61,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(5),
            color: Theme.of(context).colorScheme.tertiaryContainer,
          ),
          child: const Center(child: CircularProgressIndicator()),
        ),
      ),
      error: (error, stack) => Padding(
        padding: const EdgeInsets.only(left: 5, right: 5, top: 10),
        child: Container(
          height: 61,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(5),
            color: Theme.of(context).colorScheme.tertiaryContainer,
          ),
          child: Center(
            child: Text(
              'Error loading instance',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        ),
      ),
    );
  }
}

// Auto-rank instances widget with toggle and manual rank button
class _AutoRankInstancesWidget extends ConsumerStatefulWidget {
  const _AutoRankInstancesWidget();

  @override
  ConsumerState<_AutoRankInstancesWidget> createState() =>
      _AutoRankInstancesWidgetState();
}

class _AutoRankInstancesWidgetState
    extends ConsumerState<_AutoRankInstancesWidget> {
  bool _isRanking = false;
  bool _autoRankEnabled = true;

  @override
  void initState() {
    super.initState();
    _loadAutoRankSetting();
  }

  Future<void> _loadAutoRankSetting() async {
    final manager = ref.read(instanceManagerProvider);
    final enabled = await manager.isAutoRankEnabled();
    if (mounted) {
      setState(() {
        _autoRankEnabled = enabled;
      });
      ref.read(autoRankInstancesProvider.notifier).state = enabled;
    }
  }

  Future<void> _toggleAutoRank(bool value) async {
    final manager = ref.read(instanceManagerProvider);
    await manager.setAutoRankEnabled(value);
    if (mounted) {
      setState(() {
        _autoRankEnabled = value;
      });
      ref.read(autoRankInstancesProvider.notifier).state = value;
    }
  }

  Future<void> _rankNow() async {
    if (_isRanking) return;

    setState(() {
      _isRanking = true;
    });

    final scaffoldMessenger = ScaffoldMessenger.of(context);

    try {
      final manager = ref.read(instanceManagerProvider);
      final results = await manager.rankInstancesBySpeed();

      // Refresh the instances provider to reflect new order
      ref.invalidate(archiveInstancesProvider);
      ref.invalidate(currentInstanceProvider);

      if (!mounted) return;

      // Find the fastest instance
      String fastestName = "Unknown";
      int? fastestTime;
      final instances = await manager.getInstances();
      for (final instance in instances) {
        final time = results[instance.id];
        if (time != null && (fastestTime == null || time < fastestTime)) {
          fastestTime = time;
          fastestName = instance.name;
        }
      }

      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Text(
            fastestTime != null
                ? "Ranked! Fastest: $fastestName (${fastestTime}ms)"
                : "Ranking complete",
          ),
          duration: const Duration(seconds: 3),
        ),
      );
    } catch (e) {
      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Text("Ranking failed: ${e.toString()}"),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isRanking = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 5, right: 5, top: 10),
          child: Container(
            height: 75,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(5),
              color: Theme.of(context).colorScheme.tertiaryContainer,
            ),
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          "Auto-Rank Instances",
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.tertiary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          "Automatically sort by speed on startup",
                          style: TextStyle(
                            fontSize: 11,
                            color: Theme.of(context)
                                .colorScheme
                                .tertiary
                                .withAlpha(140),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: _autoRankEnabled,
                    thumbColor: WidgetStateProperty.resolveWith((states) =>
                        states.contains(WidgetState.selected)
                            ? Colors.green
                            : null),
                    onChanged: _toggleAutoRank,
                  ),
                ],
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(left: 5, right: 5, top: 10),
          child: InkWell(
            onTap: _isRanking ? null : _rankNow,
            child: Container(
              height: 61,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(5),
                color: Theme.of(context).colorScheme.tertiaryContainer,
              ),
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      "Rank Instances Now",
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: _isRanking
                            ? Theme.of(context)
                                .colorScheme
                                .tertiary
                                .withAlpha(100)
                            : Theme.of(context).colorScheme.tertiary,
                      ),
                    ),
                    _isRanking
                        ? SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Theme.of(context).colorScheme.secondary,
                            ),
                          )
                        : const Icon(Icons.speed),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// Update settings widget with prerelease toggle and check button
class _UpdateSettingsWidget extends StatefulWidget {
  const _UpdateSettingsWidget();

  @override
  State<_UpdateSettingsWidget> createState() => _UpdateSettingsWidgetState();
}

class _UpdateSettingsWidgetState extends State<_UpdateSettingsWidget> {
  final UpdateCheckerService _updateChecker = UpdateCheckerService();
  bool _includePrereleases = false;
  bool _isChecking = false;

  @override
  void initState() {
    super.initState();
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    final value = await _updateChecker.getIncludePrereleases();
    if (mounted) {
      setState(() {
        _includePrereleases = value;
      });
    }
  }

  Future<void> _checkForUpdates() async {
    setState(() {
      _isChecking = true;
    });

    try {
      final result = await _updateChecker.checkForUpdates(
        includePrereleases: _includePrereleases,
      );

      if (!mounted) return;

      if (result.updateAvailable && result.latestRelease != null) {
        await _updateChecker.showUpdateDialog(context, result.latestRelease!);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
                Text("You're on the latest version (${result.currentVersion})"),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Failed to check for updates: ${e.toString()}"),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isChecking = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 5, right: 5, top: 10),
          child: Container(
            height: 61,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(5),
              color: Theme.of(context).colorScheme.tertiaryContainer,
            ),
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          "Include Beta Updates",
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.tertiary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          "Get pre-release versions",
                          style: TextStyle(
                            fontSize: 11,
                            color: Theme.of(context)
                                .colorScheme
                                .tertiary
                                .withAlpha(140),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: _includePrereleases,
                    thumbColor: WidgetStateProperty.resolveWith((states) =>
                        states.contains(WidgetState.selected)
                            ? Colors.orange
                            : null),
                    onChanged: (bool value) async {
                      setState(() {
                        _includePrereleases = value;
                      });
                      await _updateChecker.setIncludePrereleases(value);
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(left: 5, right: 5, top: 10),
          child: InkWell(
            onTap: _isChecking ? null : _checkForUpdates,
            child: Container(
              height: 61,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(5),
                color: Theme.of(context).colorScheme.tertiaryContainer,
              ),
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      "Check for Updates",
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.tertiary,
                      ),
                    ),
                    _isChecking
                        ? SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Theme.of(context).colorScheme.secondary,
                            ),
                          )
                        : Icon(
                            Icons.refresh,
                            color: Theme.of(context).colorScheme.secondary,
                          ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
