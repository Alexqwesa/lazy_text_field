import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lazy_text_field/lazy_text_field.dart';

void main() {
  const style = TextStyle(
    fontFamily: 'Ahem',
    fontSize: 10,
    height: 1,
    letterSpacing: 0,
  );

  Widget cell(
    String id, {
    required LazyTextFieldSave onSave,
    ValueChanged<String>? onSaved,
  }) {
    return SizedBox(
      width: 200,
      child: ScopedLazyTextField(
        cellId: id,
        text: 'cell-$id',
        style: style,
        decoration: const InputDecoration(
          border: InputBorder.none,
          isCollapsed: true,
          contentPadding: EdgeInsets.all(4),
        ),
        onSave: onSave,
        onSaved: onSaved,
      ),
    );
  }

  Future<void> pumpCells(
    WidgetTester tester,
    LazyTextFieldEditController controller, {
    required LazyTextFieldSave onSaveA,
    ValueChanged<String>? onSavedA,
  }) {
    return tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: LazyTextFieldControllerScope(
              controller: controller,
              child: Column(
                children: [
                  cell('a', onSave: onSaveA, onSaved: onSavedA),
                  cell('b', onSave: (_) => true),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> editA(WidgetTester tester, String text) async {
    await tester.tap(find.byKey(LazyTextFieldKeys.staticSurface('a')));
    await tester.pump();
    await tester.pump();
    await tester.enterText(find.byType(EditableText), text);
  }

  Future<void> tapB(WidgetTester tester) async {
    await tester.tap(find.byKey(LazyTextFieldKeys.staticSurface('b')));
    await tester.pump();
    await tester.pump();
  }

  testWidgets('switching cells commits the previous draft in the background', (
    tester,
  ) async {
    final controller = LazyTextFieldEditController();
    addTearDown(controller.dispose);
    final saves = <String>[];
    final saved = <String>[];
    final pending = Completer<bool>();

    await pumpCells(
      tester,
      controller,
      onSaveA: (value) {
        saves.add(value);
        return pending.future;
      },
      onSavedA: saved.add,
    );
    await editA(tester, 'a-draft');
    await tapB(tester);

    // The next cell is focused before the save finishes.
    expect(saves, ['a-draft']);
    expect(controller.activeIds, ['b']);
    expect(controller.focusNodeFor('b')!.hasFocus, isTrue);
    expect(saved, isEmpty);

    pending.complete(true);
    await tester.pump();
    expect(saved, ['a-draft']);
    expect(controller.activeIds, ['b']);
  });

  testWidgets('a rejected switch commit skips onSaved', (tester) async {
    final controller = LazyTextFieldEditController();
    addTearDown(controller.dispose);
    final saved = <String>[];

    await pumpCells(
      tester,
      controller,
      onSaveA: (_) => false,
      onSavedA: saved.add,
    );
    await editA(tester, 'a-draft');
    await tapB(tester);

    expect(controller.activeIds, ['b']);
    expect(saved, isEmpty);
  });

  testWidgets('a submit already saving the same text is not saved twice', (
    tester,
  ) async {
    final controller = LazyTextFieldEditController();
    addTearDown(controller.dispose);
    final saves = <String>[];
    final saved = <String>[];
    final pending = Completer<bool>();

    await pumpCells(
      tester,
      controller,
      onSaveA: (value) {
        saves.add(value);
        return pending.future;
      },
      onSavedA: saved.add,
    );
    await editA(tester, 'a-draft');
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(saves, ['a-draft']);

    await tapB(tester);
    expect(saves, ['a-draft']);
    expect(controller.activeIds, ['b']);

    pending.complete(true);
    await tester.pump();
    expect(saved, ['a-draft']);
    expect(controller.activeIds, ['b']);
  });

  testWidgets('a canceled edit is not committed on switch', (tester) async {
    final controller = LazyTextFieldEditController();
    addTearDown(controller.dispose);
    final saves = <String>[];

    await pumpCells(
      tester,
      controller,
      onSaveA: (value) {
        saves.add(value);
        return true;
      },
    );
    await editA(tester, 'a-draft');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    await tapB(tester);

    expect(saves, isEmpty);
  });

  testWidgets('commit handlers register only for active cells', (tester) async {
    final controller = LazyTextFieldEditController();
    addTearDown(controller.dispose);
    final commits = <String>[];
    void handler(String text) => commits.add(text);

    await tester.pumpWidget(const SizedBox.shrink());
    controller.setCommitHandler('a', handler);
    controller.startEditing(cellId: 'a', initialValue: 'one');
    controller.startEditing(cellId: 'b', initialValue: 'two');
    expect(commits, isEmpty);

    controller.setCommitHandler('b', handler);
    controller.removeCommitHandler('b', (_) {});
    controller.startEditing(cellId: 'c', initialValue: 'three');
    expect(commits, ['two']);

    controller.setCommitHandler('c', handler);
    controller.stopEditing('c');
    controller.startEditing(cellId: 'c', initialValue: 'three');
    controller.startEditing(cellId: 'd', initialValue: 'four');
    expect(commits, ['two']);
    await tester.pump();
  });

  group('whenEditingDone', () {
    testWidgets('completes at once when nothing is editing', (tester) async {
      final controller = LazyTextFieldEditController();
      addTearDown(controller.dispose);
      var done = false;
      unawaited(controller.whenEditingDone().then((_) => done = true));
      await tester.pump();
      expect(done, isTrue);
    });

    testWidgets('survives a switch and completes when the last editor '
        'closes', (tester) async {
      final controller = LazyTextFieldEditController();
      addTearDown(controller.dispose);
      await pumpCells(tester, controller, onSaveA: (_) => true);
      await editA(tester, 'a-draft');
      var done = false;
      unawaited(controller.whenEditingDone().then((_) => done = true));

      await tapB(tester);
      expect(controller.activeIds, ['b']);
      expect(done, isFalse);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(controller.activeIds, isEmpty);
      expect(done, isTrue);
    });

    testWidgets('completes when the controller is disposed', (tester) async {
      final controller = LazyTextFieldEditController();
      controller.startEditing(cellId: 'a', initialValue: 'one');
      var done = false;
      unawaited(controller.whenEditingDone().then((_) => done = true));
      controller.dispose();
      await tester.pump();
      expect(done, isTrue);
    });
  });
}
