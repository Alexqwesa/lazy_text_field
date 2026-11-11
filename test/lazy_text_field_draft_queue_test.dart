import 'dart:async';

import 'package:flutter/foundation.dart';
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

  group('one queue for every save', () {
    Future<bool> Function() saveFor(String key, String value) => () {
      calls.add((key, value));
      final completer = Completer<void>();
      pending.add(completer);
      return completer.future.then((_) => true);
    };

    test(
      'saves of one key never overlap, even across rows in perRow',
      () async {
        final drafts = queue(saveOrder: LazyTextFieldSaveOrder.perRow);
        final first = enqueue(drafts, 'k', 'first', rowKey: 1);
        final second = drafts.track(
          key: 'k',
          source: 'old',
          value: 'second',
          save: saveFor('k', 'second'),
          rowKey: 2,
        );
        await pumpEventQueue();
        expect(calls, [('k', 'first')]);

        pending.removeAt(0).complete();
        expect(await first, isTrue);
        await pumpEventQueue();
        expect(calls, [('k', 'first'), ('k', 'second')]);
        pending.removeAt(0).complete();
        expect(await second, isTrue);
        expect(drafts.draftFor('k')!.value, 'second');
        expect(drafts.draftFor('k')!.status, LazyTextFieldDraftStatus.saved);
      },
    );

    test('an older save finishing late cannot win', () async {
      final drafts = queue();
      final first = enqueue(drafts, 'k', 'first');
      final second = enqueue(drafts, 'k', 'second');
      await pumpEventQueue();
      expect(calls, [('k', 'first')]);
      pending.removeAt(0).complete();
      await first;
      await pumpEventQueue();
      pending.removeAt(0).complete();
      await second;
      expect(calls.map((c) => c.$2), ['first', 'second']);
      expect(drafts.draftFor('k')!.value, 'second');
    });

    test('track and queue share the order and the counters', () async {
      final settled = <(int, int)>[];
      final drafts = queue(onSettled: (s, f) => settled.add((s, f)));
      unawaited(enqueue(drafts, 'a', 'new-a'));
      final tracked = drafts.track(
        key: 'b',
        source: 'old',
        value: 'new-b',
        save: () async => false,
      );
      final queued = drafts.queue(
        key: 'c',
        value: 'new-c',
        save: () async => throw StateError('boom'),
      );
      expect(drafts.pendingSaves, 3);
      await pumpEventQueue();
      expect(calls, [('a', 'new-a')]);

      pending.removeAt(0).complete();
      expect(await tracked, isFalse);
      expect(await queued, isFalse);
      expect(drafts.draftFor('b')!.status, LazyTextFieldDraftStatus.failed);
      expect(drafts.draftFor('c'), isNull);
      expect(drafts.pendingSaves, 0);
      expect(settled, [(1, 2)]);
    });

    test(
      'queuing the value already queued for a key reuses that save',
      () async {
        final drafts = queue();
        final submit = drafts.queue(
          key: 'k',
          value: 'v',
          save: saveFor('k', 'v'),
        );
        final onSwitch = drafts.track(
          key: 'k',
          source: 'old',
          value: 'v',
          save: saveFor('k', 'v'),
        );
        expect(drafts.pendingSaves, 1);
        await pumpEventQueue();
        expect(calls, [('k', 'v')]);
        pending.removeAt(0).complete();
        expect(await submit, isTrue);
        expect(await onSwitch, isTrue);
        expect(drafts.draftFor('k')!.status, LazyTextFieldDraftStatus.saved);
      },
    );

    test('a batch waits for running saves of its keys; later saves wait for '
        'the batch', () async {
      final drafts = queue(saveOrder: LazyTextFieldSaveOrder.perRow);
      final running = enqueue(drafts, 'k', 'first', rowKey: 1);
      drafts.hold(
        key: 'k',
        source: 'old',
        value: 'second',
        saver: (_) async => true,
      );
      final request = Completer<Map<Object, Object?>>();
      Map<Object, String>? sent;
      final batch = drafts.saveDrafts(
        batch: (values) {
          sent = values;
          return request.future;
        },
      );
      final third = enqueue(drafts, 'k', 'third', rowKey: 1);
      await pumpEventQueue();
      expect(calls, [('k', 'first')]);
      expect(sent, isNull);

      pending.removeAt(0).complete();
      await running;
      await pumpEventQueue();
      expect(sent, {'k': 'second'});
      expect(calls, [('k', 'first')]);

      request.complete({});
      expect((await batch).saved, 1);
      await pumpEventQueue();
      expect(calls, [('k', 'first'), ('k', 'third')]);
      pending.removeAt(0).complete();
      expect(await third, isTrue);
      expect(drafts.draftFor('k')!.value, 'third');
    });
  });

  group('store writes', () {
    test('run one at a time, in order', () async {
      final store = _SlowStore();
      final drafts = LazyTextFieldDraftQueue(
        saveOrder: LazyTextFieldSaveOrder.sequential,
        notify: () {},
        store: store,
      );
      addTearDown(drafts.dispose);
      drafts.hold(
        key: 'k',
        source: 'old',
        value: 'v',
        saver: (_) async => true,
      );
      drafts.clearDraft('k');
      await pumpEventQueue();
      expect(store.log, ['put k']);

      // The delete is not sent before the put finished, so a store that
      // would finish them out of order cannot bring the draft back.
      store.finishNext();
      await pumpEventQueue();
      expect(store.log, ['put k', 'delete k']);
      store.finishNext();
      await drafts.whenStored();
      expect(store.drafts, isEmpty);
    });

    test('a failed write is reported and does not stop later ones', () async {
      final store = _SlowStore();
      final drafts = LazyTextFieldDraftQueue(
        saveOrder: LazyTextFieldSaveOrder.sequential,
        notify: () {},
        store: store,
      );
      addTearDown(drafts.dispose);
      final errors = <FlutterErrorDetails>[];
      final previous = FlutterError.onError;
      FlutterError.onError = errors.add;
      addTearDown(() => FlutterError.onError = previous);

      drafts.hold(
        key: 'a',
        source: 'old',
        value: 'v',
        saver: (_) async => true,
      );
      drafts.hold(
        key: 'b',
        source: 'old',
        value: 'v',
        saver: (_) async => true,
      );
      await pumpEventQueue();
      store.failNext('disk full');
      await pumpEventQueue();
      store.finishNext();
      await drafts.whenStored();

      expect(errors.single.exception, 'disk full');
      expect(store.drafts.keys, ['b']);
    });

    test('load waits for queued writes', () async {
      final store = _SlowStore();
      final drafts = LazyTextFieldDraftQueue(
        saveOrder: LazyTextFieldSaveOrder.sequential,
        notify: () {},
        store: store,
      );
      addTearDown(drafts.dispose);
      drafts.hold(
        key: 'k',
        source: 'old',
        value: 'v',
        saver: (_) async => true,
      );
      drafts.clearDraft('k');
      var loaded = false;
      final load = drafts.load().then((count) {
        loaded = true;
        return count;
      });
      await pumpEventQueue();
      expect(loaded, isFalse);
      store.finishNext();
      await pumpEventQueue();
      expect(loaded, isFalse);
      store.finishNext();
      await pumpEventQueue();
      store.finishNext();
      expect(await load, 0);
      expect(store.log, ['put k', 'delete k', 'load']);
    });
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

/// A store whose operations finish only when told to, in call order.
class _SlowStore implements LazyTextFieldDraftStore {
  final Map<String, LazyTextFieldStoredDraft> drafts = {};
  final List<String> log = [];
  final List<Completer<void>> _waiting = [];

  void finishNext() => _waiting.removeAt(0).complete();

  void failNext(Object error) => _waiting.removeAt(0).completeError(error);

  Future<void> _op(String name, void Function() apply) {
    log.add(name);
    final completer = Completer<void>();
    _waiting.add(completer);
    return completer.future.then((_) => apply());
  }

  @override
  Future<Iterable<LazyTextFieldStoredDraft>> load() async {
    await _op('load', () {});
    return List.of(drafts.values);
  }

  @override
  Future<void> put(LazyTextFieldStoredDraft draft) =>
      _op('put ${draft.key}', () => drafts[draft.key] = draft);

  @override
  Future<void> delete(String key) =>
      _op('delete $key', () => drafts.remove(key));
}
