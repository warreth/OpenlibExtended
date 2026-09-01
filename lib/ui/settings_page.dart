// Dart imports:
import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:openlib/services/backup_service.dart';

// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:openlib/l10n/app_localizations.dart';
import 'package:openlib/services/files.dart';
import 'package:openlib/services/platform_utils.dart';
import 'package:openlib/services/update_checker.dart';
import 'package:permission_handler/permission_handler.dart';

// Project imports:
import 'package:openlib/services/database.dart';
import 'package:openlib/services/logger.dart';
import 'package:openlib/services/search_manager.dart';
import 'package:openlib/ui/components/snack_bar_widget.dart';
import 'package:openlib/ui/about_page.dart';
import 'package:openlib/ui/instances_page.dart';
import 'package:openlib/ui/onboarding/onboarding_page.dart';

import 'package:openlib/state/state.dart'
    show
        themeModeProvider,
        fontSizeScaleProvider,
        openPdfWithExternalAppProvider,
        openEpubWithExternalAppProvider,
        showManualDownloadButtonProvider,
        autoRankInstancesProvider,
        instanceManagerProvider,
        currentInstanceProvider,
        archiveInstancesProvider,
        donationKeyProvider,
        myLibraryProvider,
        searchProviderToggles,
        localeOverrideProvider;

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

// ---------------------------------------------------------------------------
// Shared building blocks: every settings row renders through these, so all
// sections share one card shape, spacing and typography.
// ---------------------------------------------------------------------------

/// Section label above a group of tiles.
class _SettingsSectionHeader extends StatelessWidget {
  const _SettingsSectionHeader(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10, left: 4, top: 4),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.bold,
          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.8),
        ),
      ),
    );
  }
}

/// Card wrapping an embedded control (dropdown, slider) with a bold label.
class _SettingsCard extends StatelessWidget {
  const _SettingsCard({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
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
}

/// Tappable row with optional icon, subtitle and trailing element. Pass a
/// [busy] flag to swap the trailing chevron for a progress spinner.
class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.title,
    this.subtitle,
    this.icon,
    this.busy = false,
    this.onTap,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final bool busy;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final Widget resolvedTrailing = busy
        ? const SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : const Icon(Icons.chevron_right);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: scheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          onTap: onTap,
          leading: icon != null ? Icon(icon, color: scheme.secondary) : null,
          title:
              Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: subtitle != null
              ? Text(subtitle!, style: const TextStyle(fontSize: 12))
              : null,
          trailing: resolvedTrailing,
        ),
      ),
    );
  }
}

/// Switch row in the same card shape as [_SettingsTile].
class _SettingsSwitchTile extends StatelessWidget {
  const _SettingsSwitchTile({
    required this.title,
    this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Theme.of(context).colorScheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: SwitchListTile(
          value: value,
          onChanged: onChanged,
          activeThumbColor: Theme.of(context).colorScheme.secondary,
          title:
              Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: subtitle != null
              ? Text(subtitle!, style: const TextStyle(fontSize: 12))
              : null,
        ),
      ),
    );
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
    final fontSizeScale = ref.watch(fontSizeScaleProvider);
    final l10n = AppLocalizations.of(context);

