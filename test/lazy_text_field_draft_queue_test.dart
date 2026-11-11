import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
// The queue is internal; the package barrel hides it.
import 'package:lazy_text_field/src/lazy_text_field_drafts.dart';

/// Widget-free tests for the internal draft queue.
void main() {
  late List<(String, String)> calls;
  late List<Completer<void>> pending;
  late int notifications;

  setUp(() {
    calls = [];
    pending = [];
    notifications = 0;
  });

  LazyTextFieldDraftQueue queue({
    LazyTextFieldSaveOrder saveOrder = LazyTextFieldSaveOrder.sequential,
    LazyTextFieldSavesSettled? onSettled,
  }) {
    final queue = LazyTextFieldDraftQueue(
      saveOrder: saveOrder,
      notify: () => notifications++,
      onSettled: onSettled,
    );
    addTearDown(queue.dispose);
    return queue;
  }

  LazyTextFieldCommit commitFor(String key) => (value) {
    calls.add((key, value));
    final completer = Completer<void>();
    pending.add(completer);
    return completer.future;
  };

  Future<bool> enqueue(
    LazyTextFieldDraftQueue queue,
    String key,
    String value, {
    String source = 'old',
    Object? rowKey,
  }) => queue.enqueue(
    key: key,
    source: source,
    value: value,
    commit: commitFor(key),
    rowKey: rowKey,
  );

  test('sequential starts the next commit after the previous one', () async {
    final drafts = queue();
    final a = enqueue(drafts, 'a', 'new-a', rowKey: 1);
    final b = enqueue(drafts, 'b', 'new-b', rowKey: 2);
    await pumpEventQueue();
    expect(calls, [('a', 'new-a')]);

    pending.removeAt(0).complete();
    expect(await a, isTrue);
    await pumpEventQueue();
    expect(calls, [('a', 'new-a'), ('b', 'new-b')]);
    pending.removeAt(0).complete();
    expect(await b, isTrue);
  });

  test('perRow runs different rows at once', () async {
    final drafts = queue(saveOrder: LazyTextFieldSaveOrder.perRow);
    unawaited(enqueue(drafts, 'a', 'new-a', rowKey: 1));
    unawaited(enqueue(drafts, 'b', 'new-b', rowKey: 2));
    unawaited(enqueue(drafts, 'c', 'new-c', rowKey: 1));
    await pumpEventQueue();
    expect(calls, [('a', 'new-a'), ('b', 'new-b')]);

    pending.removeAt(0).complete();
    await pumpEventQueue();
    expect(calls.last, ('c', 'new-c'));
    for (final completer in pending) {
      completer.complete();
    }
  });

  test('a saved draft is shown until the source moves past it', () async {
    final drafts = queue();
    unawaited(enqueue(drafts, 'k', 'first'));
    await pumpEventQueue();
    pending.removeAt(0).complete();
    await pumpEventQueue();
    unawaited(enqueue(drafts, 'k', 'second'));
    await pumpEventQueue();
    pending.removeAt(0).complete();
    await pumpEventQueue();

    expect(drafts.draftFor('k')!.status, LazyTextFieldDraftStatus.saved);
    expect(drafts.draftFor('k')!.baseText, 'old');
    // Stale refreshes: the original value, then the first save.
    expect(drafts.displayText('k', 'old'), 'second');
    expect(drafts.displayText('k', 'first'), 'second');
    // The refresh caught up.
    expect(drafts.displayText('k', 'second'), 'second');
    expect(drafts.draftFor('k'), isNull);
  });

  test('a failed draft keeps its value and error', () async {
    final drafts = queue();
    final result = enqueue(drafts, 'k', 'bad');
    await pumpEventQueue();
    pending.removeAt(0).completeError('nope');
    expect(await result, isFalse);

    final draft = drafts.draftFor('k')!;
    expect(draft.status, LazyTextFieldDraftStatus.failed);
    expect(draft.error, 'nope');
    expect(drafts.displayText('k', 'something else'), 'bad');
  });

  test('notifies on changes and settles once per burst', () async {
    final settled = <(int, int)>[];
    final drafts = queue(
      onSettled: (saved, failed) {
        settled.add((saved, failed));
      },
    );
    unawaited(enqueue(drafts, 'a', 'new-a'));
    unawaited(enqueue(drafts, 'b', 'new-b'));
    expect(notifications, 2);
    expect(drafts.pendingSaves, 2);

    await pumpEventQueue();
    pending.removeAt(0).complete();
    await pumpEventQueue();
    pending.removeAt(0).completeError('nope');
    await drafts.whenSavesSettled();
    expect(notifications, 4);
    expect(settled, [(1, 1)]);
  });

  test('dispose stops notifications but lets commits finish', () async {
    var settledCalls = 0;
    final drafts = LazyTextFieldDraftQueue(
      saveOrder: LazyTextFieldSaveOrder.sequential,
      notify: () => notifications++,
      onSettled: (_, _) => settledCalls++,
    );
    final result = enqueue(drafts, 'k', 'new');
    await pumpEventQueue();
    drafts.dispose();
    pending.removeAt(0).complete();

    expect(await result, isTrue);
    expect(notifications, 1);
    expect(settledCalls, 0);
    expect(drafts.draftFor('k'), isNull);
  });
}
