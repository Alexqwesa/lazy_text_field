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

/// Commits that the test completes by hand.
class _Server {
  final calls = <(String cell, String value)>[];
  final _pending = <Completer<void>>[];

  LazyTextFieldCommit commitFor(String cell) => (value) {
    calls.add((cell, value));
    final completer = Completer<void>();
    _pending.add(completer);
    return completer.future;
  };

  void succeed([int index = 0]) => _pending.removeAt(index).complete();

  void fail(Object error, [int index = 0]) =>
      _pending.removeAt(index).completeError(error);

  int get running => _pending.length;
}

class _Cell {
  const _Cell(this.id, {this.rowKey});

  final String id;
  final Object? rowKey;
}

void main() {
  late _Server server;
  late ValueNotifier<Map<String, String>> sources;
  late List<String> saved;

  setUp(() {
    server = _Server();
    saved = [];
  });

  Future<LazyTextFieldDraftController> pumpCells(
    WidgetTester tester, {
    List<_Cell> cells = const [_Cell('a'), _Cell('b')],
    LazyTextFieldSaveOrder saveOrder = LazyTextFieldSaveOrder.sequential,
    LazyTextFieldSubmitClose closeOnSubmit = LazyTextFieldSubmitClose.afterSave,
  }) async {
    final controller = LazyTextFieldDraftController(saveOrder: saveOrder);
    addTearDown(controller.dispose);
    sources = ValueNotifier({
      for (final cell in cells) cell.id: 'old-${cell.id}',
    });
    addTearDown(sources.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: LazyTextFieldControllerScope(
              controller: controller,
              child: ValueListenableBuilder(
                valueListenable: sources,
                builder: (context, values, _) => Column(
                  children: [
                    for (final cell in cells)
                      SizedBox(
                        width: 300,
                        child: ScopedLazyTextField(
                          cellId: cell.id,
                          rowKey: cell.rowKey,
                          text: values[cell.id]!,
                          singleLine: true,
                          style: _style,
                          decoration: const InputDecoration(
                            border: InputBorder.none,
                            isCollapsed: true,
                            contentPadding: EdgeInsets.all(4),
                          ),
                          closeOnSubmit: closeOnSubmit,
                          errorMessageOf: (error) => 'rejected: $error',
                          onCommit: server.commitFor(cell.id),
                          onSaved: saved.add,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    return controller;
  }

  String shown(WidgetTester tester, String id) => tester
      .widget<LazyTextField>(
        find.byWidgetPredicate((w) => w is LazyTextField && w.cellId == id),
      )
      .text;

  Future<void> open(WidgetTester tester, String id) async {
    await tester.tap(find.byKey(LazyTextFieldKeys.staticSurface(id)));
    await tester.pump();
    await tester.pump();
  }

  Future<void> type(WidgetTester tester, String text) =>
      tester.enterText(find.byType(EditableText), text);

  Future<void> submit(WidgetTester tester) async {
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
  }

  String editorText(WidgetTester tester) =>
      tester.widget<EditableText>(find.byType(EditableText)).controller.text;

  group('drafts', () {
    testWidgets('switching keeps the draft visible while it saves', (
      tester,
    ) async {
      final controller = await pumpCells(tester);
      await open(tester, 'a');
      await type(tester, 'new-a');
      await open(tester, 'b');

      expect(controller.activeIds, ['b']);
      expect(server.calls, [('a', 'new-a')]);
      expect(shown(tester, 'a'), 'new-a');
      expect(
        controller.draftFor('a')!.status,
        LazyTextFieldDraftStatus.pending,
      );
      expect(controller.pendingSaves, 1);

      server.succeed();
      await tester.pump();
      expect(controller.draftFor('a')!.status, LazyTextFieldDraftStatus.saved);
      expect(controller.pendingSaves, 0);
      expect(saved, ['new-a']);
      expect(shown(tester, 'a'), 'new-a');
      expect(controller.activeIds, ['b']);
    });

    testWidgets('a saved draft survives a stale refresh and yields to a new '
        'source', (tester) async {
      final controller = await pumpCells(tester);
      await open(tester, 'a');
      await type(tester, 'new-a');
      await open(tester, 'b');
      server.succeed();
      await tester.pump();

      // A fetch that started before the save still returns the old value.
      sources.value = {...sources.value};
      await tester.pump();
      expect(shown(tester, 'a'), 'new-a');

      // The server normalized the value.
      sources.value = {...sources.value, 'a': 'NEW-A'};
      await tester.pump();
      expect(shown(tester, 'a'), 'NEW-A');
      expect(controller.draftFor('a'), isNull);
    });

    testWidgets('a refresh between two saves does not show the first value', (
      tester,
    ) async {
      await pumpCells(tester);
      await open(tester, 'a');
      await type(tester, 'first');
      await open(tester, 'b');
      server.succeed();
      await tester.pump();
      await open(tester, 'a');
      expect(editorText(tester), 'first');
      await type(tester, 'second');
      await open(tester, 'b');
      server.succeed();
      await tester.pump();

      // A refresh that only saw the first save.
      sources.value = {...sources.value, 'a': 'first'};
      await tester.pump();
      expect(shown(tester, 'a'), 'second');

      sources.value = {...sources.value, 'a': 'second'};
      await tester.pump();
      expect(shown(tester, 'a'), 'second');
    });

    testWidgets('submitting unchanged text closes without a commit', (
      tester,
    ) async {
      final controller = await pumpCells(tester);
      await open(tester, 'a');
      await submit(tester);
      expect(controller.activeIds, isEmpty);
      expect(server.calls, isEmpty);
    });
  });

  group('submit', () {
    testWidgets('afterSave keeps the editor open until the save succeeds', (
      tester,
    ) async {
      final controller = await pumpCells(tester);
      await open(tester, 'a');
      await type(tester, 'new-a');
      await submit(tester);
      await submit(tester);

      expect(server.calls, [('a', 'new-a')]);
      expect(controller.isEditing('a'), isTrue);

      server.succeed();
      await tester.pump();
      expect(controller.isEditing('a'), isFalse);
      expect(saved, ['new-a']);
      expect(shown(tester, 'a'), 'new-a');
    });

    testWidgets('afterSave leaves an editor that changed while saving open', (
      tester,
    ) async {
      final controller = await pumpCells(tester);
      await open(tester, 'a');
      await type(tester, 'new-a');
      await submit(tester);
      await type(tester, 'newer-a');

      server.succeed();
      await tester.pump();
      expect(controller.isEditing('a'), isTrue);
      expect(editorText(tester), 'newer-a');
      expect(saved, ['new-a']);
    });

    testWidgets('immediately closes the editor and saves in the background', (
      tester,
    ) async {
      final controller = await pumpCells(
        tester,
        closeOnSubmit: LazyTextFieldSubmitClose.immediately,
      );
      await open(tester, 'a');
      await type(tester, 'new-a');
      await submit(tester);

      expect(controller.isEditing('a'), isFalse);
      expect(shown(tester, 'a'), 'new-a');
      expect(saved, isEmpty);
      server.succeed();
      await tester.pump();
      expect(saved, ['new-a']);
    });
  });

  group('failures', () {
    testWidgets('a failed submit keeps the editor open with the error', (
      tester,
    ) async {
      final controller = await pumpCells(tester);
      await open(tester, 'a');
      await type(tester, 'bad');
      await submit(tester);
      server.fail('too long');
      // The failure settles, the cell rebuilds, then the popup shows.
      for (var i = 0; i < 3; i++) {
        await tester.pump();
      }

      expect(controller.isEditing('a'), isTrue);
      expect(controller.draftFor('a')!.status, LazyTextFieldDraftStatus.failed);
      expect(find.text("rejected: too long"), findsOneWidget);
      expect(saved, isEmpty);

      // Typing hides the error until the next commit.
      await type(tester, 'bad!');
      await tester.pump();
      await tester.pump();
      expect(find.text('rejected: too long'), findsNothing);
    });

    testWidgets('a failed switch commit stays visible and retries unchanged', (
      tester,
    ) async {
      final controller = await pumpCells(tester);
      await open(tester, 'a');
      await type(tester, 'bad');
      await open(tester, 'b');
      server.fail('nope');
      await tester.pump();

      expect(shown(tester, 'a'), 'bad');
      expect(controller.draftFor('a')!.status, LazyTextFieldDraftStatus.failed);
      // The error shows only while the cell is editing.
      expect(find.text('rejected: nope'), findsNothing);

      await open(tester, 'a');
      expect(editorText(tester), 'bad');
      await tester.pump();
      expect(find.text('rejected: nope'), findsOneWidget);

      await submit(tester);
      expect(server.calls, [('a', 'bad'), ('a', 'bad')]);
      server.succeed();
      await tester.pump();
      expect(controller.isEditing('a'), isFalse);
      expect(controller.draftFor('a')!.status, LazyTextFieldDraftStatus.saved);
    });

    testWidgets('Escape discards a failed draft', (tester) async {
      final controller = await pumpCells(tester);
      await open(tester, 'a');
      await type(tester, 'bad');
      await open(tester, 'b');
      server.fail('nope');
      await tester.pump();

      await open(tester, 'a');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(controller.draftFor('a'), isNull);
      expect(shown(tester, 'a'), 'old-a');
    });
  });

  group('save order', () {
    Future<void> commitBoth(WidgetTester tester) async {
      await open(tester, 'a');
      await type(tester, 'new-a');
      await open(tester, 'b');
      await type(tester, 'new-b');
      await open(tester, 'a');
      await tester.pump();
    }

    testWidgets('sequential runs one commit at a time', (tester) async {
      await pumpCells(
        tester,
        cells: const [_Cell('a', rowKey: 1), _Cell('b', rowKey: 2)],
      );
      await commitBoth(tester);
      expect(server.calls, [('a', 'new-a')]);

      server.succeed();
      await tester.pump();
      expect(server.calls, [('a', 'new-a'), ('b', 'new-b')]);
    });

    testWidgets('perRow runs different rows in parallel', (tester) async {
      await pumpCells(
        tester,
        cells: const [_Cell('a', rowKey: 1), _Cell('b', rowKey: 2)],
        saveOrder: LazyTextFieldSaveOrder.perRow,
      );
      await commitBoth(tester);
      expect(server.calls, [('a', 'new-a'), ('b', 'new-b')]);
      expect(server.running, 2);

      // Completion order does not matter across rows.
      server.succeed(1);
      await tester.pump();
      expect(shown(tester, 'b'), 'new-b');
      server.succeed();
      await tester.pump();
    });

    testWidgets('perRow keeps the same row in order', (tester) async {
      await pumpCells(
        tester,
        cells: const [_Cell('a', rowKey: 1), _Cell('b', rowKey: 1)],
        saveOrder: LazyTextFieldSaveOrder.perRow,
      );
      await commitBoth(tester);
      expect(server.calls, [('a', 'new-a')]);
      server.succeed();
      await tester.pump();
      expect(server.calls, [('a', 'new-a'), ('b', 'new-b')]);
    });

    testWidgets('perRow keeps cells without a rowKey in one queue', (
      tester,
    ) async {
      await pumpCells(tester, saveOrder: LazyTextFieldSaveOrder.perRow);
      await commitBoth(tester);
      expect(server.calls, [('a', 'new-a')]);
      server.succeed();
      await tester.pump();
      expect(server.calls, [('a', 'new-a'), ('b', 'new-b')]);
    });

    testWidgets('a failed commit does not stop the queue', (tester) async {
      await pumpCells(tester);
      await commitBoth(tester);
      server.fail('nope');
      await tester.pump();
      expect(server.calls, [('a', 'new-a'), ('b', 'new-b')]);
      server.succeed();
      await tester.pump();
    });
  });

  group('controller', () {
    testWidgets('enqueue of the pending value returns the running save', (
      tester,
    ) async {
      final controller = LazyTextFieldDraftController();
      addTearDown(controller.dispose);
      final commit = server.commitFor('k');
      final first = controller.enqueue(
        key: 'k',
        source: 'old',
        value: 'new',
        commit: commit,
      );
      final second = controller.enqueue(
        key: 'k',
        source: 'old',
        value: 'new',
        commit: commit,
      );
      expect(identical(first, second), isTrue);
      expect(controller.pendingSaves, 1);
      await tester.pump();
      server.succeed();
      expect(await first, isTrue);
    });

    testWidgets('clearDraft hides a running save result', (tester) async {
      final controller = LazyTextFieldDraftController();
      addTearDown(controller.dispose);
      final result = controller.enqueue(
        key: 'k',
        source: 'old',
        value: 'new',
        commit: server.commitFor('k'),
      );
      controller.clearDraft('k');
      expect(controller.displayText('k', 'old'), 'old');
      await tester.pump();
      server.succeed();
      expect(await result, isTrue);
      expect(controller.draftFor('k'), isNull);
    });

    testWidgets('dispose while saving does not throw', (tester) async {
      final controller = LazyTextFieldDraftController();
      final result = controller.enqueue(
        key: 'k',
        source: 'old',
        value: 'new',
        commit: server.commitFor('k'),
      );
      await tester.pump();
      controller.dispose();
      server.succeed();
      expect(await result, isTrue);
    });

    testWidgets('maybeOf finds only draft controllers', (tester) async {
      LazyTextFieldDraftController? found;
      final controller = LazyTextFieldDraftController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        LazyTextFieldControllerScope(
          controller: controller,
          child: Builder(
            builder: (context) {
              found = LazyTextFieldDraftController.maybeOf(context);
              return const SizedBox();
            },
          ),
        ),
      );
      expect(found, same(controller));

      await tester.pumpWidget(
        LazyTextFieldControllerScope(
          child: Builder(
            builder: (context) {
              found = LazyTextFieldDraftController.maybeOf(context);
              return const SizedBox();
            },
          ),
        ),
      );
      expect(found, isNull);
    });
  });
}
