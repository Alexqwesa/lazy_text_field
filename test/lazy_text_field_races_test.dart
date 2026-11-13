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

Future<void> _tapCell(WidgetTester tester, String id) async {
  await tester.tap(find.byKey(LazyTextFieldKeys.staticSurface(id)));
  await tester.pump();
  await tester.pump();
}

Future<void> _pressSave(WidgetTester tester) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pump();
}

String _editorText(WidgetTester tester) =>
    tester.widget<EditableText>(find.byType(EditableText)).controller.text;

void main() {
  group('asynchronous edit permission', () {
    late LazyTextFieldEditController controller;
    late Completer<bool> permission;

    Future<void> pumpCells(WidgetTester tester) {
      controller = LazyTextFieldEditController();
      addTearDown(controller.dispose);
      permission = Completer<bool>();
      Widget cell(String id, {FutureOr<bool> Function()? ask}) => SizedBox(
        width: 200,
        child: ScopedLazyTextField(
          cellId: id,
          text: 'old-$id',
          style: _style,
          decoration: _decoration,
          onWillStartEditing: ask,
          onSave: (_) => true,
        ),
      );
      return tester.pumpWidget(
        _app(
          LazyTextFieldScope(
            controller: controller,
            child: Column(
              children: [
                cell('a', ask: () => permission.future),
                cell('b'),
              ],
            ),
          ),
        ),
      );
    }

    testWidgets('a cell clicked later wins over a pending permission', (
      tester,
    ) async {
      await pumpCells(tester);
      await _tapCell(tester, 'a');
      expect(controller.activeIds, isEmpty);

      await _tapCell(tester, 'b');
      expect(controller.activeIds, ['b']);

      permission.complete(true);
      await tester.pump();
      await tester.pump();
      expect(controller.activeIds, ['b']);
      expect(controller.focusNodeFor('b')!.hasFocus, isTrue);
    });

    testWidgets('startEditing from code wins over a pending permission', (
      tester,
    ) async {
      await pumpCells(tester);
      await _tapCell(tester, 'a');
      controller.startEditing(cellId: 'b', initialValue: 'old-b');
      await tester.pump();

      permission.complete(true);
      await tester.pump();
      await tester.pump();
      expect(controller.activeIds, ['b']);
    });

    testWidgets('a permission granted with no click since opens the cell', (
      tester,
    ) async {
      await pumpCells(tester);
      await _tapCell(tester, 'a');
      permission.complete(true);
      await tester.pump();
      await tester.pump();
      expect(controller.activeIds, ['a']);
    });
  });

  group('StatefulLazyTextField save', () {
    late List<Completer<bool>> requests;
    late List<String> saves;
    late List<String> saved;

    setUp(() {
      requests = [];
      saves = [];
      saved = [];
    });

    Future<void> pumpField(
      WidgetTester tester, {
      FutureOr<bool> Function(String value)? onSave,
    }) => tester.pumpWidget(
      _app(
        SizedBox(
          width: 200,
          child: StatefulLazyTextField(
            cellId: 'cell',
            text: 'old',
            style: _style,
            decoration: _decoration,
            onSave:
                onSave ??
                (value) {
                  saves.add(value);
                  final request = Completer<bool>();
                  requests.add(request);
                  return request.future;
                },
            onSaved: saved.add,
          ),
        ),
      ),
    );

    testWidgets('text typed during a save stays in the editor', (tester) async {
      await pumpField(tester);
      await _tapCell(tester, 'cell');
      await tester.enterText(find.byType(EditableText), 'one');
      await _pressSave(tester);
      await tester.enterText(find.byType(EditableText), 'one and two');
      await tester.pump();

      requests.single.complete(true);
      await tester.pump();
      await tester.pump();

      expect(saved, ['one']);
      expect(find.byType(EditableText), findsOneWidget);
      expect(_editorText(tester), 'one and two');
    });

    testWidgets('a submit during a save is saved after it', (tester) async {
      await pumpField(tester);
      await _tapCell(tester, 'cell');
      await tester.enterText(find.byType(EditableText), 'one');
      await _pressSave(tester);
      await tester.enterText(find.byType(EditableText), 'two');
      await _pressSave(tester);
      expect(saves, ['one']);

      requests[0].complete(true);
      await tester.pump();
      expect(saves, ['one', 'two']);
      expect(find.byType(EditableText), findsOneWidget);

      requests[1].complete(true);
      await tester.pump();
      await tester.pump();
      expect(saved, ['one', 'two']);
      expect(find.byType(EditableText), findsNothing);
    });

    testWidgets('a throwing onSave keeps the editor and can save again', (
      tester,
    ) async {
      var calls = 0;
      await pumpField(
        tester,
        onSave: (value) {
          calls++;
          if (calls == 1) throw StateError('offline');
          saves.add(value);
          return true;
        },
      );
      await _tapCell(tester, 'cell');
      await tester.enterText(find.byType(EditableText), 'one');
      await _pressSave(tester);
      await tester.pump();
      expect(tester.takeException(), isStateError);
      expect(find.byType(EditableText), findsOneWidget);
      expect(saved, isEmpty);

      await _pressSave(tester);
      await tester.pump();
      expect(saves, ['one']);
      expect(saved, ['one']);
      expect(find.byType(EditableText), findsNothing);
    });
  });

  group('saveDrafts(batch:) with an open editor', () {
    late List<String> ownSaves;
    late LazyTextFieldEditController controller;

    setUp(() => ownSaves = []);

    Future<void> pumpCell(WidgetTester tester, {required bool useOnCommit}) {
      controller = LazyTextFieldEditController();
      addTearDown(controller.dispose);
      return tester.pumpWidget(
        _app(
          LazyTextFieldScope(
            controller: controller,
            child: SizedBox(
              width: 200,
              child: ScopedLazyTextField(
                cellId: 'a',
                text: 'old',
                style: _style,
                decoration: _decoration,
                onCommit: useOnCommit
                    ? (value) async => ownSaves.add(value)
                    : null,
                onSave: useOnCommit
                    ? null
                    : (value) {
                        ownSaves.add(value);
                        return true;
                      },
              ),
            ),
          ),
        ),
      );
    }

    for (final useOnCommit in [true, false]) {
      final kind = useOnCommit ? 'onCommit' : 'onSave';
      testWidgets('sends an open $kind editor in the batch only', (
        tester,
      ) async {
        await pumpCell(tester, useOnCommit: useOnCommit);
        await _tapCell(tester, 'a');
        await tester.enterText(find.byType(EditableText), 'new');
        await tester.pump();

        final batches = <Map<Object, String>>[];
        final result = await controller.saveDrafts(
          batch: (values) async {
            batches.add(values);
            return const {};
          },
        );
        await tester.pump();

        expect(batches, [
          {'a': 'new'},
        ]);
        expect(ownSaves, isEmpty);
        expect(result.saved, 1);
        expect(result.allSaved, isTrue);
        expect(controller.isEditing('a'), isFalse);
        expect(
          controller.draftFor('a')?.status,
          LazyTextFieldDraftStatus.saved,
        );
      });
    }

    testWidgets('leaves an unchanged open editor out of the batch', (
      tester,
    ) async {
      await pumpCell(tester, useOnCommit: true);
      await _tapCell(tester, 'a');

      var called = false;
      final result = await controller.saveDrafts(
        batch: (values) async {
          called = true;
          return const {};
        },
      );
      expect(called, isFalse);
      expect(result.allSaved, isTrue);
      expect(controller.isEditing('a'), isFalse);
    });
  });
}
