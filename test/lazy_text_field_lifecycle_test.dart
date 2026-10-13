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

  Future<void> pumpStateful(
    WidgetTester tester, {
    required String cellId,
    required String text,
    required LazyTextFieldSave onSave,
    Key? key,
    ValueChanged<String>? onSaved,
    VoidCallback? onCancel,
    FutureOr<bool> Function()? onWillStartEditing,
  }) {
    return tester.pumpWidget(
      _LifecycleApp(
        child: SizedBox(
          width: 200,
          child: StatefulLazyTextField(
            key: key,
            cellId: cellId,
            text: text,
            onSave: onSave,
            onSaved: onSaved,
            onCancel: onCancel,
            onWillStartEditing: onWillStartEditing,
            style: style,
            decoration: const InputDecoration(
              border: InputBorder.none,
              isCollapsed: true,
              contentPadding: EdgeInsets.all(4),
            ),
          ),
        ),
      ),
    );
  }

  group('P0 save / cancel / cellId races', () {
    testWidgets('pending save after cancel does not wipe a later edit', (
      tester,
    ) async {
      final gate = Completer<bool>();
      final saved = <String>[];
      var saveCalls = 0;

      await pumpStateful(
        tester,
        cellId: 'cell',
        text: 'alpha',
        onSave: (_) {
          saveCalls++;
          // First save stays pending; later saves (if any) accept immediately.
          if (saveCalls == 1) return gate.future;
          return true;
        },
        onSaved: saved.add,
        onCancel: () {},
      );

      await tester.tap(find.byKey(LazyTextFieldKeys.staticSurface('cell')));
      await tester.pump();
      await tester.enterText(find.byType(EditableText), 'alpha-edited');
      await tester.pump();
      // Ctrl+S keeps focus (unlike IME done), so Escape can still cancel.
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      expect(find.byType(EditableText), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(find.byType(EditableText), findsNothing);

      await tester.tap(find.byKey(LazyTextFieldKeys.staticSurface('cell')));
      await tester.pump();
      await tester.enterText(find.byType(EditableText), 'beta-draft');
      await tester.pump();

      gate.complete(true);
      await tester.pump();

      expect(find.byType(EditableText), findsOneWidget);
      expect(
        tester.widget<EditableText>(find.byType(EditableText)).controller.text,
        'beta-draft',
      );
      expect(saved, isEmpty);
    });

    testWidgets('two concurrent saves commit once and call onSaved once', (
      tester,
    ) async {
      final gate = Completer<bool>();
      var saveCalls = 0;
      final saved = <String>[];

      await pumpStateful(
        tester,
        cellId: 'cell',
        text: 'value',
        onSave: (_) {
          saveCalls++;
          return gate.future;
        },
        onSaved: saved.add,
      );

      await tester.tap(find.byKey(LazyTextFieldKeys.staticSurface('cell')));
      await tester.pump();
      await tester.enterText(find.byType(EditableText), 'committed');
      await tester.pump();

      Future<void> pressSaveShortcut() async {
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await tester.pump();
      }

      await pressSaveShortcut();
      await pressSaveShortcut();

      expect(saveCalls, 1);
      expect(find.byType(EditableText), findsOneWidget);

      gate.complete(true);
      await tester.pump();
      await tester.pump();

      expect(saved, ['committed']);
      expect(find.byKey(LazyTextFieldKeys.editorSurface('cell')), findsNothing);
      expect(find.byType(EditableText), findsNothing);
    });

    testWidgets(
      'reusing StatefulLazyTextField state with a new cellId drops the draft',
      (tester) async {
        final key = GlobalKey();
        var cellId = 'old';
        var text = 'old-text';

        Future<void> pump() {
          return tester.pumpWidget(
            _LifecycleApp(
              child: SizedBox(
                width: 200,
                child: StatefulLazyTextField(
                  key: key,
                  cellId: cellId,
                  text: text,
                  style: style,
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    isCollapsed: true,
                    contentPadding: EdgeInsets.all(4),
                  ),
                  onSave: (_) => true,
                ),
              ),
            ),
          );
        }

        await pump();
        await tester.tap(find.byKey(LazyTextFieldKeys.staticSurface('old')));
        await tester.pump();
        await tester.enterText(find.byType(EditableText), 'draft-old');
        await tester.pump();

        cellId = 'new';
        text = 'new-text';
        await pump();
        await tester.pump();

        expect(
          find.byKey(LazyTextFieldKeys.staticSurface('new')),
          findsOneWidget,
        );
        expect(
          find.byKey(LazyTextFieldKeys.editorSurface('new')),
          findsNothing,
        );
        expect(find.byType(EditableText), findsNothing);
        expect(find.textContaining('draft-old'), findsNothing);
      },
    );
  });

  group('P1 scoped lifecycle', () {
    testWidgets('activating another scoped cell releases the previous edit', (
      tester,
    ) async {
      final editController = LazyTextFieldEditController();
      addTearDown(editController.dispose);

      await tester.pumpWidget(
        _LifecycleApp(
          child: LazyTextFieldControllerScope(
            controller: editController,
            child: Column(
              children: [
                SizedBox(
                  width: 200,
                  child: ScopedLazyTextField(
                    cellId: 'a',
                    text: 'cell-a',
                    style: style,
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      isCollapsed: true,
                      contentPadding: EdgeInsets.all(4),
                    ),
                    onSave: (_) => true,
                  ),
                ),
                SizedBox(
                  width: 200,
                  child: ScopedLazyTextField(
                    cellId: 'b',
                    text: 'cell-b',
                    style: style,
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      isCollapsed: true,
                      contentPadding: EdgeInsets.all(4),
                    ),
                    onSave: (_) => true,
                  ),
                ),
              ],
            ),
          ),
        ),
      );

      await tester.tap(find.byKey(LazyTextFieldKeys.staticSurface('a')));
      await tester.pump();
      expect(editController.isEditing('a'), isTrue);
      expect(editController.activeIds, ['a']);

      await tester.tap(find.byKey(LazyTextFieldKeys.staticSurface('b')));
      await tester.pump();
      await tester.pump();

      expect(editController.isEditing('a'), isFalse);
      expect(editController.isEditing('b'), isTrue);
      expect(editController.activeIds, ['b']);
      expect(find.byKey(LazyTextFieldKeys.editorSurface('b')), findsOneWidget);
      expect(find.byKey(LazyTextFieldKeys.editorSurface('a')), findsNothing);
    });

    testWidgets(
      'unmounting an active scoped cell stops editing (virtualized dispose)',
      (tester) async {
        final editController = LazyTextFieldEditController();
        addTearDown(editController.dispose);
        var showCell = true;

        await tester.pumpWidget(
          _LifecycleApp(
            child: LazyTextFieldControllerScope(
              controller: editController,
              child: StatefulBuilder(
                builder: (context, setState) {
                  return Column(
                    children: [
                      if (showCell)
                        SizedBox(
                          width: 200,
                          child: ScopedLazyTextField(
                            cellId: 'row',
                            text: 'visible',
                            style: style,
                            decoration: const InputDecoration(
                              border: InputBorder.none,
                              isCollapsed: true,
                              contentPadding: EdgeInsets.all(4),
                            ),
                            onSave: (_) => true,
                          ),
                        ),
                      TextButton(
                        onPressed: () => setState(() => showCell = false),
                        child: const Text('unmount'),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        );

        await tester.tap(find.byKey(LazyTextFieldKeys.staticSurface('row')));
        await tester.pump();
        expect(editController.isEditing('row'), isTrue);

        await tester.tap(find.text('unmount'));
        await tester.pump();

        expect(editController.isEditing('row'), isFalse);
        expect(editController.controllers, isEmpty);
        expect(editController.focusNodes, isEmpty);
      },
    );

    testWidgets(
      'onWillStartEditing completing after dispose creates no editor',
      (tester) async {
        final gate = Completer<bool>();
        final editController = LazyTextFieldEditController();
        addTearDown(editController.dispose);
        var mountedCell = true;

        await tester.pumpWidget(
          _LifecycleApp(
            child: LazyTextFieldControllerScope(
              controller: editController,
              child: StatefulBuilder(
                builder: (context, setState) {
                  return Column(
                    children: [
                      if (mountedCell)
                        SizedBox(
                          width: 200,
                          child: ScopedLazyTextField(
                            cellId: 'late',
                            text: 'late-start',
                            style: style,
                            decoration: const InputDecoration(
                              border: InputBorder.none,
                              isCollapsed: true,
                              contentPadding: EdgeInsets.all(4),
                            ),
                            onWillStartEditing: () => gate.future,
                            onSave: (_) => true,
                          ),
                        ),
                      TextButton(
                        onPressed: () => setState(() => mountedCell = false),
                        child: const Text('dispose-cell'),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        );

        await tester.tap(find.byKey(LazyTextFieldKeys.staticSurface('late')));
        await tester.pump();
        expect(editController.isEditing('late'), isFalse);

        await tester.tap(find.text('dispose-cell'));
        await tester.pump();

        gate.complete(true);
        await tester.pump();

        expect(editController.isEditing('late'), isFalse);
        expect(find.byType(EditableText), findsNothing);
      },
    );

    testWidgets(
      'onWillStartEditing completing after cellId change creates no orphan',
      (tester) async {
        final gate = Completer<bool>();
        final key = GlobalKey();
        var cellId = 'first';

        await tester.pumpWidget(
          _LifecycleApp(
            child: StatefulBuilder(
              builder: (context, setState) {
                return SizedBox(
                  width: 200,
                  child: StatefulLazyTextField(
                    key: key,
                    cellId: cellId,
                    text: cellId,
                    style: style,
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      isCollapsed: true,
                      contentPadding: EdgeInsets.all(4),
                    ),
                    onWillStartEditing: () => gate.future,
                    onSave: (_) => true,
                  ),
                );
              },
            ),
          ),
        );

        await tester.tap(find.byKey(LazyTextFieldKeys.staticSurface('first')));
        await tester.pump();

        cellId = 'second';
        await tester.pumpWidget(
          _LifecycleApp(
            child: SizedBox(
              width: 200,
              child: StatefulLazyTextField(
                key: key,
                cellId: cellId,
                text: cellId,
                style: style,
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  isCollapsed: true,
                  contentPadding: EdgeInsets.all(4),
                ),
                onWillStartEditing: () => true,
                onSave: (_) => true,
              ),
            ),
          ),
        );
        await tester.pump();

        gate.complete(true);
        await tester.pump();

        expect(find.byType(EditableText), findsNothing);
        expect(
          find.byKey(LazyTextFieldKeys.staticSurface('second')),
          findsOneWidget,
        );
      },
    );
  });

  group('P2 keyboard save / cancel', () {
    testWidgets(
      'Escape cancels; Enter/Ctrl+Enter/Ctrl+S/IME submit save once',
      (tester) async {
        Future<void> expectSaveFrom(Future<void> Function() trigger) async {
          final saved = <String>[];
          await pumpStateful(
            tester,
            cellId: 'keys',
            text: 'plain',
            onSave: (_) => true,
            onSaved: saved.add,
          );
          await tester.tap(find.byKey(LazyTextFieldKeys.staticSurface('keys')));
          await tester.pump();
          await tester.enterText(find.byType(EditableText), 'saved-value');
          await tester.pump();
          await trigger();
          await tester.pump();
          expect(saved, ['saved-value']);
          expect(find.byType(EditableText), findsNothing);
        }

        await expectSaveFrom(() async {
          await tester.testTextInput.receiveAction(TextInputAction.done);
        });

        await expectSaveFrom(() async {
          await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        });

        await expectSaveFrom(() async {
          await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
          await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
          await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        });

        final cancelled = <int>[];
        await pumpStateful(
          tester,
          cellId: 'keys',
          text: 'plain',
          onSave: (_) => true,
          onCancel: () => cancelled.add(1),
        );
        await tester.tap(find.byKey(LazyTextFieldKeys.staticSurface('keys')));
        await tester.pump();
        await tester.enterText(find.byType(EditableText), 'discard');
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pump();
        expect(cancelled, [1]);
        expect(find.byType(EditableText), findsNothing);
      },
    );

    testWidgets('single-line Enter saves without duplicate onSaved', (
      tester,
    ) async {
      final saved = <String>[];
      await tester.pumpWidget(
        _LifecycleApp(
          child: SizedBox(
            width: 200,
            child: StatefulLazyTextField(
              cellId: 'single',
              text: 'one-line',
              singleLine: true,
              style: style,
              decoration: const InputDecoration(
                border: InputBorder.none,
                isCollapsed: true,
                contentPadding: EdgeInsets.all(4),
              ),
              onSave: (_) => true,
              onSaved: saved.add,
            ),
          ),
        ),
      );

      await tester.tap(find.byKey(LazyTextFieldKeys.staticSurface('single')));
      await tester.pump();
      await tester.enterText(find.byType(EditableText), 'done');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();

      expect(saved, ['done']);
      expect(find.byType(EditableText), findsNothing);
    });
  });
}

class _LifecycleApp extends StatelessWidget {
  const _LifecycleApp({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Align(alignment: Alignment.topLeft, child: child),
      ),
    );
  }
}
