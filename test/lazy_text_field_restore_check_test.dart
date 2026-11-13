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

LazyTextFieldDraftId _id(int row) =>
    LazyTextFieldDraftId(table: 'tasks', row: '$row', field: 'title');

/// A draft for row [row] in the store: the user typed [value] over
/// 'server-[row]' at v1, then the app was closed.
LazyTextFieldStoredDraft _stored(int row, {String? value}) =>
    LazyTextFieldStoredDraft(
      id: _id(row),
      value: value ?? 'mine-$row',
      baseText: 'server-$row',
      baseVersion: 'v1',
    );

/// A row as the server has it now.
typedef _Row = ({int id, String text, String? version});

void main() {
  late List<(int, String)> commits;
  late LazyTextFieldMemoryDraftStore store;
  late LazyTextFieldEditController controller;

  setUp(() => commits = []);

  /// A controller that restored [drafts] from the store, as after a
  /// restart.
  Future<void> restart(
    List<LazyTextFieldStoredDraft> drafts, {
    LazyTextFieldSaveMode saveMode = LazyTextFieldSaveMode.deferred,
  }) async {
    store = LazyTextFieldMemoryDraftStore();
    drafts.forEach(store.put);
    controller = LazyTextFieldEditController(
      saveMode: saveMode,
      draftStore: store,
    );
    addTearDown(controller.dispose);
    expect(await controller.loadDrafts(), drafts.length);
  }

  Future<void> pumpRows(WidgetTester tester, List<_Row> rows) =>
      tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: LazyTextFieldScope(
                controller: controller,
                tableId: 'tasks',
                child: Column(
                  children: [
                    for (final row in rows)
                      LazyTextFieldScope.row(
                        rowId: row.id,
                        version: row.version,
                        child: SizedBox(
                          width: 300,
                          child: ScopedLazyTextField(
                            cellId: 'r${row.id}',
                            fieldId: 'title',
                            text: row.text,
                            singleLine: true,
                            style: _style,
                            decoration: const InputDecoration(
                              border: InputBorder.none,
                              isCollapsed: true,
                              contentPadding: EdgeInsets.all(4),
                            ),
                            onCommit: (value) async =>
                                commits.add((row.id, value)),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );

  String shown(WidgetTester tester, int row) => tester
      .widget<LazyTextField>(
        find.byWidgetPredicate(
          (w) => w is LazyTextField && w.cellId == 'r$row',
        ),
      )
      .text;

  Future<void> open(WidgetTester tester, int row) async {
    await tester.tap(find.byKey(LazyTextFieldKeys.staticSurface('r$row')));
    await tester.pump();
    await tester.pump();
  }

  Future<void> press(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.sendKeyEvent(key);
    await tester.pump();
    await tester.pump();
  }

  LazyTextFieldDraft? draft(int row) => controller.draftFor(_id(row));

  group('a restored draft, when its cell builds', () {
    testWidgets('is shown when the version matches', (tester) async {
      await restart([_stored(1)]);
      expect(draft(1)!.verified, isFalse);

      await pumpRows(tester, [(id: 1, text: 'server-1', version: 'v1')]);
      expect(shown(tester, 1), 'mine-1');
      expect(draft(1)!.status, LazyTextFieldDraftStatus.unsaved);
      expect(draft(1)!.verified, isTrue);
      expect(draft(1)!.restored, isTrue);

      final result = await controller.saveDrafts();
      expect(result.saved, 1);
      expect(commits, [(1, 'mine-1')]);
    });

    testWidgets('is a conflict when the field changed since', (tester) async {
      await restart([_stored(1)]);
      await pumpRows(tester, [(id: 1, text: 'theirs', version: 'v2')]);

      // The server value is shown; the draft is kept, in the store too.
      expect(shown(tester, 1), 'theirs');
      expect(draft(1)!.status, LazyTextFieldDraftStatus.conflict);
      expect(draft(1)!.value, 'mine-1');
      expect(
        draft(1)!.conflict,
        const LazyTextFieldConflict(serverText: 'theirs', serverVersion: 'v2'),
      );
      expect(await controller.whenDraftsStored(), isTrue);
      expect(store.drafts[_id(1).storeKey], _stored(1));

      Map<Object, String>? sent;
      final result = await controller.saveDrafts(
        batch: (values) async {
          sent = values;
          return {};
        },
      );
      expect(sent, isNull);
      expect(result.conflicts, 1);
      expect(result.allSaved, isFalse);
      expect(draft(1)!.status, LazyTextFieldDraftStatus.conflict);
    });

    testWidgets('is rebased when only the version changed (another field of '
        'the row)', (tester) async {
      await restart([_stored(1)]);
      await pumpRows(tester, [(id: 1, text: 'server-1', version: 'v2')]);

      expect(shown(tester, 1), 'mine-1');
      expect(draft(1)!.status, LazyTextFieldDraftStatus.unsaved);
      expect(draft(1)!.baseVersion, 'v2');
      expect(await controller.whenDraftsStored(), isTrue);
      expect(store.drafts[_id(1).storeKey]!.baseVersion, 'v2');
    });

    testWidgets('is dropped when the record already has it', (tester) async {
      await restart([_stored(1)]);
      await pumpRows(tester, [(id: 1, text: 'mine-1', version: 'v2')]);

      expect(shown(tester, 1), 'mine-1');
      expect(draft(1), isNull);
      expect(await controller.whenDraftsStored(), isTrue);
      expect(store.drafts, isEmpty);
    });

    testWidgets('without a version, compares the text', (tester) async {
      await restart([_stored(1), _stored(2)]);
      await pumpRows(tester, [
        (id: 1, text: 'server-1', version: null),
        (id: 2, text: 'theirs', version: null),
      ]);

      expect(shown(tester, 1), 'mine-1');
      expect(draft(1)!.status, LazyTextFieldDraftStatus.unsaved);
      // Kept: the store needs a version.
      expect(draft(1)!.baseVersion, 'v1');
      expect(shown(tester, 2), 'theirs');
      expect(
        draft(2)!.conflict,
        const LazyTextFieldConflict(serverText: 'theirs'),
      );
    });

    testWidgets('is checked again when the record changes later', (
      tester,
    ) async {
      await restart([_stored(1)]);
      await pumpRows(tester, [(id: 1, text: 'server-1', version: 'v1')]);
      expect(shown(tester, 1), 'mine-1');

      await pumpRows(tester, [(id: 1, text: 'theirs', version: 'v2')]);
      expect(shown(tester, 1), 'theirs');
      expect(draft(1)!.status, LazyTextFieldDraftStatus.conflict);
    });

    testWidgets('notifies listeners after the frame', (tester) async {
      await restart([_stored(1)]);
      var notified = 0;
      controller.addListener(() => notified++);

      await pumpRows(tester, [(id: 1, text: 'theirs', version: 'v2')]);
      expect(notified, 1);
      expect(controller.hasUnsavedChanges, isTrue);
      final change = controller.unsavedChanges().single;
      expect(change.status, LazyTextFieldDraftStatus.conflict);
      expect(change.value, 'mine-1');
    });
  });

  group('a conflict', () {
    Future<void> conflictIn(
      WidgetTester tester, {
      LazyTextFieldSaveMode? mode,
    }) async {
      await restart([
        _stored(1),
      ], saveMode: mode ?? LazyTextFieldSaveMode.deferred);
      await pumpRows(tester, [
        (id: 1, text: 'theirs', version: 'v2'),
        (id: 2, text: 'server-2', version: 'v1'),
      ]);
      expect(draft(1)!.status, LazyTextFieldDraftStatus.conflict);
    }

    testWidgets('is not saved when another cell starts editing', (
      tester,
    ) async {
      await conflictIn(tester, mode: LazyTextFieldSaveMode.immediate);
      await open(tester, 2);
      await tester.enterText(find.byType(EditableText), 'new-2');
      await press(tester, LogicalKeyboardKey.enter);

      expect(commits, [(2, 'new-2')]);
      expect(draft(1)!.status, LazyTextFieldDraftStatus.conflict);
    });

    testWidgets('rebaseDraft keeps the draft on top of the server value', (
      tester,
    ) async {
      await conflictIn(tester);
      expect(controller.rebaseDraft(_id(1)), isTrue);
      await tester.pump();

      expect(shown(tester, 1), 'mine-1');
      expect(draft(1)!.status, LazyTextFieldDraftStatus.unsaved);
      expect(draft(1)!.baseText, 'theirs');
      expect(draft(1)!.baseVersion, 'v2');
      expect(draft(1)!.conflict, isNull);
      // Not saved until asked.
      expect(commits, isEmpty);
      expect(controller.rebaseDraft(_id(1)), isFalse);

      await controller.saveDrafts();
      expect(commits, [(1, 'mine-1')]);
    });

    testWidgets('clearDraft keeps the server value', (tester) async {
      await conflictIn(tester);
      controller.clearDraft(_id(1));
      await tester.pump();

      expect(shown(tester, 1), 'theirs');
      expect(draft(1), isNull);
      expect(await controller.whenDraftsStored(), isTrue);
      expect(store.drafts, isEmpty);
    });

    testWidgets('opens its cell on the server value; Escape keeps it', (
      tester,
    ) async {
      await conflictIn(tester);
      await open(tester, 1);
      expect(controller.controllerFor('r1')!.text, 'theirs');
      // Unchanged: the conflict stays the only entry for the key.
      expect(controller.unsavedChanges().single.isEditing, isFalse);

      await press(tester, LogicalKeyboardKey.escape);
      expect(controller.isEditing('r1'), isFalse);
      expect(draft(1)!.status, LazyTextFieldDraftStatus.conflict);
    });

    testWidgets('is replaced by a value committed from its cell, based on the '
        'server value', (tester) async {
      await conflictIn(tester);
      await open(tester, 1);
      await tester.enterText(find.byType(EditableText), 'fresh');
      await tester.pump();
      final change = controller.unsavedChanges().single;
      expect(change.isEditing, isTrue);
      expect(change.baseText, 'theirs');
      expect(change.baseVersion, 'v2');

      await press(tester, LogicalKeyboardKey.enter);
      expect(draft(1)!.value, 'fresh');
      expect(draft(1)!.status, LazyTextFieldDraftStatus.unsaved);
      expect(draft(1)!.restored, isFalse);
      expect(draft(1)!.baseText, 'theirs');
      expect(draft(1)!.baseVersion, 'v2');
    });
  });

  group('reconcileDrafts', () {
    testWidgets('checks drafts whose rows are not on screen', (tester) async {
      await restart([
        _stored(1),
        _stored(2),
        _stored(3),
        _stored(4),
        _stored(5),
      ]);
      var notified = 0;
      controller
        ..addListener(() => notified++)
        ..reconcileDrafts({
          _id(1): const LazyTextFieldServerValue('server-1', version: 'v1'),
          _id(2): const LazyTextFieldServerValue('theirs', version: 'v2'),
          _id(3): null,
          _id(4): const LazyTextFieldServerValue('mine-4', version: 'v2'),
          _id(9): const LazyTextFieldServerValue('no draft'),
        });
      expect(notified, 1);

      expect(draft(1)!.verified, isTrue);
      expect(draft(1)!.status, LazyTextFieldDraftStatus.unsaved);
      expect(draft(2)!.status, LazyTextFieldDraftStatus.conflict);
      expect(draft(3)!.status, LazyTextFieldDraftStatus.conflict);
      expect(draft(3)!.conflict!.isDeleted, isTrue);
      expect(controller.rebaseDraft(_id(3)), isFalse);
      expect(draft(4), isNull);
      // Not in the map: still unverified.
      expect(draft(5)!.verified, isFalse);
      expect(controller.drafts.containsKey(_id(9)), isFalse);

      Map<Object, String>? sent;
      final result = await controller.saveDrafts(
        batch: (values) async {
          sent = values;
          return {};
        },
      );
      expect(sent, {_id(1): 'mine-1'});
      expect(result.saved, 1);
      expect(result.conflicts, 2);
      expect(result.unverified, 1);
      expect(result.remaining, 3);
      expect(result.allSaved, isFalse);
    });

    testWidgets('leaves drafts kept in this session alone', (tester) async {
      await restart([]);
      controller
        ..holdDraft(
          key: _id(1),
          source: 'server-1',
          value: 'typed',
          version: 'v1',
          saver: (_) async => true,
        )
        ..reconcileDrafts({
          _id(1): const LazyTextFieldServerValue('theirs', version: 'v2'),
        });
      expect(draft(1)!.status, LazyTextFieldDraftStatus.unsaved);
      expect(draft(1)!.verified, isTrue);
    });

    testWidgets('without it, unverified drafts are left out of Save all', (
      tester,
    ) async {
      await restart([_stored(1)]);
      final result = await controller.saveDrafts();
      expect(result.unverified, 1);
      expect(result.skipped, 0);
      expect(result.allSaved, isFalse);
      expect(commits, isEmpty);
    });
  });
}
