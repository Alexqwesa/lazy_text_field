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

String _shown(WidgetTester tester, String id) => tester
    .widget<LazyTextField>(
      find.byWidgetPredicate((w) => w is LazyTextField && w.cellId == id),
    )
    .text;

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

String _editorText(WidgetTester tester) =>
    tester.widget<EditableText>(find.byType(EditableText)).controller.text;

void main() {
  group('onSave cells', () {
    late LazyTextFieldEditController controller;
    late List<String> saves;
    late List<String> saved;
    late LazyTextFieldSave onSaveA;

    setUp(() {
      saves = [];
      saved = [];
    });

    Future<void> pumpCells(
      WidgetTester tester, {
      LazyTextFieldSwitchPolicy switchPolicy = LazyTextFieldSwitchPolicy.commit,
    }) {
      controller = LazyTextFieldEditController(switchPolicy: switchPolicy);
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
      expect(saves, ['first']);
      expect(_shown(tester, 'a'), 'first');

      await _open(tester, 'a');
      expect(_editorText(tester), 'first');
      await _type(tester, 'second');
      first.complete(true);
      await tester.pump();

      expect(controller.isEditing('a'), isTrue);
      expect(_editorText(tester), 'second');
      expect(saved, ['first']);

      // The reopened editor can submit while nothing else is running.
      await _submit(tester);
      await tester.pump();
      expect(saves, ['first', 'second']);
      expect(controller.isEditing('a'), isFalse);
      expect(saved, ['first', 'second']);
    });

    testWidgets('a reopened editor can submit while the old save still runs', (
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
      await _submit(tester);
      await tester.pump();

      expect(saves, ['first', 'second']);
      expect(controller.isEditing('a'), isFalse);
      first.complete(true);
      await tester.pump();
      expect(saved, ['second', 'first']);
    });

    testWidgets('a rejected switch save keeps the text as a failed draft', (
      tester,
    ) async {
      onSaveA = (_) => false;
      await pumpCells(tester);
      await _open(tester, 'a');
      await _type(tester, 'bad');
      await _open(tester, 'b');
      await tester.pump();

      expect(saves, ['bad']);
      expect(saved, isEmpty);
      expect(_shown(tester, 'a'), 'bad');
      final draft = controller.draftFor('a')!;
      expect(draft.status, LazyTextFieldDraftStatus.failed);
      expect(draft.error, isNull);

      await _open(tester, 'a');
      expect(_editorText(tester), 'bad');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(controller.draftFor('a'), isNull);
      expect(_shown(tester, 'a'), 'old-a');
    });

    testWidgets('a rejected submit that a switch closed keeps the draft', (
      tester,
    ) async {
      final result = Completer<bool>();
      onSaveA = (_) => result.future;
      await pumpCells(tester);
      await _open(tester, 'a');
      await _type(tester, 'bad');
      await _submit(tester);
      await _open(tester, 'b');
      expect(saves, ['bad']);

      result.complete(false);
      await tester.pump();
      expect(saves, ['bad']);
      expect(controller.draftFor('a')!.status, LazyTextFieldDraftStatus.failed);
      expect(_shown(tester, 'a'), 'bad');
    });

    testWidgets('a later successful submit clears the failed draft', (
      tester,
    ) async {
      var accept = false;
      onSaveA = (_) => accept;
      await pumpCells(tester);
      await _open(tester, 'a');
      await _type(tester, 'bad');
      await _open(tester, 'b');
      await tester.pump();
      expect(controller.draftFor('a')!.status, LazyTextFieldDraftStatus.failed);

      accept = true;
      await _open(tester, 'a');
      await _submit(tester);
      await tester.pump();
      expect(controller.draftFor('a'), isNull);
      expect(saved, ['bad']);
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
      expect(controller.isEditing('a'), isFalse);
      expect(saved, ['x']);
    });

    testWidgets(
      'an onSave that throws on switch keeps the error on the draft',
      (tester) async {
        onSaveA = (_) async => throw StateError('boom');
        await pumpCells(tester);
        await _open(tester, 'a');
        await _type(tester, 'x');
        await _open(tester, 'b');
        await tester.pump();

        expect(tester.takeException(), isStateError);
        final draft = controller.draftFor('a')!;
        expect(draft.status, LazyTextFieldDraftStatus.failed);
        expect(draft.error, isStateError);
        expect(_shown(tester, 'a'), 'x');
      },
    );

    testWidgets('switching without changes does not save', (tester) async {
      onSaveA = (_) => true;
      await pumpCells(tester);
      await _open(tester, 'a');
      await _open(tester, 'b');
      await tester.pump();
      expect(saves, isEmpty);
      expect(controller.draftFor('a'), isNull);
    });
  });

  group('cells that leave the tree while editing', () {
    late ScrollController scroll;
    late List<(String, String)> commits;
    late List<Completer<void>> pending;

    setUp(() {
      commits = [];
      pending = [];
    });

    Future<LazyTextFieldEditController> pumpList(
      WidgetTester tester, {
      bool useOnSave = false,
      bool keepAlive = false,
      LazyTextFieldSwitchPolicy switchPolicy = LazyTextFieldSwitchPolicy.commit,
    }) async {
      final controller = LazyTextFieldEditController(
        switchPolicy: switchPolicy,
      );
      addTearDown(controller.dispose);
      scroll = ScrollController();
      addTearDown(scroll.dispose);
      await tester.pumpWidget(
        _app(
          LazyTextFieldControllerScope(
            controller: controller,
            child: SizedBox(
              width: 200,
              height: 100,
              child: ListView.builder(
                controller: scroll,
                // ListView keeps a focused field alive by default. Grids with
                // their own virtualization dispose it; so does this list.
                addAutomaticKeepAlives: keepAlive,
                itemExtent: 50,
                itemCount: 100,
                itemBuilder: (context, index) => ScopedLazyTextField(
                  cellId: 'row-$index',
                  text: 'old-$index',
                  singleLine: true,
                  style: _style,
                  decoration: _decoration,
                  onCommit: useOnSave
                      ? null
                      : (value) {
                          commits.add(('row-$index', value));
                          final completer = Completer<void>();
                          pending.add(completer);
                          return completer.future;
                        },
                  onSave: useOnSave
                      ? (value) {
                          commits.add(('row-$index', value));
                          return true;
                        }
                      : null,
                ),
              ),
            ),
          ),
        ),
      );
      return controller;
    }

    Future<void> scrollTo(WidgetTester tester, double offset) async {
      scroll.jumpTo(offset);
      await tester.pump();
      await tester.pump();
    }

    testWidgets('scrolling an edited cell away commits and keeps its text', (
      tester,
    ) async {
      final controller = await pumpList(tester);
      await _open(tester, 'row-0');
      await _type(tester, 'typed');
      await scrollTo(tester, 2000);

      expect(find.byKey(LazyTextFieldKeys.root('row-0')), findsNothing);
      expect(tester.takeException(), isNull);
      expect(controller.activeIds, isEmpty);
      expect(commits, [('row-0', 'typed')]);
      expect(
        controller.draftFor('row-0')!.status,
        LazyTextFieldDraftStatus.pending,
      );

      await scrollTo(tester, 0);
      expect(_shown(tester, 'row-0'), 'typed');
      pending.single.complete();
      await tester.pump();
      expect(_shown(tester, 'row-0'), 'typed');
      expect(
        controller.draftFor('row-0')!.status,
        LazyTextFieldDraftStatus.saved,
      );
    });

    testWidgets('a keep-alive list keeps the editor open while scrolled away', (
      tester,
    ) async {
      final controller = await pumpList(tester, keepAlive: true);
      await _open(tester, 'row-0');
      await _type(tester, 'typed');
      await scrollTo(tester, 2000);
      await scrollTo(tester, 0);

      expect(commits, isEmpty);
      expect(controller.isEditing('row-0'), isTrue);
      expect(_editorText(tester), 'typed');
    });

    testWidgets('scrolling an edited onSave cell away saves its text', (
      tester,
    ) async {
      final controller = await pumpList(tester, useOnSave: true);
      await _open(tester, 'row-0');
      await _type(tester, 'typed');
      await scrollTo(tester, 2000);
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(commits, [('row-0', 'typed')]);
      await scrollTo(tester, 0);
      expect(_shown(tester, 'row-0'), 'typed');
      expect(
        controller.draftFor('row-0')!.status,
        LazyTextFieldDraftStatus.saved,
      );
    });

    testWidgets('an unchanged editor scrolled away does not commit', (
      tester,
    ) async {
      await pumpList(tester);
      await _open(tester, 'row-0');
      await scrollTo(tester, 2000);
      expect(commits, isEmpty);
    });

    testWidgets('the discard policy drops the text of a cell scrolled away', (
      tester,
    ) async {
      final controller = await pumpList(
        tester,
        switchPolicy: LazyTextFieldSwitchPolicy.discard,
      );
      await _open(tester, 'row-0');
      await _type(tester, 'typed');
      await scrollTo(tester, 2000);
      await scrollTo(tester, 0);

      expect(commits, isEmpty);
      expect(controller.draftFor('row-0'), isNull);
      expect(_shown(tester, 'row-0'), 'old-0');
    });

    testWidgets('a recycled cell commits the text typed for its old id', (
      tester,
    ) async {
      final controller = LazyTextFieldEditController();
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
                  onCommit: (value) async => commits.add((id, value)),
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
      expect(commits, [('a', 'typed')]);
      expect(controller.activeIds, isEmpty);
      expect(_shown(tester, 'b'), 'old-b');
      expect(controller.displayText('a', 'old-a'), 'typed');
    });
  });
}
