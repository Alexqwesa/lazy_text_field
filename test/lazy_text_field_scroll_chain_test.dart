import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lazy_text_field/lazy_text_field.dart';

const _tallText =
    'line 1\nline 2\nline 3\nline 4\nline 5\nline 6\nline 7\nline 8';

void main() {
  late ScrollController page;

  /// An editing field with a 20 px viewport inside a scrolling page.
  Future<void> pumpEditor(
    WidgetTester tester, {
    required bool chain,
    String text = _tallText,
  }) async {
    page = ScrollController();
    addTearDown(page.dispose);
    final controller = TextEditingController(text: text);
    addTearDown(controller.dispose);
    final focusNode = FocusNode();
    addTearDown(focusNode.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 300,
            child: ListView(
              controller: page,
              children: [
                const SizedBox(height: 50),
                LazyTextField(
                  cellId: 'cell',
                  text: text,
                  isEditing: true,
                  controller: controller,
                  focusNode: focusNode,
                  style: const TextStyle(fontSize: 10, height: 1),
                  decoration: const InputDecoration(
                    isCollapsed: true,
                    border: InputBorder.none,
                  ),
                  maxHeight: 20,
                  chainEditorScroll: chain,
                  onStartEditing: () {},
                ),
                const SizedBox(height: 2000),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  Future<void> wheel(WidgetTester tester, double dy) async {
    final pointer = TestPointer(1, PointerDeviceKind.mouse);
    final at = tester.getCenter(find.byKey(LazyTextFieldKeys.root('cell')));
    await tester.sendEventToBinding(pointer.hover(at));
    await tester.sendEventToBinding(pointer.scroll(Offset(0, dy)));
    await tester.pump();
  }

  ScrollPosition editorScroll(WidgetTester tester) => tester
      .state<ScrollableState>(
        find
            .descendant(
              of: find.byType(EditableText),
              matching: find.byType(Scrollable),
            )
            .first,
      )
      .position;

  testWidgets('by default the page scrolls once the editor is at its end', (
    tester,
  ) async {
    await pumpEditor(tester, chain: true);

    await wheel(tester, 500);
    expect(editorScroll(tester).pixels, editorScroll(tester).maxScrollExtent);
    expect(page.offset, 0);

    await wheel(tester, 100);
    expect(page.offset, greaterThan(0));
  });

  testWidgets('chainEditorScroll: false keeps the page still', (tester) async {
    await pumpEditor(tester, chain: false);

    await wheel(tester, 500);
    await wheel(tester, 100);
    expect(editorScroll(tester).pixels, editorScroll(tester).maxScrollExtent);
    expect(page.offset, 0);

    // Scrolling back up past the top does not move the page either.
    await wheel(tester, -1000);
    await wheel(tester, -100);
    expect(editorScroll(tester).pixels, 0);
    expect(page.offset, 0);
  });

  testWidgets('chainEditorScroll: false lets the page scroll over text that '
      'fits', (tester) async {
    await pumpEditor(tester, chain: false, text: 'short');

    await wheel(tester, 100);
    expect(page.offset, greaterThan(0));
  });
}
