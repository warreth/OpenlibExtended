// Dart imports:
import 'dart:io' show Platform;

// Flutter imports:
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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

import 'package:openlib/services/files.dart'
    show moveFilesToAndroidInternalStorage;
import 'package:openlib/services/download_manager.dart';
import 'package:openlib/services/download_notification.dart';
import 'package:openlib/state/state.dart'
    show
        selectedIndexProvider,
        themeModeProvider,
        openPdfWithExternalAppProvider,
        openEpubWithExternalAppProvider,
        showManualDownloadButtonProvider,
        userAgentProvider,
        cookieProvider;

void main(List<String> args) async {
  // Handle desktop webview window title bar BEFORE Flutter bindings (required by desktop_webview_window)
  if (runWebViewTitleBarWidget(args)) {
    return;
  }

  WidgetsFlutterBinding.ensureInitialized();

  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  MyLibraryDb dataBase = MyLibraryDb.instance;

  await DownloadManager().initialize();
  
  bool isDarkMode =
      await dataBase.getPreference('darkMode') == 0 ? false : true;
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

  if (Platform.isAndroid) {
    // Android-specific setup for system UI overlay colors
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
        systemNavigationBarColor:
            isDarkMode ? Colors.black : Colors.grey.shade200));
    await moveFilesToAndroidInternalStorage();
  }

  runApp(
    ProviderScope(
      overrides: [
        themeModeProvider.overrideWith(
            (ref) => isDarkMode ? ThemeMode.dark : ThemeMode.light),
        openPdfWithExternalAppProvider
            .overrideWith((ref) => openPdfwithExternalapp),
        openEpubWithExternalAppProvider
            .overrideWith((ref) => openEpubwithExternalapp),
        showManualDownloadButtonProvider
            .overrideWith((ref) => showManualDownloadButton),
        userAgentProvider.overrideWith((ref) => browserUserAgent),
        cookieProvider.overrideWith((ref) => browserCookie),
      ],
      child: const MyApp(),
    ),
  );
}

class MyApp extends ConsumerWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      builder: (BuildContext context, Widget? child) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: const TextScaler.linear(1.0),
          ),
          child: child!,
        );
      },
      debugShowCheckedModeBanner: false,
      title: 'Openlib',
      theme: lightTheme,
      darkTheme: darkTheme,
      themeMode: ref.watch(themeModeProvider),
      home: const MainScreen(),
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
    SettingsPage()
  ];

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
    final hasAskedBefore = await prefs.getPreference('hasAskedNotificationPermission')
        .catchError((_) => 0);
    
    if (hasAskedBefore == 0) {
      // Check current permission status
      final notificationService = DownloadNotificationService();
      final currentStatus = await notificationService.checkNotificationPermission();
      
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
            'Openlib needs notification permission to show download progress in the background. This helps you track your book downloads even when the app is minimized.',
            style: TextStyle(
              fontSize: 13,
              color: Theme.of(context).colorScheme.tertiary.withValues(alpha: 0.78),
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
                  color: Theme.of(context).colorScheme.tertiary.withValues(alpha: 0.67),
                ),
              ),
            ),
            TextButton(
              onPressed: () async {
                Navigator.of(context).pop();
                // Request permission when user clicks Enable
                await DownloadNotificationService().requestNotificationPermission();
                // Mark that we've asked
                await MyLibraryDb.instance.savePreference('hasAskedNotificationPermission', 1);
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

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.surface,
        title: const Text("Openlib"),
        titleTextStyle: Theme.of(context).textTheme.displayLarge,
      ),
      body: _widgetOptions.elementAt(selectedIndex),
      bottomNavigationBar: SafeArea(
        child: GNav(
          backgroundColor: isDarkMode ? Colors.black : Colors.grey.shade200,
          haptic: true,
          tabBorderRadius: 50,
          tabActiveBorder: Border.all(
            color: Theme.of(context).colorScheme.secondary,
          ),
          tabMargin: const EdgeInsets.fromLTRB(13, 6, 13, 2.5),
          curve: Curves.fastLinearToSlowEaseIn,
          duration: const Duration(milliseconds: 25),
          gap: 5,
          color: const Color.fromARGB(255, 255, 255, 255),
          activeColor: const Color.fromARGB(255, 255, 255, 255),
          iconSize: 19, // tab button icon size
          tabBackgroundColor: Theme.of(context).colorScheme.secondary,
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 6.5),
          tabs: [
            GButton(
              icon: Icons.trending_up,
              text: 'Home',
              iconColor: isDarkMode ? Colors.white : Colors.black,
              textStyle: const TextStyle(
                fontWeight: FontWeight.w900,
                color: Colors.white,
                fontSize: 11,
              ),
            ),
            GButton(
              icon: Icons.search,
              text: 'Search',
              iconColor: isDarkMode ? Colors.white : Colors.black,
              textStyle: const TextStyle(
                fontWeight: FontWeight.w900,
                color: Colors.white,
                fontSize: 11,
              ),
            ),
            GButton(
              icon: Icons.collections_bookmark,
              text: 'My Library',
              iconColor: isDarkMode ? Colors.white : Colors.black,
              textStyle: const TextStyle(
                fontWeight: FontWeight.w900,
                color: Colors.white,
                fontSize: 11,
              ),
            ),
            GButton(
              icon: Icons.build,
              text: 'Settings',
              iconColor: isDarkMode ? Colors.white : Colors.black,
              textStyle: const TextStyle(
                fontWeight: FontWeight.w900,
                color: Colors.white,
                fontSize: 11,
              ),
            ),
          ],
          selectedIndex: selectedIndex,
          onTabChange: (index) async {
            ref.read(selectedIndexProvider.notifier).state = index;
          },
        ),
      ),
    );
  }
}
