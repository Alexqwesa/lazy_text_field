import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lazy_text_field/lazy_text_field.dart';

void main() {
  const style = TextStyle(
    fontFamily: 'Ahem',
    fontSize: 10,
    height: 1,
    letterSpacing: 0,
  );

  group('P1 decoration / singleLine', () {
    testWidgets(
      'tapping suffixIcon while editing does not save via onTapOutside',
      (tester) async {
        final saved = <String>[];
        var suffixTaps = 0;

        await tester.pumpWidget(
          _InputApp(
            child: SizedBox(
              width: 240,
              child: StatefulLazyTextField(
                cellId: 'decorated',
                text: 'editing',
                style: style,
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    key: const ValueKey('suffix-action'),
                    icon: const Icon(Icons.clear, size: 16),
                    onPressed: () => suffixTaps++,
                  ),
                  suffixIconConstraints: const BoxConstraints.tightFor(
                    width: 40,
                    height: 40,
                  ),
                ),
                onSave: (value) {
                  saved.add(value);
                  return true;
                },
                onSaved: saved.add,
              ),
            ),
          ),
        );

        await tester.tap(
          find.byKey(LazyTextFieldKeys.staticSurface('decorated')),
        );
        await tester.pump();
        expect(find.byType(EditableText), findsOneWidget);

        await tester.tap(find.byKey(const ValueKey('suffix-action')));
        await tester.pump();

        expect(suffixTaps, 1);
        expect(find.byType(EditableText), findsOneWidget);
        expect(saved, isEmpty);
      },
    );

    testWidgets(
      'tapping prefixIcon while editing does not save via onTapOutside',
      (tester) async {
        var prefixTaps = 0;
        final saved = <String>[];

        await tester.pumpWidget(
          _InputApp(
            child: SizedBox(
              width: 240,
              child: StatefulLazyTextField(
                cellId: 'prefix',
                text: 'editing',
                style: style,
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  prefixIcon: IconButton(
                    key: const ValueKey('prefix-action'),
                    icon: const Icon(Icons.search, size: 16),
                    onPressed: () => prefixTaps++,
                  ),
                  prefixIconConstraints: const BoxConstraints.tightFor(
                    width: 40,
                    height: 40,
                  ),
                ),
                onSave: (_) {
                  saved.add('saved');
                  return true;
                },
              ),
            ),
          ),
        );

        await tester.tap(find.byKey(LazyTextFieldKeys.staticSurface('prefix')));
        await tester.pump();
        await tester.tap(find.byKey(const ValueKey('prefix-action')));
        await tester.pump();

        expect(prefixTaps, 1);
        expect(find.byType(EditableText), findsOneWidget);
        expect(saved, isEmpty);
      },
    );

    testWidgets(
      'singleLine rejects pasted newlines',
      (tester) async {
        final controller = TextEditingController(text: 'seed');
        final focusNode = FocusNode();
        addTearDown(controller.dispose);
        addTearDown(focusNode.dispose);

        await tester.pumpWidget(
          _InputApp(
            child: SizedBox(
              width: 200,
              child: LazyTextField(
                cellId: 'single',
                text: controller.text,
                isEditing: true,
                controller: controller,
                focusNode: focusNode,
                singleLine: true,
                style: style,
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  isCollapsed: true,
                  contentPadding: EdgeInsets.all(4),
                ),
                onStartEditing: () {},
              ),
            ),
          ),
        );
        await tester.pump();

        await tester.showKeyboard(find.byType(EditableText));
        tester.testTextInput.updateEditingValue(
          const TextEditingValue(
            text: 'line1\nline2',
            selection: TextSelection.collapsed(offset: 11),
          ),
        );
        await tester.pump();

        expect(controller.text, isNot(contains('\n')));
        expect(controller.text, 'line1line2');
      },
    );
  });

  group('P2 caret / parent rebuild / overflow a11y', () {
    testWidgets(
      'tapPosition places caret under right-aligned text',
      (tester) async {
        await _expectTapPositionForAlignedText(
          tester,
          textAlign: TextAlign.end,
          targetOffset: 3,
        );
      },
    );

    testWidgets(
      'tapPosition places caret under centered text',
      (tester) async {
        await _expectTapPositionForAlignedText(
          tester,
          textAlign: TextAlign.center,
          targetOffset: 6,
        );
      },
    );

    testWidgets(
      'parent text style and text scale stay consistent while editing',
      (tester) async {
        final controller = TextEditingController(text: 'scale-me');
        final focusNode = FocusNode();
        addTearDown(controller.dispose);
        addTearDown(focusNode.dispose);
        var scale = 1.0;
        var fontSize = 10.0;

        Future<void> pumpTree() {
          return tester.pumpWidget(
            _InputApp(
              child: MediaQuery(
                data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                child: SizedBox(
                  width: 200,
                  child: LazyTextField(
                    cellId: 'theme',
                    text: controller.text,
                    isEditing: true,
                    controller: controller,
                    focusNode: focusNode,
                    style: TextStyle(
                      fontFamily: 'Ahem',
                      fontSize: fontSize,
                      height: 1,
                    ),
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      isCollapsed: true,
                      contentPadding: EdgeInsets.all(4),
                    ),
                    onStartEditing: () {},
                  ),
                ),
              ),
            ),
          );
        }

        await pumpTree();
        await tester.pump();
        final before = tester.getSize(
          find.byKey(LazyTextFieldKeys.textViewport('theme')),
        );

        scale = 1.5;
        fontSize = 12;
        await pumpTree();
        await tester.pump();

        final editable = tester.widget<EditableText>(find.byType(EditableText));
        expect(editable.style.fontSize, 12);
        expect(controller.text, 'scale-me');
        expect(
          tester
              .getSize(find.byKey(LazyTextFieldKeys.textViewport('theme')))
              .height,
          greaterThanOrEqualTo(before.height),
        );
      },
    );

    testWidgets(
      'overflow marker sits on the end edge in RTL and exposes semantics',
      (tester) async {
        var toggles = 0;
        final handle = tester.ensureSemantics();
        try {
          await tester.pumpWidget(
            _InputApp(
              textDirection: TextDirection.rtl,
              child: SizedBox(
                width: 80,
                child: LazyTextField(
                  cellId: 'rtl',
                  text: 'line 1\nline 2\nline 3\nline 4',
                  isEditing: false,
                  style: style,
                  maxHeight: 30,
                  decoration: null,
                  onReadOnlyOverflowToggle: () => toggles++,
                  onStartEditing: () {},
                ),
              ),
            ),
          );

          final marker = find.byKey(
            const ValueKey('cell-overflow-corner-marker'),
          );
          expect(marker, findsOneWidget);

          final viewport = tester.getRect(
            find.byKey(LazyTextFieldKeys.textViewport('rtl')),
          );
          final markerRect = tester.getRect(marker);
          expect(markerRect.left, closeTo(viewport.left, 0.5));
          expect(markerRect.right, lessThan(viewport.center.dx));

          final semanticsFinder = find.bySemanticsLabel('Expand overflow');
          expect(semanticsFinder, findsOneWidget);
          final semantics = tester.getSemantics(semanticsFinder);
          expect(semantics.flagsCollection.isButton, isTrue);
          expect(
            semantics.getSemanticsData().hasAction(SemanticsAction.tap),
            isTrue,
          );

          // Drive the semantic action through the marker hit target.
          await tester.tap(marker);
          await tester.pump();
          expect(toggles, 1);
        } finally {
          handle.dispose();
        }
      },
    );
  });
}

