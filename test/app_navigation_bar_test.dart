import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openlib/l10n/app_localizations.dart';
import 'package:openlib/ui/components/app_navigation_bar.dart';

double labelOpacity(WidgetTester tester, String label) {
  var opacity = 1.0;
  tester.element(find.text(label)).visitAncestorElements((element) {
    final widget = element.widget;
    if (widget is Opacity) opacity *= widget.opacity;
    return true;
  });
  return opacity;
}

Future<void> pumpBar(WidgetTester tester, List<int> selected) async {
  var index = 0;
  await tester.pumpWidget(MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: StatefulBuilder(
      builder: (context, update) => Scaffold(
        bottomNavigationBar: AppNavigationBar(
          selectedIndex: index,
          onSelected: (value) => update(() {
            index = value;
            selected.add(value);
          }),
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('keeps the original icon-only inactive tabs and selected label',
      (tester) async {
    await pumpBar(tester, []);
    expect(labelOpacity(tester, 'Home'), 1);
    for (final label in ['Search', 'My Library', 'Settings']) {
      expect(labelOpacity(tester, label), 0,
          reason: 'inactive labels stay hidden in the original design');
    }
  });

  testWidgets('a second tab tap is accepted while the first pill is animating',
      (tester) async {
    final selected = <int>[];
    await pumpBar(tester, selected);
    await tester.tap(find.byIcon(Icons.search).last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));
    await tester.tap(find.byIcon(Icons.settings).last);
    await tester.pump();
    expect(selected, [1, 3],
        reason: 'animation must never lock out a subsequent navigation tap');
    await tester.pump(const Duration(milliseconds: 200));
    expect(labelOpacity(tester, 'Settings'), 1);
    expect(labelOpacity(tester, 'Search'), 0);
    expect(labelOpacity(tester, 'Home'), 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('label reveal progresses smoothly and finishes within 200 ms',
      (tester) async {
    await pumpBar(tester, []);
    await tester.tap(find.byIcon(Icons.search).last);
    await tester.pump();
    final opacities = <double>[];
    for (var frame = 0; frame < 5; frame++) {
      await tester.pump(const Duration(milliseconds: 40));
      opacities.add(labelOpacity(tester, 'Search'));
    }
    expect(opacities.first, greaterThan(0));
    expect(opacities.first, lessThan(1));
    for (var i = 1; i < opacities.length; i++) {
      expect(opacities[i], greaterThanOrEqualTo(opacities[i - 1]));
    }
    expect(opacities.last, 1);
  });
}
