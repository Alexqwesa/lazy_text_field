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

void main() {
  late List<(String, String)> commits;
  late Set<String> failing;
  late List<String> saved;
  late List<(int, int)> settled;
  Completer<void>? gate;

  setUp(() {
    commits = [];
    failing = {};
    saved = [];
    settled = [];
    gate = null;
  });

  LazyTextFieldEditController newController({
    LazyTextFieldSaveMode saveMode = LazyTextFieldSaveMode.deferred,
    LazyTextFieldDraftStore? store,
  }) {
    final controller = LazyTextFieldEditController(
      saveMode: saveMode,
      draftStore: store,
      onSavesSettled: (saved, failed) => settled.add((saved, failed)),
    );
    addTearDown(controller.dispose);
    return controller;
  }

  Future<void> pumpCells(
    WidgetTester tester,
    LazyTextFieldEditController controller, {
    List<String> ids = const ['a', 'b', 'c'],
    LazyTextFieldSave? onSave,
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
                  for (final id in ids)
                    SizedBox(
                      width: 300,
                      child: ScopedLazyTextField(
                        cellId: id,
                        text: 'old-$id',
                        singleLine: true,
                        style: _style,
                        decoration: const InputDecoration(
                          border: InputBorder.none,
                          isCollapsed: true,
                          contentPadding: EdgeInsets.all(4),
                        ),
                        onSave: onSave,
                        onCommit: onSave != null
                            ? null
                            : (value) async {
                                commits.add((id, value));
                                await gate?.future;
                                if (failing.contains(id)) throw 'rejected $id';
                              },
                        onSaved: saved.add,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
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

  Future<void> edit(WidgetTester tester, String id, String text) async {
    await open(tester, id);
    await tester.enterText(find.byType(EditableText), text);
  }

  Future<void> submit(WidgetTester tester) async {
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
  }

  LazyTextFieldDraftStatus? status(
    LazyTextFieldEditController controller,
    String key,
  ) => controller.draftFor(key)?.status;

  group('deferred mode', () {
    testWidgets('submit and switch keep unsaved drafts without saving', (
      tester,
    ) async {
      final controller = newController();
      await pumpCells(tester, controller);
      await edit(tester, 'a', 'new-a');
      await submit(tester);
      expect(controller.isEditing('a'), isFalse);

      await edit(tester, 'b', 'new-b');
      await open(tester, 'c');
      await tester.pump();

      expect(commits, isEmpty);
      expect(saved, isEmpty);
      expect(status(controller, 'a'), LazyTextFieldDraftStatus.unsaved);
      expect(status(controller, 'b'), LazyTextFieldDraftStatus.unsaved);
      expect(shown(tester, 'a'), 'new-a');
      expect(shown(tester, 'b'), 'new-b');
      expect(controller.pendingSaves, 0);
    });

    testWidgets('saveDrafts saves every unsaved draft through its cell', (
      tester,
    ) async {
      final controller = newController();
      await pumpCells(tester, controller);
      await edit(tester, 'a', 'new-a');
      await edit(tester, 'b', 'new-b');
      await submit(tester);

      final result = await controller.saveDrafts();
      await tester.pump();
      expect(result.saved, 2);
      expect(result.allSaved, isTrue);
      expect(commits, [('a', 'new-a'), ('b', 'new-b')]);
      expect(saved, ['new-a', 'new-b']);
      expect(status(controller, 'a'), LazyTextFieldDraftStatus.saved);
      expect(status(controller, 'b'), LazyTextFieldDraftStatus.saved);
      expect(settled, [(2, 0)]);
      expect(shown(tester, 'a'), 'new-a');
    });

    testWidgets('saveDrafts retries failed drafts', (tester) async {
      final controller = newController();
      await pumpCells(tester, controller);
      failing.add('a');
      await edit(tester, 'a', 'new-a');
      await submit(tester);

      var result = await controller.saveDrafts();
      expect(result.failed, 1);
      expect(status(controller, 'a'), LazyTextFieldDraftStatus.failed);
      expect(controller.draftFor('a')!.error, 'rejected a');

      failing.clear();
      result = await controller.saveDrafts();
      expect(result.saved, 1);
      expect(status(controller, 'a'), LazyTextFieldDraftStatus.saved);
    });

    testWidgets('a batch saves all drafts in one call', (tester) async {
      final controller = newController();
      await pumpCells(tester, controller);
      await edit(tester, 'a', 'new-a');
      await edit(tester, 'b', 'new-b');
      await submit(tester);

      final request = Completer<Map<Object, Object?>>();
      Map<Object, String>? sent;
      final result = controller.saveDrafts(
        batch: (values) {
          sent = values;
          return request.future;
        },
      );
      await tester.pump();
      expect(sent, {'a': 'new-a', 'b': 'new-b'});
      expect(status(controller, 'a'), LazyTextFieldDraftStatus.pending);
      expect(controller.pendingSaves, 2);

      request.complete({'b': 'duplicate'});
      final outcome = await result;
      expect(outcome.saved, 1);
      expect(outcome.failed, 1);
      expect(status(controller, 'a'), LazyTextFieldDraftStatus.saved);
      expect(status(controller, 'b'), LazyTextFieldDraftStatus.failed);
      expect(controller.draftFor('b')!.error, 'duplicate');
      expect(commits, isEmpty);
      expect(settled, [(1, 1)]);
    });

    testWidgets('a batch that throws fails every draft', (tester) async {
      final controller = newController();
      await pumpCells(tester, controller);
      await edit(tester, 'a', 'new-a');
      await submit(tester);

      final result = await controller.saveDrafts(
        batch: (_) async => throw 'offline',
      );
      expect(result.failed, 1);
      expect(status(controller, 'a'), LazyTextFieldDraftStatus.failed);
      expect(controller.draftFor('a')!.error, 'offline');
    });

    testWidgets('reopening a draft continues it; Escape discards it', (
      tester,
    ) async {
      final controller = newController();
      await pumpCells(tester, controller);
      await edit(tester, 'a', 'new-a');
      await submit(tester);

      await open(tester, 'a');
      expect(
        tester.widget<EditableText>(find.byType(EditableText)).controller.text,
        'new-a',
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(controller.draftFor('a'), isNull);
      expect(shown(tester, 'a'), 'old-a');
    });

    testWidgets('onSave cells still save on submit', (tester) async {
      final controller = newController();
      final saves = <String>[];
      await pumpCells(
        tester,
        controller,
        onSave: (value) {
          saves.add(value);
          return true;
        },
      );
      await edit(tester, 'a', 'new-a');
      await submit(tester);
      await tester.pump();
      expect(saves, ['new-a']);
      expect(saved, ['new-a']);
    });

    testWidgets('saveDrafts commits open editors first', (tester) async {
      final controller = newController();
      await pumpCells(tester, controller);
      await edit(tester, 'a', 'new-a');
      expect(controller.isEditing('a'), isTrue);

      final result = await controller.saveDrafts();
      await tester.pump();
      expect(result.saved, 1);
      expect(result.allSaved, isTrue);
      expect(commits, [('a', 'new-a')]);
      expect(controller.isEditing('a'), isFalse);
      expect(shown(tester, 'a'), 'new-a');
    });

    testWidgets('includeOpenEdits: false leaves open editors alone', (
      tester,
    ) async {
      final controller = newController();
      await pumpCells(tester, controller);
      await edit(tester, 'a', 'new-a');
      final result = await controller.saveDrafts(includeOpenEdits: false);
      expect(result.saved, 0);
      expect(commits, isEmpty);
      expect(controller.isEditing('a'), isTrue);
    });

    testWidgets('onSaved runs for a draft whose cell left the tree', (
      tester,
    ) async {
      final controller = newController();
      await pumpCells(tester, controller);
      await edit(tester, 'a', 'new-a');
      await submit(tester);
      await pumpCells(tester, controller, ids: ['b', 'c']);

      final result = await controller.saveDrafts();
      expect(result.saved, 1);
      expect(commits, [('a', 'new-a')]);
      expect(saved, ['new-a']);
    });

    testWidgets('a batch does not call onSaved', (tester) async {
      final controller = newController();
      await pumpCells(tester, controller);
      await edit(tester, 'a', 'new-a');
      await submit(tester);
      final result = await controller.saveDrafts(batch: (_) async => {});
      expect(result.saved, 1);
      expect(saved, isEmpty);
    });

    testWidgets('a change during a batch is reported as remaining', (
      tester,
    ) async {
      final controller = newController();
      await pumpCells(tester, controller);
      await edit(tester, 'a', 'new-a');
      await submit(tester);

      final request = Completer<Map<Object, Object?>>();
      final result = controller.saveDrafts(batch: (_) => request.future);
      await tester.pump();
      await edit(tester, 'a', 'newer-a');
      await submit(tester);
      request.complete({});

      final outcome = await result;
      expect(outcome.saved, 1);
      expect(outcome.remaining, 1);
      expect(outcome.allSaved, isFalse);
      expect(status(controller, 'a'), LazyTextFieldDraftStatus.unsaved);
      expect(controller.draftFor('a')!.value, 'newer-a');
    });

    testWidgets('saveDrafts with nothing to save returns at once', (
      tester,
    ) async {
      final controller = newController();
      final result = await controller.saveDrafts();
      expect(result.saved + result.failed + result.skipped, 0);
      expect(result.allSaved, isTrue);
    });
  });

  group('saveDrafts and saves already running', () {
    testWidgets('waits for them and reports a failure as remaining', (
      tester,
    ) async {
      final controller = newController(
        saveMode: LazyTextFieldSaveMode.immediate,
      );
      await pumpCells(tester, controller);
      gate = Completer<void>();
      failing.add('a');
      await edit(tester, 'a', 'new-a');
      await open(tester, 'b');
      expect(status(controller, 'a'), LazyTextFieldDraftStatus.pending);

      var done = false;
      final result = controller.saveDrafts().then((r) {
        done = true;
        return r;
      });
      await tester.pump();
      expect(done, isFalse);

      gate!.complete();
      final outcome = await result;
      expect(outcome.saved + outcome.failed, 0);
      expect(outcome.remaining, 1);
      expect(outcome.allSaved, isFalse);
      expect(status(controller, 'a'), LazyTextFieldDraftStatus.failed);
    });

    testWidgets('is all saved once they succeed', (tester) async {
      final controller = newController(
        saveMode: LazyTextFieldSaveMode.immediate,
      );
      await pumpCells(tester, controller);
      gate = Completer<void>();
      await edit(tester, 'a', 'new-a');
      await open(tester, 'b');

      final result = controller.saveDrafts(includeOpenEdits: false);
      await tester.pump();
      gate!.complete();
      final outcome = await result;
      expect(outcome.allSaved, isTrue);
      expect(controller.pendingSaves, 0);
      expect(saved, ['new-a']);
    });

    testWidgets('waits for onSave submits too', (tester) async {
      final controller = newController(
        saveMode: LazyTextFieldSaveMode.immediate,
      );
      final slow = Completer<bool>();
      await pumpCells(tester, controller, onSave: (_) => slow.future);
      await edit(tester, 'a', 'new-a');
      await submit(tester);

      var done = false;
      unawaited(
        controller.saveDrafts(includeOpenEdits: false).then((_) => done = true),
      );
      await tester.pump();
      expect(done, isFalse);
      slow.complete(true);
      await tester.pump();
      await tester.pump();
      expect(done, isTrue);
    });
  });

  group('draft store', () {
    testWidgets('writes unsaved and failed drafts and deletes saved ones', (
      tester,
    ) async {
      final store = LazyTextFieldMemoryDraftStore();
      final controller = newController(store: store);
      await pumpCells(tester, controller);
      await edit(tester, 'a', 'new-a');
      await edit(tester, 'b', 'new-b');
      await submit(tester);
      await tester.pump();

      expect(store.drafts.keys, unorderedEquals(['a', 'b']));
      expect(
        store.drafts['a'],
        const LazyTextFieldStoredDraft(
          key: 'a',
          value: 'new-a',
          baseText: 'old-a',
        ),
      );

      failing.add('b');
      await controller.saveDrafts();
      await tester.pump();
      expect(store.drafts.keys, ['b']);

      controller.clearDraft('b');
      await tester.pump();
      expect(store.drafts, isEmpty);
    });

    testWidgets('disposing the controller keeps stored drafts', (tester) async {
      final store = LazyTextFieldMemoryDraftStore();
      final controller = LazyTextFieldEditController(
        saveMode: LazyTextFieldSaveMode.deferred,
        draftStore: store,
      );
      controller.holdDraft(
        key: 'a',
        source: 'old',
        value: 'new',
        saver: (_) async => true,
      );
      await tester.pump();
      controller.dispose();
      await tester.pump();
      expect(store.drafts.keys, ['a']);
    });

    testWidgets('loadDrafts restores drafts that cells show and save', (
      tester,
    ) async {
      final store = LazyTextFieldMemoryDraftStore()
        ..put(
          const LazyTextFieldStoredDraft(
            key: 'a',
            value: 'restored',
            baseText: 'old-a',
          ),
        );
      final controller = newController(store: store);
      expect(await controller.loadDrafts(), 1);
      expect(status(controller, 'a'), LazyTextFieldDraftStatus.unsaved);

      await pumpCells(tester, controller);
      expect(shown(tester, 'a'), 'restored');

      final result = await controller.saveDrafts();
      await tester.pump();
      expect(result.saved, 1);
      expect(commits, [('a', 'restored')]);
      expect(store.drafts, isEmpty);
    });

    testWidgets('restored drafts without a cell are skipped, batches save '
        'them', (tester) async {
      final store = LazyTextFieldMemoryDraftStore()
        ..put(
          const LazyTextFieldStoredDraft(
            key: 'gone',
            value: 'restored',
            baseText: 'old',
          ),
        );
      final controller = newController(store: store);
      await controller.loadDrafts();

      var result = await controller.saveDrafts();
      expect(result.skipped, 1);
      expect(result.allSaved, isFalse);

      result = await controller.saveDrafts(batch: (_) async => {});
      await tester.pump();
      expect(result.saved, 1);
      expect(store.drafts, isEmpty);
    });

    testWidgets('drafts in memory win over stored ones', (tester) async {
      final store = LazyTextFieldMemoryDraftStore()
        ..put(
          const LazyTextFieldStoredDraft(
            key: 'a',
            value: 'stored',
            baseText: 'old',
          ),
        );
      final controller = newController(store: store);
      controller.holdDraft(
        key: 'a',
        source: 'old',
        value: 'newer',
        saver: (_) async => true,
      );
      expect(await controller.loadDrafts(), 0);
      expect(controller.draftFor('a')!.value, 'newer');
    });

    test('a non-String key is reported and kept in memory only', () async {
      final store = LazyTextFieldMemoryDraftStore();
      final controller = LazyTextFieldEditController(draftStore: store);
      addTearDown(controller.dispose);
      final errors = <FlutterErrorDetails>[];
      final previous = FlutterError.onError;
      FlutterError.onError = errors.add;
      addTearDown(() => FlutterError.onError = previous);

      void hold(String value) => controller.holdDraft(
        key: 1,
        source: 'old',
        value: value,
        saver: (_) async => true,
      );
      hold('new');
      hold('newer');

      expect(errors, hasLength(1));
      expect(errors.single.exception, isArgumentError);
      expect(store.drafts, isEmpty);
      expect(controller.draftFor(1)!.value, 'newer');
      expect(await controller.whenDraftsStored(), isFalse);

      controller.clearDraft(1);
      expect(await controller.whenDraftsStored(), isTrue);
    });

    testWidgets('failed writes are tracked and retried by whenDraftsStored', (
      tester,
    ) async {
      final store = _FlakyStore()..failures = 1;
      final controller = newController(store: store);
      final errors = <FlutterErrorDetails>[];
      final previous = FlutterError.onError;
      FlutterError.onError = errors.add;
      addTearDown(() => FlutterError.onError = previous);

      controller.holdDraft(
        key: 'a',
        source: 'old',
        value: 'new',
        saver: (_) async => true,
      );
      await tester.pump();
      expect(controller.draftStoreErrors.keys, ['a']);
      expect(errors, hasLength(1));
      expect(store.drafts, isEmpty);

      expect(await controller.whenDraftsStored(), isTrue);
      expect(controller.draftStoreErrors, isEmpty);
      expect(store.drafts.keys, ['a']);
    });

    testWidgets('whenDraftsStored reports a store that keeps failing', (
      tester,
    ) async {
      final store = _FlakyStore()..failures = 100;
      final controller = newController(store: store);
      final previous = FlutterError.onError;
      FlutterError.onError = (_) {};
      addTearDown(() => FlutterError.onError = previous);

      controller.holdDraft(
        key: 'a',
        source: 'old',
        value: 'new',
        saver: (_) async => true,
      );
      expect(await controller.whenDraftsStored(), isFalse);
      expect(controller.draftStoreErrors.keys, ['a']);
    });

    testWidgets('a delete after a failed put is still sent', (tester) async {
      final store = _FlakyStore()
        ..drafts['a'] = const LazyTextFieldStoredDraft(
          key: 'a',
          value: 'older',
          baseText: 'old',
        )
        ..failures = 1;
      final controller = newController(store: store);
      final previous = FlutterError.onError;
      FlutterError.onError = (_) {};
      addTearDown(() => FlutterError.onError = previous);

      controller.holdDraft(
        key: 'a',
        source: 'old',
        value: 'new',
        saver: (_) async => true,
      );
      await tester.pump();
      controller.clearDraft('a');
      expect(await controller.whenDraftsStored(), isTrue);
      expect(store.drafts, isEmpty);
    });

    test('stored drafts round-trip through JSON', () {
      const draft = LazyTextFieldStoredDraft(
        key: 'row-1/name',
        value: 'new',
        baseText: 'old',
      );
      expect(LazyTextFieldStoredDraft.fromJson(draft.toJson()), draft);
    });
  });
}

/// A memory store whose next [failures] writes throw.
class _FlakyStore extends LazyTextFieldMemoryDraftStore {
  int failures = 0;

  @override
  void put(LazyTextFieldStoredDraft draft) {
    if (failures > 0) {
      failures--;
      throw StateError('disk full');
    }
    super.put(draft);
  }

  @override
  void delete(String key) {
    if (failures > 0) {
      failures--;
      throw StateError('disk full');
    }
    super.delete(key);
  }
}
