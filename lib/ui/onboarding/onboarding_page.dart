import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlib/main.dart' show MainScreen;
import 'package:openlib/services/database.dart';
import 'package:openlib/services/files.dart';
import 'package:openlib/state/state.dart';
import 'package:openlib/ui/settings_page.dart' show scanAndImportBooks;
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';

class OnboardingPage extends ConsumerStatefulWidget {
  const OnboardingPage({super.key});

  @override
  ConsumerState<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends ConsumerState<OnboardingPage> {
  final PageController _pageController = PageController();
  int _currentPage = 0;
  String _storagePath = '';
  bool _enableAutoUpdate = true;
  bool _enableBetaUpdates = false;
  bool _enableNotifications = false;
  final TextEditingController _donationKeyController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadDefaultStorage();
    _loadDonationKey();
    _loadBetaUpdatesPref();
  }

  Future<void> _loadBetaUpdatesPref() async {
    final db = MyLibraryDb.instance;
    try {
      final value = await db.getPreference('includePrereleaseUpdates');
      if (mounted) {
        setState(() {
          _enableBetaUpdates = value == 1;
        });
      }
    } catch (_) {
      // default false
    }
  }

  Future<void> _loadDonationKey() async {
    final db = MyLibraryDb.instance;
    final key = await db.getPreference('donationKey');
    if (key != null && key.isNotEmpty) {
      if (mounted) {
        setState(() {
          _donationKeyController.text = key;
        });
        ref.read(donationKeyProvider.notifier).state = key;
      }
    }
  }

  Future<void> _loadDefaultStorage() async {
    try {
      final path = await getBookStorageDefaultDirectory;
      if (mounted) {
        setState(() {
          _storagePath = path;
        });
      }
    } catch (e) {
      // ignore
    }
  }

