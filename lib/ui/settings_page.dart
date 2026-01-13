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
import 'package:openlib/services/logger.dart';
import 'package:openlib/services/platform_utils.dart';
import 'package:openlib/services/update_checker.dart';
import 'package:permission_handler/permission_handler.dart';

// Project imports:
import 'package:openlib/services/database.dart';
import 'package:openlib/ui/about_page.dart';
import 'package:openlib/ui/instances_page.dart';
import 'package:openlib/ui/components/page_title_widget.dart';

import 'package:openlib/state/state.dart'
    show
        themeModeProvider,
        openPdfWithExternalAppProvider,
        openEpubWithExternalAppProvider,
        showManualDownloadButtonProvider,
        instanceManagerProvider,
        currentInstanceProvider,
        archiveInstancesProvider;

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
    MyLibraryDb dataBase = MyLibraryDb.instance;
    return Padding(
      padding: const EdgeInsets.only(left: 5, right: 5, top: 10),
      child: SingleChildScrollView(
        scrollDirection: Axis.vertical,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const TitleText("Settings"),
            const Padding(
              padding: EdgeInsets.only(left: 5, right: 5, top: 10),
              child: Text(
                "Archive Instance",
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const _InstanceSelectorWidget(),
            _PaddedContainer(
              onClick: () {
                Navigator.push(context,
                    MaterialPageRoute(builder: (BuildContext context) {
                  return const InstancesPage();
                }));
              },
              children: [
                Text(
                  "Manage Instances",
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.tertiary,
                  ),
                ),
                const Icon(Icons.settings),
              ],
            ),
            const Padding(
              padding: EdgeInsets.only(left: 5, right: 5, top: 20, bottom: 5),
              child: Text(
                "General Settings",
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            _PaddedContainer(
              children: [
                Text(
                  "Dark Mode",
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.tertiary,
                  ),
                ),
                Switch(
                  // This bool value toggles the switch.
                  value: ref.watch(themeModeProvider) == ThemeMode.dark,
                  activeThumbColor: Colors.red,
                  onChanged: (bool value) {
                    ref.read(themeModeProvider.notifier).state =
                        value == true ? ThemeMode.dark : ThemeMode.light;
                    dataBase.savePreference('darkMode', value);
                    // Only update system UI overlay on Android
                    if (Platform.isAndroid) {
                      SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
                          systemNavigationBarColor:
                              value ? Colors.black : Colors.grey.shade200));
                    }
                  },
                )
              ],
            ),
            _PaddedContainer(
              children: [
                Text(
                  "Open PDF with External Reader",
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.tertiary,
                  ),
                ),
                Switch(
                  // This bool value toggles the switch.
                  value: ref.watch(openPdfWithExternalAppProvider),
                  activeThumbColor: Colors.red,
                  onChanged: (bool value) {
                    ref.read(openPdfWithExternalAppProvider.notifier).state =
                        value;
                    dataBase.savePreference('openPdfwithExternalApp', value);
                  },
                )
              ],
            ),
            _PaddedContainer(
              children: [
                Text(
                  "Open Epub with External Reader",
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.tertiary,
                  ),
                ),
                Switch(
                  // This bool value toggles the switch.
                  value: ref.watch(
                    openEpubWithExternalAppProvider,
                  ),
                  activeThumbColor: Colors.red,
                  onChanged: (bool value) {
                    ref.read(openEpubWithExternalAppProvider.notifier).state =
                        value;
                    dataBase.savePreference('openEpubwithExternalApp', value);
                  },
                )
              ],
            ),
            const Padding(
              padding: EdgeInsets.only(left: 5, right: 5, top: 20, bottom: 5),
              child: Text(
                "Download Settings",
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            _PaddedContainer(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Show Manual Download Button",
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.tertiary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        "Enable if background download doesn't work",
                        style: TextStyle(
                          fontSize: 11,
                          color: Theme.of(context).colorScheme.tertiary.withAlpha(140),
                        ),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: ref.watch(showManualDownloadButtonProvider),
                  activeThumbColor: Colors.red,
                  onChanged: (bool value) {
                    ref.read(showManualDownloadButtonProvider.notifier).state =
                        value;
                    dataBase.savePreference('showManualDownloadButton', value);
                  },
                )
              ],
            ),
            const Padding(
              padding: EdgeInsets.only(left: 5, right: 5, top: 20, bottom: 5),
              child: Text(
                "Storage & Files",
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            _PaddedContainer(
                onClick: () async {
                  final currentDirectory =
                      await dataBase.getPreference('bookStorageDirectory');
                  String? pickedDirectory =
                      await FilePicker.platform.getDirectoryPath();
                  if (pickedDirectory == null) {
                    return;
                  }
                  await requestStoragePermission();
                  // Attempt moving existing books to the new directory
                  moveFolderContents(currentDirectory, pickedDirectory);
                  dataBase.savePreference(
                      'bookStorageDirectory', pickedDirectory);
                },
                children: [
                  Text(
                    "Change storage path",
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.tertiary,
                    ),
                  ),
                  const Icon(Icons.folder),
                ]),
            _PaddedContainer(
              onClick: () async {
                try {
                  final logger = AppLogger();
                  await logger.exportLogs();
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Failed to export logs: ${e.toString()}'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                }
              },
              children: [
                Text(
                  "Export Logs (Last 5 Minutes)",
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.tertiary,
                  ),
                ),
                const Icon(Icons.file_download),
              ],
            ),
            _PaddedContainer(
              onClick: () {
                Navigator.push(context,
                    MaterialPageRoute(builder: (BuildContext context) {
                  return const AboutPage();
                }));
              },
              children: [
                Text(
                  "About",
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.tertiary,
                  ),
                ),
              ],
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
          ],
        ),
      ),
    );
  }
}

class _PaddedContainer extends StatelessWidget {
  const _PaddedContainer({this.onClick, required this.children});

  final VoidCallback? onClick;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 5, right: 5, top: 10),
      child: InkWell(
        onTap: onClick,
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
              children: children,
            ),
          ),
        ),
      ),
    );
  }
}

class _InstanceSelectorWidget extends ConsumerStatefulWidget {
  const _InstanceSelectorWidget();

  @override
  ConsumerState<_InstanceSelectorWidget> createState() => _InstanceSelectorWidgetState();
}

class _InstanceSelectorWidgetState extends ConsumerState<_InstanceSelectorWidget> {
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
            final selectedInstanceExists = instances.any((i) => i.id == selectedId);
            final effectiveSelectedId = selectedInstanceExists ? selectedId : currentInstance.id;

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
                                        style: TextStyle(fontSize: 10, color: Colors.grey),
                                      ),
                                    ),
                                ],
                              ),
                            );
                          }).toList(),
                          onChanged: (String? newValue) async {
                            if (newValue != null) {
                              // Capture context-dependent objects before async gap
                              final scaffoldMessenger = ScaffoldMessenger.of(context);
                              
                              setState(() {
                                _selectedInstanceId = newValue;
                              });
                              final manager = ref.read(instanceManagerProvider);
                              await manager.setSelectedInstanceId(newValue);
                              ref.invalidate(currentInstanceProvider);
                              
                              if (!mounted) return;
                              scaffoldMessenger.showSnackBar(
                                const SnackBar(
                                  content: Text('Instance changed successfully'),
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
            content: Text("You're on the latest version (${result.currentVersion})"),
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
                            color: Theme.of(context).colorScheme.tertiary.withAlpha(140),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: _includePrereleases,
                    activeThumbColor: Colors.orange,
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
