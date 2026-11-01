import 'package:flutter/material.dart';
import 'package:google_nav_bar/google_nav_bar.dart';
import 'package:openlib/l10n/app_localizations.dart';

class AppNavigationBar extends StatelessWidget {
  const AppNavigationBar(
      {super.key, required this.selectedIndex, required this.onSelected});

  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final l10n = AppLocalizations.of(context);
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 180);
    final icons = [
      Icons.trending_up,
      Icons.search,
      Icons.collections_bookmark,
      Icons.settings,
    ];
    final labels = [
      l10n.navHome,
      l10n.navSearch,
      l10n.navMyLibrary,
      l10n.navSettings,
    ];

    return SafeArea(
      child: RepaintBoundary(
        child: ColoredBox(
          color: isDark ? const Color(0xFF141414) : Colors.white,
          // Keep GNav's original pills and hidden labels. Its container blocks
          // every tap until an animation ends; direct GButtons stay responsive.
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (var i = 0; i < icons.length; i++)
                GButton(
                  active: selectedIndex == i,
                  icon: icons[i],
                  text: labels[i],
                  semanticLabel: labels[i],
                  haptic: true,
                  debug: false,
                  borderRadius: BorderRadius.circular(50),
                  activeBorder: Border.all(color: theme.colorScheme.secondary),
                  margin: const EdgeInsets.fromLTRB(13, 12, 13, 12),
                  // A symmetric curve keeps expand/collapse motion consistent
                  // when GButton flips its curve, including mid-animation taps.
                  curve: Curves.easeInOutCubic,
                  duration: duration,
                  gap: 8,
                  iconColor: isDark ? Colors.white : Colors.black,
                  iconActiveColor: Colors.white,
                  textColor: Colors.white,
                  iconSize: 20,
                  backgroundColor: theme.colorScheme.secondary,
                  rippleColor: Colors.transparent,
                  hoverColor: Colors.transparent,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  onPressed: () => onSelected(i),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
