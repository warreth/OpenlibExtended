// The book info page must expose its text for copying: SelectionArea wraps
// the scroll view so title, author, info and description are selectable,
// while buttons inside the child slot keep working.

// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:flutter_test/flutter_test.dart';

// Project imports:
import 'package:openlib/ui/components/book_info_widget.dart';

class _FakeBookData {
  final String md5 = '7b2e2c05501894b229e309e39ec0d05d';
  final String title = 'Structure of Scientific Revolutions';
  final String author = 'Thomas S. Kuhn';
  final String publisher = 'University of Chicago Press';
  final String info = 'English [en], EPUB, 1.5MB, 2012';
  final String thumbnail = '';
  final String description =
      'A book about paradigm shifts in science and how they reshape whole fields.';
}

void main() {
  testWidgets('book info text is selectable for copying', (tester) async {
    final data = _FakeBookData();

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: BookInfoWidget(
          data: data,
          child: ElevatedButton(
            onPressed: () {},
            child: const Text('Add To My Library'),
          ),
        ),
      ),
    ));

    await tester.pump();

    // The selectable region wraps the text content.
    expect(find.byType(SelectionArea), findsOneWidget);

    // Title, author, metadata and description all render inside it.
    expect(find.text(data.title), findsOneWidget);
    expect(find.text(data.author), findsOneWidget);
    expect(find.text(data.info), findsOneWidget);
    expect(find.text(data.description), findsOneWidget);

    // The button in the child slot still exists and is reachable.
    expect(find.byType(ElevatedButton), findsOneWidget);
  });
}