    MyLibraryDb dataBase = MyLibraryDb.instance;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 10.0),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.settingsTitle,
                style: Theme.of(context).textTheme.displayLarge),
            const SizedBox(height: 20),
            _SettingsSectionHeader(l10n.searchProvidersSection),
            const _SearchProvidersWidget(),
            _SettingsSectionHeader(l10n.libraryInstancesSection),
            _SettingsCard(
              title: l10n.archiveInstance,
              child: _InstanceSelectorWidget(),
            ),
            _SettingsTile(
              title: l10n.mirrorsAndProviders,
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
            _SettingsSectionHeader(l10n.appearanceSection),
            _SettingsCard(
              title: l10n.languageSetting,
              child: _LanguageSelectorWidget(),
            ),
            _SettingsCard(
              title: l10n.themeTitle,
              child: DropdownButtonFormField<ThemeMode>(
                initialValue: themeMode,
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.zero,
                ),
                items: [
                  DropdownMenuItem(
                      value: ThemeMode.system,
                      child: Text(l10n.followSystem)),
                  DropdownMenuItem(
                      value: ThemeMode.light, child: Text(l10n.lightTheme)),
                  DropdownMenuItem(
                      value: ThemeMode.dark, child: Text(l10n.darkTheme)),
                ],
                onChanged: (ThemeMode? val) {
                  if (val != null) {
                    ref.read(themeModeProvider.notifier).setTheme(val);
                  }
                },
              ),
            ),
            _SettingsCard(
              title: l10n.fontSizeTitle,
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(l10n.scaleValue(fontSizeScale.toStringAsFixed(1))),
                      Text(l10n.preview,
                          textScaler: TextScaler.linear(fontSizeScale)),
                    ],
                  ),
                  Slider(
                    value: fontSizeScale,
                    min: 0.8,
                    max: 2.0,
                    divisions: 12,
                    label: fontSizeScale.toStringAsFixed(1),
                    onChanged: (val) {
                      ref.read(fontSizeScaleProvider.notifier).state = val;
                    },
                    onChangeEnd: (val) {
                      dataBase.savePreference('fontSizeScale', val.toString());
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            _SettingsSectionHeader(l10n.generalSection),
            FutureBuilder<dynamic>(
              future: dataBase.getPreference('bookStorageDirectory'),
              builder: (context, snapshot) {
                String subtitle = "Change where books are saved";
                if (snapshot.hasData && snapshot.data is String) {
                  subtitle = snapshot.data as String;
                }
                return _SettingsTile(
                  title: l10n.storageLocation,
                  subtitle: subtitle,
                  icon: Icons.folder,
                  onTap: () async {
                    final currentDirectory =
                        await dataBase.getPreference('bookStorageDirectory');
                    String? pickedDirectory = await pickBookStorageDirectory();
                    if (pickedDirectory == null) return;
                    await requestStoragePermission();

                    // Move the books from wherever they live now - the
                    // old code only moved them when leaving the internal
                    // default, so switching between two custom folders
                    // left every file behind and the library showed
                    // "File not found" on the next open.
                    if (currentDirectory != pickedDirectory) {
                      await moveLibraryFiles(currentDirectory, pickedDirectory);
                    }

                    await dataBase.savePreference(
                        'bookStorageDirectory', pickedDirectory);
                    await scanAndImportBooks(pickedDirectory, dataBase, ref);
                    // ignore: unused_result
                    ref.refresh(myLibraryProvider);
                    // The FutureBuilder reads the db future directly, so
                    // rebuild manually to show the new path immediately.
                    (context as Element).markNeedsBuild();
                  },
                );
              },
            ),
            const SizedBox(height: 20),
            _SettingsSectionHeader(l10n.readerSection),
            _SettingsSwitchTile(
              title: l10n.openPdfExternally,
              subtitle: l10n.useDefaultPdfViewer,
              value: openPdfExternal,
              onChanged: (val) {
                ref.read(openPdfWithExternalAppProvider.notifier).state = val;
                dataBase.savePreference('openPdfwithExternalApp', val);
              },
            ),
            _SettingsSwitchTile(
              title: l10n.openEpubExternally,
              subtitle: l10n.useDefaultEpubReader,
              value: openEpubExternal,
              onChanged: (val) {
                ref.read(openEpubWithExternalAppProvider.notifier).state = val;
                dataBase.savePreference('openEpubwithExternalApp', val);
              },
            ),
            const SizedBox(height: 20),
            _SettingsSectionHeader(l10n.advancedSection),
            _SettingsSwitchTile(
              title: l10n.manualDownloadButton,
              subtitle: l10n.showManualDownloadHint,
              value: showManualDownload,
              onChanged: (val) {
                ref.read(showManualDownloadButtonProvider.notifier).state = val;
                dataBase.savePreference('showManualDownloadButton', val);
              },
            ),
            _SettingsTile(
              title: l10n.donationKeyTitle,
              subtitle: l10n.enterKeyForFasterDownloads,
              icon: Icons.key,
              onTap: () => _showDonationKeyDialog(context, ref, dataBase),
            ),
            const SizedBox(height: 20),
            _SettingsSectionHeader(l10n.backupSection),
            _BackupSettingsWidget(database: dataBase),
            const SizedBox(height: 20),
            _SettingsSectionHeader(l10n.updatesSection),
            const _UpdateSettingsWidget(),
            const SizedBox(height: 20),
            _SettingsSectionHeader(l10n.aboutSection),
            _SettingsTile(
              title: l10n.aboutOpenlib,
              icon: Icons.info_outline,
              onTap: () {
                Navigator.push(context,
                    MaterialPageRoute(builder: (context) => const AboutPage()));
              },
            ),
            _SettingsTile(
              title: l10n.redoOnboarding,
              subtitle: l10n.resetAppSetup,
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
            _SettingsTile(
              title: l10n.exportLogs,
              subtitle: l10n.shareDiagnosticLogs,
              icon: Icons.bug_report,
              onTap: () async {
                final l10n = AppLocalizations.of(context);
                try {
                  await AppLogger().exportLogs();
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                          content: Text(l10n.failedExportLogs('$e'))),
                    );
                  }
                }
              },
            ),
            const SizedBox(height: 20),
            FutureBuilder<PackageInfo>(
              future: PackageInfo.fromPlatform(),
              builder: (context, snapshot) {
                if (snapshot.hasData) {
                  return Center(
                    child: Text(
                      "Version ${snapshot.data!.version}+${snapshot.data!.buildNumber}",
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.tertiary,
                        fontSize: 12,
                      ),
                    ),
                  );
                }
                return const SizedBox.shrink();
              },
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  void _showDonationKeyDialog(
      BuildContext context, WidgetRef ref, MyLibraryDb dataBase) {
    final dialogL10n = AppLocalizations.of(context);
    final currentKey = ref.read(donationKeyProvider);
    final controller = TextEditingController(text: currentKey);
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(AppLocalizations.of(context).donationKeyDialog),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(
            hintText: dialogL10n.enterYourKey,
            helperText: dialogL10n.donationKeyHelper,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(dialogL10n.cancel),
          ),
          TextButton(
            onPressed: () {
              final newKey = controller.text.trim();
              ref.read(donationKeyProvider.notifier).state = newKey;
              dataBase.savePreference('donationKey', newKey);
              Navigator.pop(dialogContext);
            },
            child: Text(dialogL10n.save),
          ),
        ],
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

            return DropdownButton<String>(
              isExpanded: true,
              value: effectiveSelectedId,
              underline: const SizedBox.shrink(),
              items: instances.map((instance) {
                return DropdownMenuItem<String>(
                  value: instance.id,
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          instance.name,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (!instance.enabled)
                        Text(
                          ' (disabled)',
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurface
                                .withAlpha(140),
                          ),
                        ),
                    ],
                  ),
                );
              }).toList(),
              onChanged: (String? newValue) async {
                if (newValue == null) return;
                // Capture context-dependent objects before async gap
                final scaffoldMessenger = ScaffoldMessenger.of(context);
                final instanceChangedMsg =
                    AppLocalizations.of(context).instanceChanged;

                setState(() {
                  _selectedInstanceId = newValue;
                });
                final manager = ref.read(instanceManagerProvider);
                await manager.setSelectedInstanceId(newValue);
                ref.invalidate(currentInstanceProvider);

                if (!mounted) return;
                scaffoldMessenger.showSnackBar(
                  SnackBar(
                    content: Text(instanceChangedMsg),
                    duration: const Duration(seconds: 2),
                  ),
                );
              },
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, stack) => _instanceLoadError(context),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stack) => _instanceLoadError(context),
    );
  }

  Widget _instanceLoadError(BuildContext context) {
    return Text(
      'Error loading instances',
      style: TextStyle(color: Theme.of(context).colorScheme.error),
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
    final rankL10n = AppLocalizations.of(context);

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
                ? rankL10n.rankedFastest(
                    fastestName, '$fastestTime')
                : rankL10n.rankingComplete,
          ),
          duration: const Duration(seconds: 3),
        ),
      );
    } catch (e) {
      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Text(rankL10n.rankingFailed(e.toString())),
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
    final l10n = AppLocalizations.of(context);
    return Column(
      children: [
        _SettingsSwitchTile(
          title: l10n.autoRankInstances,
          subtitle: l10n.sortBySpeedOnStartup,
          value: _autoRankEnabled,
          onChanged: _toggleAutoRank,
        ),
        _SettingsTile(
          title: l10n.rankInstancesNow,
          icon: Icons.speed,
          busy: _isRanking,
          onTap: _isRanking ? null : _rankNow,
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
    final updateL10n = AppLocalizations.of(context);
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
                Text(updateL10n.onLatestVersion(result.currentVersion)),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(updateL10n.failedCheckUpdates(e.toString())),
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
    final l10n = AppLocalizations.of(context);
    return Column(
      children: [
        _SettingsSwitchTile(
          title: l10n.includeBetaUpdates,
          subtitle: l10n.getPreReleaseVersions,
          value: _includePrereleases,
          onChanged: (bool value) async {
            setState(() {
              _includePrereleases = value;
            });
            await _updateChecker.setIncludePrereleases(value);
          },
        ),
        _SettingsTile(
          title: l10n.checkForUpdates,
          icon: Icons.refresh,
          busy: _isChecking,
          onTap: _isChecking ? null : _checkForUpdates,
        ),
      ],
    );
  }
}

/// Toggles which catalogs the search fans out to. Disabling the last
/// source is refused - there is nothing to search without one.
class _SearchProvidersWidget extends ConsumerWidget {
  const _SearchProvidersWidget();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final enabled = ref.watch(searchProviderToggles);

    return enabled.when(
      data: (enabledIds) {
        final manager = SearchManager();
        return Column(
          children: [
            for (final provider in [
              (
                SearchProviderId.annasArchive,
                "Anna's Archive",
                l10n.providerSourceOriginal
              ),
              (
                SearchProviderId.libgen,
                'Library Genesis',
                l10n.providerLibgenCatalog
              ),
              (
                SearchProviderId.zlibrary,
                'Z-Library',
                l10n.providerZlibMirrors
              ),
            ])
              _SettingsSwitchTile(
                title: provider.$2,
                subtitle: provider.$3,
                value: enabledIds.contains(provider.$1),
                onChanged: (on) async {
                  if (!on && enabledIds.length == 1) {
                    showSnackBar(
                        context: context,
                        message: l10n.atLeastOneSource);
                    return;
                  }
                  await manager.setProviderEnabled(provider.$1, on);
                  // ignore: unused_result
                  ref.refresh(searchProviderToggles);
                },
              ),
          ],
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (e, _) => const SizedBox.shrink(),
    );
  }
}

/// Export/import the whole app state: settings, saved books, reading
/// positions, instances. One JSON file, shareable or pickable.
class _BackupSettingsWidget extends ConsumerWidget {
  const _BackupSettingsWidget({required this.database});

  final MyLibraryDb database;

  Future<void> _export(BuildContext context) async {
    final service = BackupService(database: database);
    final exportL10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final json = await service.createBackupJson();
      final timestamp = DateTime.now()
          .toIso8601String()
          .replaceAll(':', '-')
          .replaceAll('.', '-');
      final fileName = 'openlib_backup_$timestamp.json';

      if (PlatformUtils.isDesktop) {
        final target = await FilePicker.saveFile(
          dialogTitle: exportL10n.saveBackupTitle,
          fileName: fileName,
          type: FileType.custom,
          allowedExtensions: ['json'],
          bytes: Uint8List.fromList(utf8.encode(json)),
        );
        if (target == null) return;
        if (context.mounted) {
          showSnackBar(
              context: context,
              message: AppLocalizations.of(context).backupSaved);
        }
      } else {
        final tempDir = await getTemporaryDirectory();
        final file = File('${tempDir.path}/$fileName');
        await file.writeAsString(json);
        await SharePlus.instance.share(ShareParams(
          files: [XFile(file.path)],
          text: 'OpenlibExtended backup',
        ));
      }
    } catch (e) {
      messenger.showSnackBar(
          SnackBar(content: Text(exportL10n.failedExportBackup('$e'))));
    }
  }

  Future<void> _import(BuildContext context, WidgetRef ref) async {
    final service = BackupService(database: database);
    final importL10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final files = await FilePicker.pickFiles(
        dialogTitle: importL10n.pickBackupFile,
        type: FileType.custom,
        allowedExtensions: ['json'],
      );
      final path = files.single.path;
      if (path == null) return;

      final restored = await service.restoreBackupFile(path);
      if (!restored) {
        if (context.mounted) {
          showSnackBar(
              context: context,
              message: importL10n.notABackup);
        }
        return;
      }
      // Imported preferences/instances must reach the live UI.
      // ignore: unused_result
      ref.refresh(myLibraryProvider);
      // ignore: unused_result
      ref.refresh(searchProviderToggles);
      if (context.mounted) {
        showSnackBar(
            context: context,
            message: AppLocalizations.of(context).backupRestored);
      }
    } catch (e) {
      messenger.showSnackBar(
          SnackBar(content: Text(importL10n.failedImportBackup('$e'))));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      children: [
        _SettingsTile(
          title: 'Export Backup',
          subtitle: 'Save settings, books and instances to a JSON file',
          icon: Icons.file_upload_outlined,
          onTap: () => _export(context),
        ),
        _SettingsTile(
          title: 'Import Backup',
          subtitle: 'Restore from a backup file (replaces current data)',
          icon: Icons.file_download_outlined,
          onTap: () => _import(context, ref),
        ),
      ],
    );
  }
}

// ====================================================================
// LANGUAGE SELECTOR
// Dropdown that pins the app to one of the supported locales, or
// follows the system default. Choice persists in the preferences
// table under the 'locale' key.
// ====================================================================
class _LanguageSelectorWidget extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(localeOverrideProvider);
    final l10n = AppLocalizations.of(context);

    // Native display names: a French user should see 'Francais' even
    // while the app still renders in English.
    const nativeNames = {
      'en': 'English',
      'de': 'Deutsch',
      'fr': 'Français',
      'es': 'Español',
    };

    return DropdownButtonFormField<Locale?>(
      initialValue: locale,
      decoration: const InputDecoration(
        border: InputBorder.none,
        contentPadding: EdgeInsets.zero,
      ),
      items: [
        DropdownMenuItem(
          value: null,
          child: Text(l10n.systemLanguage),
        ),
        ...AppLocalizations.supportedLocales.map(
          (loc) => DropdownMenuItem(
            value: loc,
            child: Text(nativeNames[loc.languageCode] ?? loc.languageCode),
          ),
        ),
      ],
      onChanged: (Locale? val) {
        ref.read(localeOverrideProvider.notifier).state = val;
        MyLibraryDb.instance
            .savePreference('locale', val?.languageCode ?? '')
            .catchError((_) => 0);
      },
    );
  }
}