/// Taps the visual glyph at [targetOffset] for [textAlign] and expects
/// [LazyTextFieldStartEditDetails.textOffset] (and the applied caret) to match.
Future<void> _expectTapPositionForAlignedText(
  WidgetTester tester, {
  required TextAlign textAlign,
  required int targetOffset,
}) async {
  const text = 'abcdefghij';
  const cellId = 'align';
  const cursorWidth = 2.0;
  const fieldWidth = 160.0;
  final style = const TextStyle(
    fontFamily: 'Ahem',
    fontSize: 10,
    height: 1,
    letterSpacing: 0,
  );

  late LazyTextFieldStartEditDetails details;
  var editing = false;
  final controller = TextEditingController(text: text);
  final focusNode = FocusNode();
  addTearDown(controller.dispose);
  addTearDown(focusNode.dispose);

  await tester.pumpWidget(
    _InputApp(
      child: SizedBox(
        width: fieldWidth,
        child: StatefulBuilder(
          builder: (context, setState) {
            return LazyTextField(
              cellId: cellId,
              text: text,
              isEditing: editing,
              controller: editing ? controller : null,
              focusNode: editing ? focusNode : null,
              style: style,
              textAlign: textAlign,
              cursorWidth: cursorWidth,
              decoration: const InputDecoration(
                border: InputBorder.none,
                isCollapsed: true,
                contentPadding: EdgeInsets.zero,
              ),
              onStartEditingWithDetails: (value) {
                details = value;
                controller.selection = TextSelection.collapsed(
                  offset: value.textOffset,
                );
                setState(() => editing = true);
              },
              onStartEditing: () {},
            );
          },
        ),
      ),
    ),
  );

  final viewport = tester.getRect(
    find.byKey(LazyTextFieldKeys.textViewport(cellId)),
  );
  final textLayoutWidth = viewport.width - (cursorWidth + 1);
  final painter = TextPainter(
    text: TextSpan(text: text, style: style),
    textAlign: textAlign,
    textDirection: TextDirection.ltr,
    textScaler: TextScaler.noScaling,
    strutStyle: StrutStyle.fromTextStyle(style),
  )..layout(maxWidth: textLayoutWidth);

  final boxes = painter.getBoxesForSelection(
    TextSelection(baseOffset: targetOffset, extentOffset: targetOffset + 1),
  );
  expect(
    boxes,
    isNotEmpty,
    reason: 'expected a glyph box for offset $targetOffset under $textAlign',
  );
  final box = boxes.first;
  // Prefer the leading half of the glyph so getPositionForOffset does not
  // advance to the trailing caret (offset + 1).
  final tapAt = viewport.topLeft + Offset(box.left + 1, box.top + 1);

  await tester.tapAt(tapAt);
  await tester.pump();
  await tester.pump();

  expect(editing, isTrue);
  expect(
    details.textOffset,
    targetOffset,
    reason: 'tapPosition under $textAlign should hit glyph $targetOffset',
  );
  expect(controller.selection.baseOffset, targetOffset);
}

class _InputApp extends StatelessWidget {
  const _InputApp({
    required this.child,
    this.textDirection = TextDirection.ltr,
  });

  final Widget child;
  final TextDirection textDirection;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Directionality(
        textDirection: textDirection,
        child: Scaffold(
          body: Align(alignment: Alignment.topLeft, child: child),
        ),
      ),
    );
  }
}
