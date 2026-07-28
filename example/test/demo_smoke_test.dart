import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lazy_text_field/lazy_text_field.dart';
import 'package:lazy_text_field_example/main_live_demo.dart';

void main() {
  testWidgets('demo renders table and enters edit mode', (tester) async {
    await tester.pumpWidget(const LazyTextFieldExampleApp());

    expect(find.text('Task'), findsOneWidget);
    expect(find.text('Owner'), findsOneWidget);
    expect(find.text('Status'), findsOneWidget);
    expect(find.text('Notes'), findsOneWidget);
    expect(find.byIcon(Icons.info_outline), findsWidgets);
    expect(find.byType(LazyTextField), findsWidgets);
    expect(find.text('Edit full'), findsOneWidget);
    expect(find.text('Click'), findsOneWidget);
    expect(find.byType(DropdownMenu<double>), findsOneWidget);
    expect(find.byIcon(Icons.text_fields), findsOneWidget);

    await tester.tap(find.byType(LazyTextField).first);
    await tester.pump();

    expect(
      find.descendant(
        of: find.byType(LazyTextField).first,
        matching: find.byType(TextField),
      ),
      findsOneWidget,
    );
  });
}
