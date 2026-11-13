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

void main() {
  /// Pumps [scopes] around a probe and returns the controller it sees.
  Future<LazyTextFieldEditController?> controllerUnder(
    WidgetTester tester,
    Widget Function(Widget probe) scopes,
  ) async {
    LazyTextFieldEditController? seen;
    await tester.pumpWidget(
      scopes(
        Builder(
          builder: (context) {
            seen = LazyTextFieldScope.maybeOf(context);
            return const SizedBox();
          },
        ),
      ),
    );
    return seen;
  }

  testWidgets('a scope without a controller creates one', (tester) async {
    final seen = await controllerUnder(
      tester,
      (probe) => LazyTextFieldScope(child: probe),
    );
    expect(seen, isNotNull);
  });

  testWidgets('a nested scope without a controller uses the one above', (
    tester,
  ) async {
    final controller = LazyTextFieldEditController();
    addTearDown(controller.dispose);
    final seen = await controllerUnder(
      tester,
      (probe) => LazyTextFieldScope(
        controller: controller,
        child: LazyTextFieldScope(shortcuts: const {}, child: probe),
      ),
    );
    expect(seen, same(controller));
  });

  group('table of a nested scope', () {
    late LazyTextFieldEditController outer;
    late LazyTextFieldEditController inner;

    setUp(() {
      outer = LazyTextFieldEditController(
        saveMode: LazyTextFieldSaveMode.deferred,
      );
      inner = LazyTextFieldEditController(
        saveMode: LazyTextFieldSaveMode.deferred,
      );
      addTearDown(outer.dispose);
      addTearDown(inner.dispose);
    });

    Future<void> keepDraft(WidgetTester tester, Widget Function(Widget) wrap) =>
        _editAndSubmit(
          tester,
          wrap(
            LazyTextFieldScope.row(
              rowId: 1,
              version: 'v1',
              child: SizedBox(
                width: 200,
                child: ScopedLazyTextField(
                  cellId: 'cell',
                  fieldId: 'title',
                  text: 'old',
                  singleLine: true,
                  style: _style,
                  onCommit: (_) async {},
                ),
              ),
            ),
          ),
        );

    testWidgets('comes from the scope above', (tester) async {
      await keepDraft(
        tester,
        (child) => LazyTextFieldScope(
          controller: outer,
          tableId: 'tasks',
          child: LazyTextFieldScope(shortcuts: const {}, child: child),
        ),
      );
      expect(outer.drafts.keys, [
        const LazyTextFieldDraftId(table: 'tasks', row: '1', field: 'title'),
      ]);
    });

    testWidgets('is not taken from above by a scope with its own controller', (
      tester,
    ) async {
      await keepDraft(
        tester,
        (child) => LazyTextFieldScope(
          controller: outer,
          tableId: 'tasks',
          child: LazyTextFieldScope(controller: inner, child: child),
        ),
      );
      // No table: the draft belongs to the cell.
      expect(inner.drafts.keys, ['cell']);
      expect(outer.drafts, isEmpty);
    });
  });

  testWidgets('the 2.x name LazyTextFieldControllerScope still works', (
    tester,
  ) async {
    final controller = LazyTextFieldEditController();
    addTearDown(controller.dispose);
    LazyTextFieldEditController? seen;
    await tester.pumpWidget(
      // ignore: deprecated_member_use_from_same_package
      LazyTextFieldControllerScope(
        controller: controller,
        child: Builder(
          builder: (context) {
            // ignore: deprecated_member_use_from_same_package
            seen = LazyTextFieldControllerScope.of(context);
            return const SizedBox();
          },
        ),
      ),
    );
    expect(seen, same(controller));
  });
}

/// Opens the only cell in [widget], types, and presses Enter.
Future<void> _editAndSubmit(WidgetTester tester, Widget widget) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Align(alignment: Alignment.topLeft, child: widget),
      ),
    ),
  );
  await tester.tap(find.byKey(LazyTextFieldKeys.staticSurface('cell')));
  await tester.pump();
  await tester.pump();
  await tester.enterText(find.byType(EditableText), 'new');
  await tester.sendKeyEvent(LogicalKeyboardKey.enter);
  await tester.pump();
}
