import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lazy_text_field/lazy_text_field.dart';

const _style = TextStyle(
  fontFamily: 'Ahem',
  fontSize: 10,
  height: 1,
  letterSpacing: 0,
);

const _decoration = InputDecoration(
  border: InputBorder.none,
  isCollapsed: true,
  contentPadding: EdgeInsets.all(4),
);

Widget _app(Widget child) => MaterialApp(
  home: Scaffold(
    body: Align(alignment: Alignment.topLeft, child: child),
  ),
);

Future<void> _open(WidgetTester tester, String id) async {
  await tester.tap(find.byKey(LazyTextFieldKeys.staticSurface(id)));
  await tester.pump();
  await tester.pump();
}

Future<void> _type(WidgetTester tester, String text) =>
    tester.enterText(find.byType(EditableText), text);

Future<void> _submit(WidgetTester tester) async {
  await tester.sendKeyEvent(LogicalKeyboardKey.enter);
  await tester.pump();
}

Future<void> _escape(WidgetTester tester) async {
  await tester.sendKeyEvent(LogicalKeyboardKey.escape);
  await tester.pump();
  await tester.pump();
}

String _editorText(WidgetTester tester) =>
    tester.widget<EditableText>(find.byType(EditableText)).controller.text;

void main() {
  late LazyTextFieldEditController controller;
  late List<String> saves;
  late List<String> saved;
  late FutureOr<bool> Function(String value) onSaveA;

  setUp(() {
    saves = [];
    saved = [];
  });

  Future<void> pumpCells(WidgetTester tester) {
    controller = LazyTextFieldEditController();
    addTearDown(controller.dispose);
    return tester.pumpWidget(
      _app(
        LazyTextFieldControllerScope(
          controller: controller,
          child: Column(
            children: [
              for (final id in ['a', 'b'])
                SizedBox(
                  width: 200,
                  child: ScopedLazyTextField(
                    cellId: id,
                    text: 'old-$id',
                    singleLine: true,
                    style: _style,
                    decoration: _decoration,
                    onSave: id == 'a'
                        ? (value) {
                            saves.add(value);
                            return onSaveA(value);
                          }
                        : (_) => true,
                    onSaved: id == 'a' ? saved.add : null,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  testWidgets('a save that finishes late does not close a reopened editor', (
    tester,
  ) async {
    final first = Completer<bool>();
    onSaveA = (value) => value == 'first' ? first.future : true;
    await pumpCells(tester);
    await _open(tester, 'a');
    await _type(tester, 'first');
    await _submit(tester);
    await _open(tester, 'b');
    await _open(tester, 'a');
    await _type(tester, 'second');

    first.complete(true);
    await tester.pump();
    expect(controller.isEditing('a'), isTrue);
    expect(_editorText(tester), 'second');
    expect(saved, ['first']);

    await _submit(tester);
    await tester.pump();
    expect(saves, ['first', 'second']);
    expect(saved, ['first', 'second']);
    expect(controller.isEditing('a'), isFalse);
  });

  testWidgets('typing after a submit keeps the editor open with the newer '
      'text', (tester) async {
    final first = Completer<bool>();
    onSaveA = (value) => value == 'first' ? first.future : true;
    await pumpCells(tester);
    await _open(tester, 'a');
    await _type(tester, 'first');
    await _submit(tester);
    await _type(tester, 'second');

    first.complete(true);
    await tester.pump();
    await tester.pump();
    expect(saved, ['first']);
    expect(controller.isEditing('a'), isTrue);
    expect(_editorText(tester), 'second');

    await _submit(tester);
    await tester.pump();
    expect(saves, ['first', 'second']);
    expect(saved, ['first', 'second']);
    expect(controller.isEditing('a'), isFalse);
  });

  testWidgets('a second submit while the first saves runs after it', (
    tester,
  ) async {
    final first = Completer<bool>();
    onSaveA = (value) => value == 'first' ? first.future : true;
    await pumpCells(tester);
    await _open(tester, 'a');
    await _type(tester, 'first');
    await _submit(tester);
    await _type(tester, 'second');
    await _submit(tester);
    await tester.pump();
    expect(saves, ['first']);

    first.complete(true);
    await tester.pump();
    await tester.pump();
    expect(saves, ['first', 'second']);
    expect(saved, ['first', 'second']);
    expect(controller.isEditing('a'), isFalse);
  });

  testWidgets('a submit after Escape waits for the save still running', (
    tester,
  ) async {
    final first = Completer<bool>();
    onSaveA = (value) => value == 'first' ? first.future : true;
    await pumpCells(tester);
    await _open(tester, 'a');
    await _type(tester, 'first');
    await _submit(tester);
    await _escape(tester);
    await _open(tester, 'a');
    await _type(tester, 'second');
    await _submit(tester);
    await tester.pump();

    // "second" is not sent while "first" may still land after it.
    expect(saves, ['first']);
    expect(controller.isEditing('a'), isTrue);

    first.complete(true);
    await tester.pump();
    await tester.pump();
    expect(saves, ['first', 'second']);
    // Escape canceled the first edit, so only the second reports onSaved.
    expect(saved, ['second']);
    expect(controller.isEditing('a'), isFalse);
  });

  testWidgets('an older save that fails does not block the newer one', (
    tester,
  ) async {
    final first = Completer<bool>();
    onSaveA = (value) => value == 'first' ? first.future : true;
    await pumpCells(tester);
    await _open(tester, 'a');
    await _type(tester, 'first');
    await _submit(tester);
    await _type(tester, 'second');
    await _submit(tester);

    first.complete(false);
    await tester.pump();
    await tester.pump();
    expect(saves, ['first', 'second']);
    expect(saved, ['second']);
    expect(controller.isEditing('a'), isFalse);
  });

  testWidgets('an onSave that throws is reported and does not block saves', (
    tester,
  ) async {
    var fail = true;
    onSaveA = (_) => fail ? throw StateError('boom') : true;
    await pumpCells(tester);
    await _open(tester, 'a');
    await _type(tester, 'x');
    await _submit(tester);
    await tester.pump();

    expect(tester.takeException(), isStateError);
    expect(controller.isEditing('a'), isTrue);

    fail = false;
    await _submit(tester);
    await tester.pump();
    expect(saves, ['x', 'x']);
    expect(saved, ['x']);
    expect(controller.isEditing('a'), isFalse);
  });

  testWidgets('a rejected save keeps the editor open', (tester) async {
    onSaveA = (_) => false;
    await pumpCells(tester);
    await _open(tester, 'a');
    await _type(tester, 'x');
    await _submit(tester);
    await tester.pump();
    expect(saves, ['x']);
    expect(saved, isEmpty);
    expect(controller.isEditing('a'), isTrue);
    expect(_editorText(tester), 'x');
  });

  testWidgets('recycling an editing cell for a new cellId does not notify '
      'the scope during build', (tester) async {
    controller = LazyTextFieldEditController();
    addTearDown(controller.dispose);
    final cellId = ValueNotifier('a');
    addTearDown(cellId.dispose);
    await tester.pumpWidget(
      _app(
        LazyTextFieldControllerScope(
          controller: controller,
          child: ValueListenableBuilder(
            valueListenable: cellId,
            builder: (context, id, _) => SizedBox(
              width: 200,
              child: ScopedLazyTextField(
                cellId: id,
                text: 'old-$id',
                singleLine: true,
                style: _style,
                decoration: _decoration,
                onSave: (_) => true,
              ),
            ),
          ),
        ),
      ),
    );
    await _open(tester, 'a');
    await _type(tester, 'typed');
    cellId.value = 'b';
    await tester.pump();
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(controller.isEditing('a'), isFalse);
    expect(find.byType(EditableText), findsNothing);
  });
}
