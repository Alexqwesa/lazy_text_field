import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lazy_text_field/lazy_text_field.dart';

bool _hasTextToolbar(WidgetTester tester) {
  return [
    find.byType(AdaptiveTextSelectionToolbar),
    find.byType(TextSelectionToolbar),
    find.text('Copy'),
  ].any((f) => f.evaluate().isNotEmpty);
}

Future<void> _rightClickCenter(WidgetTester tester) async {
  await tester.tapAt(
    tester.getCenter(find.byType(EditableText)),
    buttons: kSecondaryMouseButton,
  );
  await tester.pumpAndSettle();
}

void main() {
  const padding = EdgeInsets.fromLTRB(3, 4, 5, 6);
  const cellWidth = 120.0;
  const textStyle = TextStyle(fontSize: 10, height: 1);

  testWidgets('explicit null contextMenuBuilder disables right click menu', (
    tester,
  ) async {
    final controller = TextEditingController(text: 'hello world');
    final focusNode = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(focusNode.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TextField(
            controller: controller,
            focusNode: focusNode,
            autofocus: true,
            contextMenuBuilder: null,
          ),
        ),
      ),
    );
    await tester.pump();
    await _rightClickCenter(tester);
    expect(_hasTextToolbar(tester), isFalse);
  });

  testWidgets('LazyTextField edit mode shows context menu', (tester) async {
    final controller = TextEditingController(text: 'hello world');
    final focusNode = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(focusNode.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: cellWidth,
            height: 30,
            child: LazyTextField(
              cellId: 'cell-1',
              text: controller.text,
              controller: controller,
              focusNode: focusNode,
              isEditing: true,
              style: textStyle,
              padding: padding,
              decoration: null,
              decorationVisibility: LazyInputDecorationVisibility.never,
              onStartEditing: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    await _rightClickCenter(tester);
    expect(_hasTextToolbar(tester), isTrue);
  });
}
