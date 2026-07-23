import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lazy_text_field/lazy_text_field.dart';
import 'package:lazy_text_field_example/main.dart';

void main() {
  testWidgets('demo renders table and enters edit mode', (tester) async {
    await tester.pumpWidget(const LazyTextFieldExampleApp());

    expect(find.text('Task'), findsOneWidget);
    expect(find.text('Owner'), findsOneWidget);
    expect(find.text('Status'), findsOneWidget);
    expect(find.text('Notes'), findsOneWidget);
    expect(find.byIcon(Icons.info_outline), findsWidgets);
    expect(find.byType(LazyTextField), findsWidgets);

    await tester.tap(find.text('Edit full'));
    await tester.pump();

    await tester.tap(find.byType(LazyTextField).first);
    await tester.pump();

    expect(find.byType(TextField), findsOneWidget);
  });
}
