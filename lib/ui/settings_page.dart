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
import 'package:permission_handler/permission_handler.dart';

// Project imports:
import 'package:openlib/services/database.dart';
import 'package:openlib/services/instance_manager.dart';
import 'package:openlib/ui/about_page.dart';
import 'package:openlib/ui/instances_page.dart';
import 'package:openlib/ui/components/page_title_widget.dart';

import 'package:openlib/state/state.dart'
    show
        themeModeProvider,
        openPdfWithExternalAppProvider,
        openEpubWithExternalAppProvider,
        instanceManagerProvider,
        currentInstanceProvider,
        enabledInstancesProvider;

Future<void> requestStoragePermission() async {
  bool permissionGranted = false;
  // Check whether the device is running Android 11 or higher
  DeviceInfoPlugin plugin = DeviceInfoPlugin();
  AndroidDeviceInfo android = await plugin.androidInfo;
  // Android < 11
  if (android.version.sdkInt < 33) {
    if (await Permission.storage.request().isGranted) {
      permissionGranted = true;
    } else if (await Permission.storage.request().isPermanentlyDenied) {
      await openAppSettings();
    }
  }
  // Android > 11
  else {
    if (await Permission.manageExternalStorage.request().isGranted) {
      permissionGranted = true;
    } else if (await Permission.manageExternalStorage
        .request()
        .isPermanentlyDenied) {
      await openAppSettings();
    } else if (await Permission.manageExternalStorage.request().isDenied) {
      permissionGranted = false;
    }
  }
  print("Storage permission status: $permissionGranted");
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
            _InstanceSelectorWidget(),
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
                Icon(Icons.settings),
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
                  activeColor: Colors.red,
                  onChanged: (bool value) {
                    ref.read(themeModeProvider.notifier).state =
                        value == true ? ThemeMode.dark : ThemeMode.light;
                    dataBase.savePreference('darkMode', value);
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
                  activeColor: Colors.red,
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
                  activeColor: Colors.red,
                  onChanged: (bool value) {
                    ref.read(openEpubWithExternalAppProvider.notifier).state =
                        value;
                    dataBase.savePreference('openEpubwithExternalApp', value);
                  },
                )
              ],
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
                  Icon(Icons.folder),
                ]),
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
            )
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
    _loadSelectedInstance();
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
    final enabledInstancesAsync = ref.watch(enabledInstancesProvider);

    return currentInstanceAsync.when(
      data: (currentInstance) {
        return enabledInstancesAsync.when(
          data: (instances) {
            final selectedId = _selectedInstanceId ?? currentInstance.id;

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
                          value: selectedId,
                          underline: Container(),
                          items: instances.map((instance) {
                            return DropdownMenuItem<String>(
                              value: instance.id,
                              child: Text(
                                instance.name,
                                style: const TextStyle(fontSize: 13),
                                overflow: TextOverflow.ellipsis,
                              ),
                            );
                          }).toList(),
                          onChanged: (String? newValue) async {
                            if (newValue != null) {
                              setState(() {
                                _selectedInstanceId = newValue;
                              });
                              final manager = ref.read(instanceManagerProvider);
                              await manager.setSelectedInstanceId(newValue);
                              ref.invalidate(currentInstanceProvider);
                              
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Instance changed successfully'),
                                    duration: Duration(seconds: 2),
                                  ),
                                );
                              }
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
