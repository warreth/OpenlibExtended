import 'package:flutter/material.dart';

class ReaderHelpOverlay extends StatelessWidget {
  final VoidCallback onDismiss;
  final bool isDesktop;

  const ReaderHelpOverlay({
    super.key,
    required this.onDismiss,
    required this.isDesktop,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withOpacity(0.85),
      child: InkWell(
        onTap: onDismiss,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Close hint
            Positioned(
              top: 40,
              right: 20,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white, size: 30),
                onPressed: onDismiss,
              ),
            ),

            // Content
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.menu_book, color: Colors.white, size: 60),
                const SizedBox(height: 20),
                Text(
                  "Reader Controls",
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 40),

                // Controls Grid
                Wrap(
                  spacing: 40,
                  runSpacing: 30,
                  alignment: WrapAlignment.center,
                  children: [
                    _buildHelpItem(
                      context,
                      icon: isDesktop ? Icons.keyboard : Icons.touch_app,
                      title: isDesktop ? "Arrow Keys" : "Tap Sides",
                      subtitle: isDesktop
                          ? "Use Left/Right arrows to turn pages"
                          : "Tap left/right edges to turn pages",
                    ),
                    _buildHelpItem(
                      context,
                      icon: Icons.zoom_in,
                      title: "Zoom",
                      subtitle: isDesktop
                          ? "Use provided controls"
                          : "Pinch to zoom (PDF)",
                    ),
                    _buildHelpItem(
                      context,
                      icon: Icons.list,
                      title: "Menu",
                      subtitle: isDesktop
                          ? "Table of Contents via sidebar"
                          : "Tap center or swipe for menu",
                    ),
                  ],
                ),

                const SizedBox(height: 50),
                OutlinedButton(
                  onPressed: onDismiss,
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.white),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 40, vertical: 15),
                  ),
                  child: const Text("Got it!"),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHelpItem(BuildContext context,
      {required IconData icon,
      required String title,
      required String subtitle}) {
    return SizedBox(
      width: 150,
      child: Column(
        children: [
          Icon(icon, color: Colors.white70, size: 40),
          const SizedBox(height: 10),
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withOpacity(0.7),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}
