import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openlib/ui/components/snack_bar_widget.dart';

void main() {
  testWidgets('new messages replace stale messages and the visible message closes', (tester) async {
    late BuildContext pageContext;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: Builder(
      builder: (context) { pageContext = context; return const Text('Page'); },
    ))));
    showSnackBar(context: pageContext, message: 'First error');
    await tester.pump();
    showSnackBar(context: pageContext, message: 'Second error');
    showSnackBar(context: pageContext, message: 'Current error');
    await tester.pumpAndSettle();
    expect(find.text('Current error'), findsOneWidget);
    expect(find.text('First error'), findsNothing);
    expect(find.text('Second error'), findsNothing);
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(find.byType(SnackBar), findsNothing);
    await tester.pump(const Duration(seconds: 5));
    expect(find.byType(SnackBar), findsNothing);
  });
}
