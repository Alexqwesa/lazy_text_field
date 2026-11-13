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

LazyTextFieldDraftId _id(
  Object row, {
  String table = 'tasks',
  String field = 'title',
}) => LazyTextFieldDraftId(table: table, row: '$row', field: field);

void main() {
  late List<(String, String)> commits;
  late List<String> started;
  late List<FlutterErrorDetails> errors;
  Completer<void>? gate;

  setUp(() {
    commits = [];
    started = [];
    errors = [];
    gate = null;
  });

  void captureErrors() {
    final previous = FlutterError.onError;
    FlutterError.onError = errors.add;
    addTearDown(() => FlutterError.onError = previous);
  }

  LazyTextFieldEditController newController({
    LazyTextFieldSaveMode saveMode = LazyTextFieldSaveMode.deferred,
    LazyTextFieldSaveOrder saveOrder = LazyTextFieldSaveOrder.sequential,
    LazyTextFieldDraftStore? store,
  }) {
    final controller = LazyTextFieldEditController(
      saveMode: saveMode,
      saveOrder: saveOrder,
      draftStore: store,
    );
    addTearDown(controller.dispose);
    return controller;
  }

  /// A cell; commits are recorded as (label, value), label defaulting to
  /// the cell id.
  Widget cell(
    String cellId, {
    String? fieldId = 'title',
    Object? rowId,
    String? version,
    Object? draftKey,
    String? text,
    String? label,
  }) => SizedBox(
    width: 300,
    child: ScopedLazyTextField(
      cellId: cellId,
      fieldId: fieldId,
      rowId: rowId,
      version: version,
      draftKey: draftKey,
      text: text ?? 'server-$cellId',
      singleLine: true,
      style: _style,
      decoration: const InputDecoration(
        border: InputBorder.none,
        isCollapsed: true,
        contentPadding: EdgeInsets.all(4),
      ),
      onCommit: (value) async {
        started.add(label ?? cellId);
        await gate?.future;
        commits.add((label ?? cellId, value));
      },
    ),
  );

  Widget row(Object rowId, List<Widget> cells, {String? version = 'v1'}) =>
      LazyTextFieldScope.row(
        rowId: rowId,
        version: version,
        child: Column(children: cells),
      );

  Future<void> pumpTable(
    WidgetTester tester,
    LazyTextFieldEditController controller,
    List<Widget> children, {
    String? tableId = 'tasks',
  }) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: LazyTextFieldScope(
            controller: controller,
            tableId: tableId,
            child: Column(children: children),
          ),
        ),
      ),
    ),
  );

  String shown(WidgetTester tester, String cellId) => tester
      .widget<LazyTextField>(
        find.byWidgetPredicate((w) => w is LazyTextField && w.cellId == cellId),
      )
      .text;

  Future<void> open(WidgetTester tester, String cellId) async {
    await tester.tap(find.byKey(LazyTextFieldKeys.staticSurface(cellId)));
    await tester.pump();
    await tester.pump();
  }

  Future<void> edit(WidgetTester tester, String cellId, String text) async {
    await open(tester, cellId);
    await tester.enterText(find.byType(EditableText), text);
    await tester.pump();
  }

  Future<void> submit(WidgetTester tester) async {
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    await tester.pump();
  }

  group('draft id from the scopes', () {
    testWidgets('table from the scope, row and version from the row scope, '
        'field from the cell', (tester) async {
      final store = LazyTextFieldMemoryDraftStore();
      final controller = newController(store: store);
      await pumpTable(tester, controller, [
        row(7, [cell('t7'), cell('n7', fieldId: 'note')], version: 'v3'),
      ]);
      await edit(tester, 't7', 'new title');
      await submit(tester);
      await edit(tester, 'n7', 'new note');
      await submit(tester);

      expect(controller.draftFor(_id(7))!.value, 'new title');
      expect(controller.draftFor(_id(7))!.baseVersion, 'v3');
      expect(controller.draftFor(_id(7, field: 'note'))!.value, 'new note');
      expect(await controller.whenDraftsStored(), isTrue);
      expect(
        store.drafts.keys,
        unorderedEquals(['tasks/7/title', 'tasks/7/note']),
      );
    });

    testWidgets("a cell's own rowId and version win over the row scope", (
      tester,
    ) async {
      final controller = newController();
      await pumpTable(tester, controller, [
        row(7, [cell('x', rowId: 8, version: 'v9')]),
      ]);
      await edit(tester, 'x', 'new');
      await submit(tester);

      expect(controller.draftFor(_id(8))!.baseVersion, 'v9');
    });

    testWidgets('cells without a row scope give rowId and version', (
      tester,
    ) async {
      final store = LazyTextFieldMemoryDraftStore();
      final controller = newController(store: store);
      await pumpTable(tester, controller, [cell('x', rowId: 4, version: 'v2')]);
      await edit(tester, 'x', 'new');
      await submit(tester);

      expect(controller.draftFor(_id(4))!.baseVersion, 'v2');
      expect(await controller.whenDraftsStored(), isTrue);
    });

    testWidgets('draftKey wins over the scopes', (tester) async {
      final controller = newController();
      final explicit = _id(1, table: 'other', field: 'f');
      await pumpTable(tester, controller, [
        row(7, [cell('x', draftKey: explicit)], version: 'v5'),
      ]);
      await edit(tester, 'x', 'new');
      await submit(tester);

      expect(controller.draftFor(explicit)!.baseVersion, 'v5');
      expect(controller.draftFor(_id(7)), isNull);
    });

    testWidgets('without a fieldId the key is the cell id, which a store '
        'does not take', (tester) async {
      final store = LazyTextFieldMemoryDraftStore();
      final controller = newController(store: store);
      captureErrors();
      await pumpTable(tester, controller, [
        row(7, [cell('x', fieldId: null)]),
      ]);
      await edit(tester, 'x', 'new');
      await submit(tester);

      expect(controller.draftFor('x')!.value, 'new');
      expect('${errors.single.exception}', contains('fieldId'));
      expect(store.drafts, isEmpty);
      expect(await controller.whenDraftsStored(), isFalse);
    });

    testWidgets('two tables with the same row and field never share a draft', (
      tester,
    ) async {
      final store = LazyTextFieldMemoryDraftStore();
      final controller = newController(store: store);
      await pumpTable(tableId: null, tester, controller, [
        for (final table in ['tasks', 'notes'])
          LazyTextFieldScope(
            controller: controller,
            tableId: table,
            child: row(1, [cell('$table-1')]),
          ),
      ]);
      await edit(tester, 'tasks-1', 'task text');
      await submit(tester);
      await edit(tester, 'notes-1', 'note text');
      await submit(tester);

      expect(controller.draftFor(_id(1))!.value, 'task text');
      expect(controller.draftFor(_id(1, table: 'notes'))!.value, 'note text');
      expect(await controller.whenDraftsStored(), isTrue);
      expect(
        store.drafts.keys,
        unorderedEquals(['tasks/1/title', 'notes/1/title']),
      );
    });
  });

  group('position-based cell ids', () {
    // Cell ids are positions; the row scope names the record.
    List<Widget> rows(List<int> order) => [
      for (var i = 0; i < order.length; i++)
        row(order[i], [
          cell('r$i', text: 'server-${order[i]}', label: '${order[i]}'),
        ]),
    ];

    testWidgets('a kept draft follows its record when rows are re-sorted', (
      tester,
    ) async {
      final controller = newController();
      await pumpTable(tester, controller, rows([5, 9]));
      await edit(tester, 'r0', 'mine-5');
      await submit(tester);
      expect(shown(tester, 'r0'), 'mine-5');

      await pumpTable(tester, controller, rows([9, 5]));
      expect(shown(tester, 'r0'), 'server-9');
      expect(shown(tester, 'r1'), 'mine-5');

      expect((await controller.saveDrafts()).saved, 1);
      expect(commits, [('5', 'mine-5')]);
    });

    testWidgets('an editor open while rows are re-sorted keeps its text for '
        'its own record', (tester) async {
      final controller = newController(
        saveMode: LazyTextFieldSaveMode.immediate,
      );
      await pumpTable(tester, controller, rows([5, 9]));
      await edit(tester, 'r0', 'typing-5');

      await pumpTable(tester, controller, rows([9, 5]));
      await tester.pump();
      expect(controller.isEditing('r0'), isFalse);
      expect(shown(tester, 'r0'), 'server-9');
      expect(shown(tester, 'r1'), 'typing-5');
      expect(controller.draftFor(_id(5))!.baseText, 'server-5');

      // Saved with row 5's own onCommit, never row 9's.
      await controller.saveDrafts();
      expect(commits, [('5', 'typing-5')]);
    });

    testWidgets('a restored draft goes back to its record', (tester) async {
      final store = LazyTextFieldMemoryDraftStore()
        ..put(
          LazyTextFieldStoredDraft(
            id: _id(5),
            value: 'restored-5',
            baseText: 'server-5',
            baseVersion: 'v1',
          ),
        );
      final controller = newController(store: store);
      expect(await controller.loadDrafts(), 1);

      // After the restart, row 5 is second in the list.
      await pumpTable(tester, controller, rows([9, 5]));
      expect(shown(tester, 'r0'), 'server-9');
      expect(shown(tester, 'r1'), 'restored-5');
    });
  });

  testWidgets('perRow saves each row scope in its own lane', (tester) async {
    final controller = newController(
      saveMode: LazyTextFieldSaveMode.immediate,
      saveOrder: LazyTextFieldSaveOrder.perRow,
    );
    await pumpTable(tester, controller, [
      row(1, [cell('a'), cell('c', fieldId: 'note')]),
      row(2, [cell('b')]),
    ]);
    gate = Completer<void>();

    await edit(tester, 'a', 'new-a');
    await edit(tester, 'b', 'new-b'); // a saves: row 1.
    await edit(tester, 'c', 'new-c'); // b saves: row 2, does not wait.
    await submit(tester); // c saves: row 1, waits for a.
    expect(started, ['a', 'b']);

    gate!.complete();
    await tester.pump();
    await tester.pump();
    expect(started, ['a', 'b', 'c']);
  });

  testWidgets('unsaved changes carry the version they started from', (
    tester,
  ) async {
    final controller = newController(saveMode: LazyTextFieldSaveMode.deferred);
    // Kept at v1; the records changed since: both are at v2 now.
    controller.holdDraft(
      key: _id(1),
      source: 'server-a',
      value: 'kept-1',
      version: 'v1',
      saver: (_) async => true,
    );
    await pumpTable(tester, controller, [
      row(1, [cell('a')], version: 'v2'),
      row(2, [cell('b')], version: 'v2'),
    ]);

    await edit(tester, 'b', 'new-b');
    var changes = {
      for (final change in controller.unsavedChanges()) change.key: change,
    };
    expect(changes[_id(1)]!.baseVersion, 'v1');
    expect(changes[_id(2)]!.baseVersion, 'v2');

    // An editor that continues the draft keeps the draft's base.
    await edit(tester, 'a', 'checked-a');
    changes = {
      for (final change in controller.unsavedChanges()) change.key: change,
    };
    expect(changes[_id(1)]!.isEditing, isTrue);
    expect(changes[_id(1)]!.baseVersion, 'v1');
  });

  test('a draft keeps the version of the first change', () {
    final controller = newController();
    void hold(String value, String version) => controller.holdDraft(
      key: _id(1),
      source: 'old',
      value: value,
      version: version,
      saver: (_) async => true,
    );

    hold('new', 'v1');
    hold('newer', 'v2');
    expect(controller.draftFor(_id(1))!.baseVersion, 'v1');

    controller.clearDraft(_id(1));
    hold('again', 'v2');
    expect(controller.draftFor(_id(1))!.baseVersion, 'v2');
  });

  testWidgets('open editor text without a version is not stored', (
    tester,
  ) async {
    final store = LazyTextFieldMemoryDraftStore();
    final controller = newController(store: store);
    captureErrors();
    await pumpTable(tester, controller, [
      row(1, [cell('a')], version: null),
    ]);
    await edit(tester, 'a', 'typed');
    controller.storeOpenEdits();

    expect(await controller.whenDraftsStored(), isFalse);
    expect('${errors.single.exception}', contains('has no version'));
    expect(store.drafts, isEmpty);

    // Escape: nothing is kept, so nothing is missing from the store.
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(await controller.whenDraftsStored(), isTrue);
  });
}
