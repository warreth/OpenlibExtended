// Dart imports:
import 'dart:io' show Platform;

// Flutter imports:
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart'; // <-- REQUIRED

// Package imports:
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_nav_bar/google_nav_bar.dart';
import 'package:openlib/ui/home_page.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:desktop_webview_window/desktop_webview_window.dart';

// Project imports:
import 'package:openlib/services/database.dart' show MyLibraryDb;
import 'package:openlib/services/platform_utils.dart';
import 'package:openlib/services/update_checker.dart';
import 'package:openlib/ui/mylibrary_page.dart';
import 'package:openlib/ui/search_page.dart';
import 'package:openlib/ui/settings_page.dart';
import 'package:openlib/ui/themes.dart';
import 'package:openlib/ui/onboarding/onboarding_page.dart';

import 'package:openlib/services/files.dart'
    show moveFilesToAndroidInternalStorage;
import 'package:openlib/services/download_manager.dart';
import 'package:openlib/services/download_notification.dart';
import 'package:openlib/services/instance_manager.dart';
import 'package:openlib/state/state.dart'
    show
        ThemeModeNotifier,
        selectedIndexProvider,
        themeModeProvider,
        fontSizeScaleProvider,
        openPdfWithExternalAppProvider,
        openEpubWithExternalAppProvider,
        showManualDownloadButtonProvider,
        autoRankInstancesProvider,
        userAgentProvider,
        cookieProvider,
        donationKeyProvider,
        selectedTypeState,
        selectedSortState,
        selectedFileTypeState,
        selectedLanguageState,
        selectedYearState;

void main(List<String> args) async {
  // Required for desktop_webview_window on Linux - must be called before ensureInitialized
  if (Platform.isLinux || Platform.isWindows) {
    if (runWebViewTitleBarWidget(args)) {
      return;
    }
  }
  WidgetsFlutterBinding.ensureInitialized();

  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  MyLibraryDb dataBase = MyLibraryDb.instance;

  await DownloadManager().initialize();

  ThemeMode startThemeMode = await ThemeModeNotifier.getInitialTheme();

  double fontSizeScale = 1.0;
  try {
    var pref =
        await dataBase.getPreference('fontSizeScale').catchError((e) => 1.0);
    if (pref is num) {
      fontSizeScale = pref.toDouble();
    } else if (pref is String) {
      fontSizeScale = double.tryParse(pref) ?? 1.0;
    }
  } catch (e) {
    fontSizeScale = 1.0;
  }

  bool openPdfwithExternalapp = await dataBase
              .getPreference('openPdfwithExternalApp')
              .catchError((e) => null) ==
          0
      ? false
      : true;

  bool openEpubwithExternalapp = await dataBase
              .getPreference('openEpubwithExternalApp')
              .catchError((e) => null) ==
          0
      ? false
      : true;

  bool showManualDownloadButton = await dataBase
              .getPreference('showManualDownloadButton')
              .catchError((e) => null) ==
          0
      ? false
      : true;

  String browserUserAgent = await dataBase.getBrowserOptions('userAgent');
  String browserCookie = await dataBase.getBrowserOptions('cookie');

  // Load search filter preferences
  String savedType = await dataBase
          .getPreference('filterType')
          .catchError((e) => 'All') as String? ??
      'All';
  String savedSort = await dataBase
          .getPreference('filterSort')
          .catchError((e) => 'Most Relevant') as String? ??
      'Most Relevant';
  String savedFileType = await dataBase
          .getPreference('filterFileType')
          .catchError((e) => 'All') as String? ??
      'All';
  String savedLanguage = await dataBase
          .getPreference('filterLanguage')
          .catchError((e) => 'All') as String? ??
      'All';
  String savedYear = await dataBase
          .getPreference('filterYear')
          .catchError((e) => 'All') as String? ??
      'All';

  String savedDonationKey = await dataBase
          .getPreference('donationKey')
          .catchError((e) => '') as String? ??
      '';

  // Check onboarding status
  bool onboardingCompleted = await dataBase
          .getPreference('onboardingCompleted')
          .catchError((e) => 0) ==
      1;

  if (Platform.isAndroid) {
    // Android-specific setup for system UI overlay colors
    ThemeModeNotifier.updateSystemUi(startThemeMode);
    await moveFilesToAndroidInternalStorage();
  }

  runApp(
    ProviderScope(
      overrides: [
        themeModeProvider
            .overrideWith((ref) => ThemeModeNotifier(startThemeMode)),
        fontSizeScaleProvider.overrideWith((ref) => fontSizeScale),
        openPdfWithExternalAppProvider
            .overrideWith((ref) => openPdfwithExternalapp),
        openEpubWithExternalAppProvider
            .overrideWith((ref) => openEpubwithExternalapp),
        showManualDownloadButtonProvider
            .overrideWith((ref) => showManualDownloadButton),
        donationKeyProvider.overrideWith((ref) => savedDonationKey),
        userAgentProvider.overrideWith((ref) => browserUserAgent),
        cookieProvider.overrideWith((ref) => browserCookie),
        selectedTypeState.overrideWith((ref) => savedType),
        selectedSortState.overrideWith((ref) => savedSort),
        selectedFileTypeState.overrideWith((ref) => savedFileType),
        selectedLanguageState.overrideWith((ref) => savedLanguage),
        selectedYearState.overrideWith((ref) => savedYear),
      ],
      child: MyApp(onboardingCompleted: onboardingCompleted),
    ),
  );
}

