// The scrolling-physics fix: the app's MaterialApp must hand every
// scrollable momentum-based physics, so lists on Android 15 no longer
// stop on a dime when the finger lifts.

// Flutter imports:
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Project imports:
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlib/main.dart' show MyApp;
import 'package:openlib/ui/onboarding/onboarding_page.dart';

void main() {
  testWidgets('the app hands scrollables momentum-based physics',
      (tester) async {
    await tester.pumpWidget(const ProviderScope(
      child: MyApp(onboardingCompleted: false),
    ));
    // Let the onboarding shell settle into a frame with a context we
    // can read - it lives under the MaterialApp, whose scrollBehavior
    // is what we are verifying.
    await tester.pump();

    final context = tester.element(find.byType(OnboardingPage).first);
    final captured = ScrollConfiguration.of(context).getScrollPhysics(context);

    // Momentum-based deceleration instead of the default
    // ClampingScrollPhysics that halts immediately at finger-lift.
    expect(captured, isA<BouncingScrollPhysics>());

    // The chain keeps an always-scrollable root, so short lists stay
    // draggable (pull-to-refresh on short result lists).
    var physics = captured;
    var alwaysScrollable = false;
    while (physics.parent != null) {
      if (physics is AlwaysScrollableScrollPhysics) alwaysScrollable = true;
      physics = physics.parent!;
    }
    if (physics is AlwaysScrollableScrollPhysics) alwaysScrollable = true;
    expect(alwaysScrollable, isTrue);
  });
}
