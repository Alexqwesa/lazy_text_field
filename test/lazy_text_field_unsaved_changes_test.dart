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

/// The draft id of cell [id]: field `text` of row [id] in table `tasks`.
LazyTextFieldDraftId _id(String id) =>
    LazyTextFieldDraftId(table: 'tasks', row: id, field: 'text');

String _key(String id) => _id(id).storeKey;

void main() {
  late LazyTextFieldEditController controller;
  late LazyTextFieldMemoryDraftStore store;
  late Set<String> failing;

  setUp(() {
    store = LazyTextFieldMemoryDraftStore();
    failing = {};
  });

  LazyTextFieldEditController newController({
    bool withStore = false,
    Duration? storeOpenEditsAfter,
  }) {
    final created = LazyTextFieldEditController(
      draftStore: withStore ? store : null,
      storeOpenEditsAfter: storeOpenEditsAfter,
    );
    addTearDown(created.dispose);
    return created;
  }

  Future<void> pumpCells(WidgetTester tester) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: LazyTextFieldControllerScope(
            controller: controller,
            child: Column(
              children: [
                for (final id in ['a', 'b'])
                  SizedBox(
                    width: 200,
                    child: ScopedLazyTextField(
                      cellId: id,
                      draftKey: _id(id),
                      version: 'v1',
                      text: 'old-$id',
                      singleLine: true,
                      style: _style,
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        isCollapsed: true,
                        contentPadding: EdgeInsets.all(4),
                      ),
                      onCommit: (value) async {
                        if (failing.contains(id)) throw 'rejected $id';
                      },
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  Future<void> open(WidgetTester tester, String id) async {
    await tester.tap(find.byKey(LazyTextFieldKeys.staticSurface(id)));
    await tester.pump();
    await tester.pump();
  }

  Future<void> type(WidgetTester tester, String text) async {
    await tester.enterText(find.byType(EditableText), text);
    await tester.pump();
  }

  Future<void> press(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.sendKeyEvent(key);
    await tester.pump();
    await tester.pump();
  }

  group('unsavedChanges', () {
    testWidgets('lists an open editor once its text changes', (tester) async {
      controller = newController();
      await pumpCells(tester);
      await open(tester, 'a');
      expect(controller.unsavedChanges(), isEmpty);
      expect(controller.hasUnsavedChanges, isFalse);

      await type(tester, 'new-a');
      final change = controller.unsavedChanges().single;
      expect(change.key, _id('a'));
      expect(change.value, 'new-a');
      expect(change.baseText, 'old-a');
      expect(change.baseVersion, 'v1');
      expect(change.isEditing, isTrue);
      expect(change.cellId, 'a');
      expect(change.status, isNull);
      expect(controller.hasUnsavedChanges, isTrue);
    });

    testWidgets('notifies on the first change and on a revert only', (
      tester,
    ) async {
      controller = newController();
      await pumpCells(tester);
      await open(tester, 'a');
      var notified = 0;
      controller.addListener(() => notified++);

      await type(tester, 'n');
      await type(tester, 'ne');
      await type(tester, 'new');
      expect(notified, 1);

      await type(tester, 'old-a');
      expect(notified, 2);
      expect(controller.hasUnsavedChanges, isFalse);
    });

    testWidgets('lists drafts and open editors together', (tester) async {
      controller = newController();
      failing.add('a');
      await pumpCells(tester);
      await open(tester, 'a');
      await type(tester, 'new-a');
      // Switching closes a; its save fails and leaves a failed draft.
      await open(tester, 'b');
      await tester.pump();
      expect(
        controller.draftFor(_id('a'))?.status,
        LazyTextFieldDraftStatus.failed,
      );
      await type(tester, 'new-b');

      final changes = {
        for (final change in controller.unsavedChanges()) change.key: change,
      };
      expect(changes.keys, unorderedEquals([_id('a'), _id('b')]));
      expect(changes[_id('a')]!.status, LazyTextFieldDraftStatus.failed);
      expect(changes[_id('a')]!.isEditing, isFalse);
      expect(changes[_id('a')]!.value, 'new-a');
      expect(changes[_id('b')]!.isEditing, isTrue);
      expect(changes[_id('b')]!.status, isNull);
    });

    testWidgets('an editor continuing a draft has its text and the draft', (
      tester,
    ) async {
      controller = newController();
      failing.add('a');
      await pumpCells(tester);
      await open(tester, 'a');
      await type(tester, 'new-a');
      await open(tester, 'b');
      await tester.pump();
      await open(tester, 'a');
      await type(tester, 'newer-a');

      final change = controller.unsavedChanges().single;
      expect(change.value, 'newer-a');
      expect(change.baseText, 'old-a');
      expect(change.isEditing, isTrue);
      expect(change.status, LazyTextFieldDraftStatus.failed);
    });

    testWidgets('a saved edit is no longer listed', (tester) async {
      controller = newController();
      await pumpCells(tester);
      await open(tester, 'a');
      await type(tester, 'new-a');
      await press(tester, LogicalKeyboardKey.enter);
      await tester.pump();

      expect(controller.unsavedChanges(), isEmpty);
      expect(controller.hasUnsavedChanges, isFalse);
    });
  });

  group('storeOpenEdits', () {
    testWidgets('writes open text to the store without saving it', (
      tester,
    ) async {
      controller = newController(withStore: true);
      await pumpCells(tester);
      await open(tester, 'a');
      await type(tester, 'typed');

      controller.storeOpenEdits();
      expect(await controller.whenDraftsStored(), isTrue);
      expect(store.drafts[_key('a')]?.value, 'typed');
      expect(store.drafts[_key('a')]?.baseText, 'old-a');
      expect(store.drafts[_key('a')]?.baseVersion, 'v1');
      expect(controller.draftFor(_id('a')), isNull);
      expect(controller.isEditing('a'), isTrue);
    });

    testWidgets('text stored from an open editor comes back after a '
        'restart', (tester) async {
      controller = newController(withStore: true);
      await pumpCells(tester);
      await open(tester, 'a');
      await type(tester, 'typed');
      controller.storeOpenEdits();
      await controller.whenDraftsStored();

      // The app was killed with the editor open: a new controller loads.
      final restarted = LazyTextFieldEditController(draftStore: store);
      addTearDown(restarted.dispose);
      expect(await restarted.loadDrafts(), 1);
      expect(restarted.draftFor(_id('a'))?.value, 'typed');
      expect(restarted.draftFor(_id('a'))?.baseVersion, 'v1');
      expect(restarted.draftFor(_id('a'))?.restored, isTrue);
    });

    testWidgets('Escape removes the stored open text', (tester) async {
      controller = newController(withStore: true);
      await pumpCells(tester);
      await open(tester, 'a');
      await type(tester, 'typed');
      controller.storeOpenEdits();
      await controller.whenDraftsStored();

      await press(tester, LogicalKeyboardKey.escape);
      expect(await controller.whenDraftsStored(), isTrue);
      expect(store.drafts, isEmpty);
    });

    testWidgets('a save removes the stored open text', (tester) async {
      controller = newController(withStore: true);
      await pumpCells(tester);
      await open(tester, 'a');
      await type(tester, 'typed');
      controller.storeOpenEdits();
      await controller.whenDraftsStored();

      await press(tester, LogicalKeyboardKey.enter);
      await tester.pump();
      expect(await controller.whenDraftsStored(), isTrue);
      expect(store.drafts, isEmpty);
    });

    testWidgets('a failed save leaves the draft in the store', (tester) async {
      controller = newController(withStore: true);
      failing.add('a');
      await pumpCells(tester);
      await open(tester, 'a');
      await type(tester, 'typed');
      controller.storeOpenEdits();
      await press(tester, LogicalKeyboardKey.enter);
      await tester.pump();

      expect(await controller.whenDraftsStored(), isTrue);
      expect(store.drafts[_key('a')]?.value, 'typed');
    });

    testWidgets('an editor reverted to its start text is removed again', (
      tester,
    ) async {
      controller = newController(withStore: true);
      await pumpCells(tester);
      await open(tester, 'a');
      await type(tester, 'typed');
      controller.storeOpenEdits();
      await type(tester, 'old-a');
      controller.storeOpenEdits();

      expect(await controller.whenDraftsStored(), isTrue);
      expect(store.drafts, isEmpty);
    });

    testWidgets('storeOpenEditsAfter writes after the last keystroke', (
      tester,
    ) async {
      controller = newController(
        withStore: true,
        storeOpenEditsAfter: const Duration(seconds: 1),
      );
      await pumpCells(tester);
      await open(tester, 'a');
      await type(tester, 'typ');
      await tester.pump(const Duration(milliseconds: 600));
      await type(tester, 'typed');
      await tester.pump(const Duration(milliseconds: 600));
      await controller.whenDraftsStored();
      expect(store.drafts, isEmpty);

      await tester.pump(const Duration(milliseconds: 500));
      await controller.whenDraftsStored();
      expect(store.drafts[_key('a')]?.value, 'typed');
    });
  });
}