class MyApp extends ConsumerWidget {
  final bool onboardingCompleted;
  const MyApp({super.key, this.onboardingCompleted = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      builder: (context, child) {
        final scale = ref.watch(fontSizeScaleProvider);
        return MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        );
      },
      debugShowCheckedModeBanner: false,
      title: 'OpenlibExtended',
      theme: lightTheme,
      darkTheme: darkTheme,
      themeMode: ref.watch(themeModeProvider),
      home: onboardingCompleted ? const MainScreen() : const OnboardingPage(),
    );
  }
}

class MainScreen extends ConsumerStatefulWidget {
  const MainScreen({super.key});

  @override
  ConsumerState<ConsumerStatefulWidget> createState() => _MainScreenState();
}

class _MainScreenState extends ConsumerState<MainScreen> {
  static const List<Widget> _widgetOptions = <Widget>[
    HomePage(),
    SearchPage(),
    MyLibraryPage(),
    SettingsPage(),
  ];

  bool _showExpandedHeader = true; // <-- ONLY new state

  @override
  void initState() {
    super.initState();
    // Request notification permission after first frame (only on mobile)
    if (PlatformUtils.isMobile) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _checkAndRequestNotificationPermission();
      });
    }
    // Check for updates after the app has loaded
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkForUpdatesOnStartup();
    });
    // Auto-rank instances on startup if enabled
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _autoRankInstancesOnStartup();
    });
  }

  Future<void> _autoRankInstancesOnStartup() async {
    // Small delay to let the UI settle first
    await Future.delayed(const Duration(seconds: 1));
    if (!mounted) return;

    try {
      final instanceManager = InstanceManager();
      final didRank = await instanceManager.rankOnStartupIfNeeded();
      if (didRank) {
        debugPrint("Instances auto-ranked on startup");
        // Update the provider state
        ref.read(autoRankInstancesProvider.notifier).state = true;
      }
    } catch (e) {
      // Silently fail - don't interrupt user flow
      debugPrint("Auto-ranking failed: $e");
    }
  }

  Future<void> _checkForUpdatesOnStartup() async {
    // Small delay to let the UI settle
    await Future.delayed(const Duration(seconds: 2));
    if (!mounted) return;

    try {
      await UpdateCheckerService().checkAndShowUpdateDialog(context);
    } catch (e) {
      // Silently fail on startup - user can manually check in settings
      debugPrint("Update check failed: $e");
    }
  }

  Future<void> _checkAndRequestNotificationPermission() async {
    // Skip on desktop platforms
    if (PlatformUtils.isDesktop) return;

    // Check if we should show the permission dialog
    final prefs = MyLibraryDb.instance;
    final hasAskedBefore = await prefs
        .getPreference('hasAskedNotificationPermission')
        .catchError((_) => 0);

    if (hasAskedBefore == 0) {
      // Check current permission status
      final notificationService = DownloadNotificationService();
      final currentStatus =
          await notificationService.checkNotificationPermission();

      if (!currentStatus && mounted) {
        // Show the contextual dialog first
        _showNotificationPermissionDialog();
      } else {
        // Already granted, just mark as asked
        await prefs.savePreference('hasAskedNotificationPermission', 1);
      }
    }
  }

  void _showNotificationPermissionDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(
            'Enable Notifications',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.secondary,
            ),
          ),
          content: Text(
            'OpenlibExtended needs notification permission to show download progress in the background. This helps you track your book downloads even when the app is minimized.',
            style: TextStyle(
              fontSize: 13,
              color: Theme.of(context)
                  .colorScheme
                  .tertiary
                  .withValues(alpha: 0.78),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                // Don't mark as asked so we can ask again later
              },
              child: Text(
                'Maybe Later',
                style: TextStyle(
                  color: Theme.of(context)
                      .colorScheme
                      .tertiary
                      .withValues(alpha: 0.67),
                ),
              ),
            ),
            TextButton(
              onPressed: () async {
                Navigator.of(context).pop();
                // Request permission when user clicks Enable
                await DownloadNotificationService()
                    .requestNotificationPermission();
                // Mark that we've asked
                await MyLibraryDb.instance
                    .savePreference('hasAskedNotificationPermission', 1);
              },
              child: Text(
                'Enable',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.secondary,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final selectedIndex = ref.watch(selectedIndexProvider);

    // Calculate proper header height including status bar on mobile
    final statusBarHeight = MediaQuery.of(context).padding.top;
    final expandedHeaderHeight = PlatformUtils.isMobile
        ? kToolbarHeight + statusBarHeight
        : kToolbarHeight;

    return Scaffold(
      body: NotificationListener<UserScrollNotification>(
        onNotification: (notification) {
          if (notification.direction == ScrollDirection.reverse &&
              _showExpandedHeader) {
            setState(() => _showExpandedHeader = false);
          } else if (notification.direction == ScrollDirection.forward &&
              !_showExpandedHeader) {
            setState(() => _showExpandedHeader = true);
          }
          return false;
        },
        child: Column(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              height: _showExpandedHeader ? expandedHeaderHeight : 0,
              child: AppBar(
                toolbarHeight: kToolbarHeight,
                backgroundColor: Theme.of(context).colorScheme.surface,
                title: const Text("OpenlibExtended"),
                titleTextStyle: Theme.of(context).textTheme.displayLarge,
              ),
            ),
            Expanded(
              child: _widgetOptions.elementAt(selectedIndex),
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Container(
          // Allow bottom bar to be light in light mode
          color: isDarkMode ? const Color(0xFF141414) : Colors.white,
          child: GNav(
            backgroundColor:
                isDarkMode ? const Color(0xFF141414) : Colors.white,
            haptic: true,
            tabBorderRadius: 50,
            tabActiveBorder: Border.all(
              color: Theme.of(context).colorScheme.secondary,
            ),
            tabMargin: const EdgeInsets.fromLTRB(13, 12, 13, 12),
            curve: Curves.fastLinearToSlowEaseIn,
            duration: const Duration(milliseconds: 250),
            gap: 8,
            // Icons adapted for light/dark mode
            color: isDarkMode ? Colors.white : Colors.black,
            activeColor: Colors.white,
            iconSize: 20,
            tabBackgroundColor: Theme.of(context).colorScheme.secondary,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            tabs: const [
              GButton(icon: Icons.trending_up, text: 'Home'),
              GButton(icon: Icons.search, text: 'Search'),
              GButton(
                  icon: Icons.collections_bookmark,
                  text: 'Library'), // Shortened text
              GButton(icon: Icons.settings, text: 'Settings'),
            ],
            selectedIndex: selectedIndex,
            onTabChange: (index) {
              ref.read(selectedIndexProvider.notifier).state = index;
            },
          ),
        ),
      ),
    );
  }
}