  void _nextPage() {
    if (_currentPage == 1 && _storagePath.isEmpty) {
      // Force storage selection
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text("Please select a storage folder to continue")),
      );
      return;
    }

    // Page count adjusted for platform
    final platformPages = (Platform.isAndroid || Platform.isIOS) ? 7 : 6;

    if (_currentPage < platformPages - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } else {
      _finishOnboarding();
    }
  }

  Future<void> _finishOnboarding() async {
    final db = MyLibraryDb.instance;
    await db.savePreference('onboardingCompleted', 1);
    await db.savePreference('bookStorageDirectory', _storagePath);
    await db.savePreference('enableAutoUpdate', _enableAutoUpdate ? 1 : 0);
    await db.savePreference(
        'includePrereleaseUpdates', _enableBetaUpdates ? 1 : 0);
    await db.savePreference('donationKey', _donationKeyController.text);

    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (context) => const MainScreen()),
      );
    }
  }

  Future<void> _selectStorage() async {
    String? pickedDirectory = await FilePicker.platform.getDirectoryPath();
    if (pickedDirectory != null) {
      // If we are selecting a new path, we should probably check permissions if android
      if (Platform.isAndroid) {
        var status = await Permission.storage.status;
        if (!status.isGranted) {
          await Permission.storage.request();
        }
        if (await Permission.manageExternalStorage.status.isDenied) {
          await Permission.manageExternalStorage.request();
        }
      }

      setState(() {
        _storagePath = pickedDirectory;
      });

      // Scan new directory
      if (mounted) {
        final db = MyLibraryDb.instance;
        await scanAndImportBooks(_storagePath, db, ref);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Only show notification page on mobile
    final showNotificationPage = Platform.isAndroid || Platform.isIOS;
    final displayPages = [
      _buildWelcomePage(),
      _buildStoragePage(),
      _buildUpdatePage(),
      _buildDonationPage(),
      _buildSponsorPage(),
      if (showNotificationPage) _buildNotificationPage(),
      _buildThemePage(),
    ];

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: PageView(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(),
                onPageChanged: (page) {
                  setState(() {
                    _currentPage = page;
                  });
                },
                children: displayPages,
              ),
            ),
            _buildBottomBar(displayPages.length),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomBar(int pageCount) {
    return Container(
      padding: const EdgeInsets.all(20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Dots indicator
          Row(
            children: List.generate(pageCount, (index) {
              return Container(
                margin: const EdgeInsets.symmetric(horizontal: 4),
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _currentPage == index
                      ? Theme.of(context).colorScheme.secondary
                      : Theme.of(context)
                          .colorScheme
                          .secondary
                          .withOpacity(0.2),
                ),
              );
            }),
          ),
          ElevatedButton(
            onPressed: _nextPage,
            child: Text(_currentPage == pageCount - 1 ? "Get Started" : "Next"),
          ),
        ],
      ),
    );
  }

  Widget _buildWelcomePage() {
    return Padding(
      padding: const EdgeInsets.all(32.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.library_books,
              size: 80, color: Theme.of(context).colorScheme.secondary),
          const SizedBox(height: 30),
          Text(
            "Welcome to OpenlibExtended",
            style: Theme.of(context).textTheme.displayLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          Text(
            "Your personal gateway to a world of knowledge. Let's get you set up.",
            style: Theme.of(context).textTheme.bodyLarge,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildStoragePage() {
    return Padding(
      padding: const EdgeInsets.all(32.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.folder_open, size: 60),
          const SizedBox(height: 20),
          Text("Where should we store your books?",
              style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 30),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
                _storagePath.isEmpty ? "No path selected" : _storagePath,
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: _selectStorage,
            icon: const Icon(Icons.edit),
            label: const Text("Select Folder"),
            style: ElevatedButton.styleFrom(
              // Ensure visible colors regardless of theme defaults
              backgroundColor: Theme.of(context).colorScheme.secondary,
              foregroundColor: Colors.white,
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            "We'll only look for PDF/EPUB files in this folder. No recursive scanning of subfolders.",
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ],
      ),
    );
  }

  Widget _buildUpdatePage() {
    return Padding(
      padding: const EdgeInsets.all(32.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.system_update, size: 60),
          const SizedBox(height: 20),
          Text("Automatic Updates",
              style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 30),
          Container(
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.withOpacity(0.3)),
            ),
            child: Column(
              children: [
                SwitchListTile(
                  title: const Text("Enable Auto-Updates"),
                  subtitle: const Text(
                      "Not recommended if you installed via F-Droid (F-Droid handles updates)."),
                  activeThumbColor: Theme.of(context).colorScheme.secondary,
                  activeTrackColor:
                      Theme.of(context).colorScheme.secondary.withOpacity(0.5),
                  inactiveThumbColor: Colors.grey,
                  inactiveTrackColor: Colors.grey.withOpacity(0.5),
                  value: _enableAutoUpdate,
                  onChanged: (val) async {
                    setState(() {
                      _enableAutoUpdate = val;
                    });
                    if (val && Platform.isAndroid) {
                      // Request install permission if they enable it
                      final status =
                          await Permission.requestInstallPackages.status;
                      if (!status.isGranted) {
                        await Permission.requestInstallPackages.request();
                      }
                    }
                  },
                ),
                Divider(),
                SwitchListTile(
                  title: const Text("Enable Beta Updates"),
                  subtitle: const Text(
                      "Get pre-release versions (beta updates) when available."),
                  activeThumbColor: Colors.orange,
                  activeTrackColor: Colors.orangeAccent,
                  inactiveThumbColor: Colors.grey,
                  inactiveTrackColor: Colors.grey.withOpacity(0.5),
                  value: _enableBetaUpdates,
                  onChanged: (val) async {
                    setState(() {
                      _enableBetaUpdates = val;
                    });
                    final db = MyLibraryDb.instance;
                    await db.savePreference(
                        'includePrereleaseUpdates', val ? 1 : 0);
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDonationPage() {
    return Padding(
      padding: const EdgeInsets.all(32.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.favorite, size: 60, color: Colors.red),
          const SizedBox(height: 20),
          Text("Support Anna's Archive",
              style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 20),
          const Text(
            "Donating to Anna's Archive provides faster downloads and helps them keep the service running for everyone. You can enter your secret key below.",
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _donationKeyController,
            decoration: const InputDecoration(
              labelText: "Anna's Archive Secret Key",
              border: OutlineInputBorder(),
            ),
            onChanged: (value) {
              ref.read(donationKeyProvider.notifier).state = value;
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSponsorPage() {
    return Padding(
      padding: const EdgeInsets.all(32.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.code, size: 60),
          const SizedBox(height: 20),
          Text("Support This App",
              style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 30),
          const Text(
            "If you enjoy this app, consider supporting its development. It helps me dedicate more time to making it better!",
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: () =>
                launchUrl(Uri.parse('https://github.com/sponsors/warreth')),
            icon: const Icon(Icons.open_in_new),
            label: const Text("Sponsor on GitHub"),
          ),
        ],
      ),
    );
  }

  Widget _buildNotificationPage() {
    return Padding(
      padding: const EdgeInsets.all(32.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.notifications, size: 60),
          const SizedBox(height: 20),
          Text("Stay Updated",
              style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 30),
          SwitchListTile(
            title: const Text("Enable Notifications"),
            subtitle: const Text("Get notified when downloads complete."),
            value: _enableNotifications,
            onChanged: (val) async {
              setState(() {
                _enableNotifications = val;
              });
              if (val) {
                await Permission.notification.request();
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildThemePage() {
    final mode = ref.watch(themeModeProvider);
    return Padding(
      padding: const EdgeInsets.all(32.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.palette, size: 60),
          const SizedBox(height: 20),
          Text("Choose a Theme",
              style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 30),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _ThemeCard(
                  title: "Light",
                  icon: Icons.light_mode,
                  selected: mode == ThemeMode.light,
                  onTap: () {
                    ref.read(themeModeProvider.notifier).state =
                        ThemeMode.light;
                    MyLibraryDb.instance.savePreference('darkMode', 0);
                  }),
              const SizedBox(width: 20),
              _ThemeCard(
                  title: "Dark",
                  icon: Icons.dark_mode,
                  selected: mode == ThemeMode.dark,
                  onTap: () {
                    ref.read(themeModeProvider.notifier).state = ThemeMode.dark;
                    MyLibraryDb.instance.savePreference('darkMode', 1);
                  }),
            ],
          ),
        ],
      ),
    );
  }
}

class _ThemeCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _ThemeCard({
    required this.title,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 100,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: selected
              ? Theme.of(context).colorScheme.secondary.withOpacity(0.1)
              : null,
          border: Border.all(
            color: selected
                ? Theme.of(context).colorScheme.secondary
                : Colors.grey,
            width: selected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Icon(icon,
                size: 30,
                color:
                    selected ? Theme.of(context).colorScheme.secondary : null),
            const SizedBox(height: 8),
            Text(title,
                style: TextStyle(
                    fontWeight:
                        selected ? FontWeight.bold : FontWeight.normal)),
          ],
        ),
      ),
    );
  }
}
