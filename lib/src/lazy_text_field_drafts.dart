import 'dart:async';

import 'package:flutter/foundation.dart';

/// Writes a committed value, typically to a server.
///
/// Complete normally on success; throw to mark the draft as failed. The
/// callback runs when its turn in the save queue comes, so it can read state
/// written by earlier saves (for example a row version).
typedef LazyTextFieldCommit = Future<void> Function(String value);

/// Called when a [LazyTextFieldEditController]'s save queue becomes empty.
///
/// [saved] and [failed] count the commits that finished since the queue was
/// last empty.
typedef LazyTextFieldSavesSettled = void Function(int saved, int failed);

/// Saves one draft later, for example from
/// [LazyTextFieldEditController.saveDrafts]; returns whether it saved.
///
/// Registered by the cell that owns the draft, so it keeps working after the
/// cell left the tree.
typedef LazyTextFieldDraftSaver =
    Future<bool> Function(LazyTextFieldDraft draft);

/// Saves many drafts in one request.
///
/// Receives the values by draft key. Return the errors of the drafts that
/// failed, by key; keys that are missing or map to null are saved. Throwing
/// marks every draft in the batch as failed with that error.
typedef LazyTextFieldBatchCommit =
    Future<Map<Object, Object?>> Function(Map<Object, String> values);

/// Save state of a [LazyTextFieldDraft].
enum LazyTextFieldDraftStatus {
  /// Kept but not saved yet: its editor closed without a commit (for example
  /// the cell left the tree), or the controller saves later
  /// ([LazyTextFieldSaveMode.deferred]).
  ///
  /// Saved by [LazyTextFieldEditController.saveDrafts], or, in
  /// [LazyTextFieldSaveMode.immediate], when another cell starts editing.
  /// **Until then the value exists only in memory** (and in the
  /// [LazyTextFieldDraftStore], if one is set).
  unsaved,

  /// Queued or saving.
  pending,

  /// Saved; shown until the source text catches up.
  saved,

  /// The save failed; [LazyTextFieldDraft.error] holds the error, if any.
  failed,
}

/// When a [LazyTextFieldEditController] saves `onCommit` cells.
enum LazyTextFieldSaveMode {
  /// Save when the user submits or moves to another cell.
  ///
  /// Text kept as [LazyTextFieldDraftStatus.unsaved] (an editor that closed
  /// because its cell left the tree) is saved when another cell starts
  /// editing.
  immediate,

  /// Never save on its own: submits, cell switches, and cells leaving the
  /// tree keep the text as [LazyTextFieldDraftStatus.unsaved] drafts. Save
  /// them with [LazyTextFieldEditController.saveDrafts], for example from a
  /// "Save all" button.
  ///
  /// Applies to `onCommit` cells. `onSave` cells still save on submit and on
  /// switch, since `onSave` decides whether the editor may close.
  deferred,
}

/// How a [LazyTextFieldEditController] orders its saves (`onCommit`,
/// `onSave`, and batches).
///
/// In every order, saves of the same draft key never overlap, so an older
/// value cannot land after a newer one.
enum LazyTextFieldSaveOrder {
  /// One save at a time, in the order they were queued.
  ///
  /// The safe default: a save never overlaps another save from the same
  /// controller. A slow save delays the next one, including an `onSave`
  /// submit of another cell (its editor stays open until its turn).
  sequential,

  /// Saves with the same `rowKey` run one at a time, in order; saves for
  /// different rows run in parallel.
  ///
  /// Use when rows are independent records. Cells without a `rowKey` share
  /// one queue and still save one at a time.
  perRow,
}

/// When an explicit submit closes a `ScopedLazyTextField` that uses
/// `onCommit`.
enum LazyTextFieldSubmitClose {
  /// Keep the editor open until the commit succeeds, then close it if its
  /// text has not changed meanwhile. On failure the editor stays open with
  /// the error.
  afterSave,

  /// Close the editor at once and save in the background.
  immediately,
}

/// A value kept by a [LazyTextFieldEditController] after its editor closed.
@immutable
class LazyTextFieldDraft {
  const LazyTextFieldDraft._({
    required this.value,
    required this.baseText,
    required this.status,
    required Set<String> staleSources,
    this.error,
  }) : _staleSources = staleSources;

  /// The kept text.
  final String value;

  /// The source text the cell displayed when the first draft for this key
  /// was kept.
  final String baseText;

  /// Save state.
  final LazyTextFieldDraftStatus status;

  /// Why the save failed, when [status] is [LazyTextFieldDraftStatus.failed]:
  /// what the commit threw, or null when `onSave` returned false.
  final Object? error;

  // Source texts that predate this draft. A saved draft stays visible while
  // the source still shows one of them (the refresh has not arrived yet).
  final Set<String> _staleSources;

  LazyTextFieldDraft _withStatus(
    LazyTextFieldDraftStatus status, {
    Object? error,
  }) => LazyTextFieldDraft._(
    value: value,
    baseText: baseText,
    status: status,
    staleSources: _staleSources,
    error: error,
  );

  @override
  String toString() =>
      'LazyTextFieldDraft($status, ${value.length} chars'
      '${error == null ? '' : ', error: $error'})';
}

/// Result of [LazyTextFieldEditController.saveDrafts].
@immutable
class LazyTextFieldSaveDraftsResult {
  /// Creates a result.
  const LazyTextFieldSaveDraftsResult({
    this.saved = 0,
    this.failed = 0,
    this.skipped = 0,
    this.remaining = 0,
  });

  /// Drafts this call sent and the server accepted: the values as they were
  /// when the call started. A newer value typed meanwhile is in [remaining].
  final int saved;

  /// Drafts this call sent whose save failed; they stay as failed drafts.
  final int failed;

  /// Drafts left unsaved because no saver is known for them (a draft loaded
  /// from a [LazyTextFieldDraftStore] whose cell has not been built since).
  /// Pass a `batch` to save those too.
  final int skipped;

  /// Drafts not saved when the call finished, whatever the reason: failed,
  /// skipped, changed again while saving, or kept by saves that were already
  /// running when the call started and then failed.
  ///
  /// `LazyTextFieldEditController.saveDrafts` commits open editors first by
  /// default; with `includeOpenEdits: false`, open editors are not drafts and
  /// are not counted.
  final int remaining;

  /// Whether nothing is left to save: no failure and no [remaining] draft.
  bool get allSaved => failed == 0 && remaining == 0;

  @override
  String toString() =>
      'LazyTextFieldSaveDraftsResult(saved: $saved, failed: $failed, '
      'skipped: $skipped, remaining: $remaining)';
}

/// A draft as written to a [LazyTextFieldDraftStore].
@immutable
class LazyTextFieldStoredDraft {
  /// Creates a stored draft.
  const LazyTextFieldStoredDraft({
    required this.key,
    required this.value,
    required this.baseText,
  });

  /// Rebuilds a stored draft from [toJson] output.
  factory LazyTextFieldStoredDraft.fromJson(Map<String, Object?> json) =>
      LazyTextFieldStoredDraft(
        key: json['key']! as String,
        value: json['value']! as String,
        baseText: json['baseText']! as String,
      );

  /// The draft key; unique within the store and stable across restarts.
  final String key;

  /// The unsaved text.
  final String value;

  /// The source text the cell showed before the draft.
  final String baseText;

  /// A JSON-compatible map, for stores such as Hive or shared preferences.
  Map<String, Object?> toJson() => <String, Object?>{
    'key': key,
    'value': value,
    'baseText': baseText,
  };

  @override
  bool operator ==(Object other) =>
      other is LazyTextFieldStoredDraft &&
      other.key == key &&
      other.value == value &&
      other.baseText == baseText;

  @override
  int get hashCode => Object.hash(key, value, baseText);
}

/// Local storage for drafts that are not saved yet, so they survive an app
/// restart (for example a Hive box).
///
/// The controller calls [put] when a draft becomes unsaved, pending, or
/// failed, and [delete] when it is saved or discarded. Draft keys must be
/// [String]s that are unique within the store and stable across restarts.
/// Load them back with [LazyTextFieldEditController.loadDrafts].
abstract interface class LazyTextFieldDraftStore {
  /// Returns every stored draft.
  FutureOr<Iterable<LazyTextFieldStoredDraft>> load();

  /// Inserts or replaces the draft with [LazyTextFieldStoredDraft.key].
  FutureOr<void> put(LazyTextFieldStoredDraft draft);

  /// Removes the draft with [key], if stored.
  FutureOr<void> delete(String key);
}

/// [LazyTextFieldDraftStore] that keeps drafts in memory, for tests and as a
/// template for a persistent store.
class LazyTextFieldMemoryDraftStore implements LazyTextFieldDraftStore {
  /// Stored drafts by key.
  final Map<String, LazyTextFieldStoredDraft> drafts =
      <String, LazyTextFieldStoredDraft>{};

  @override
  Iterable<LazyTextFieldStoredDraft> load() => List.of(drafts.values);

  @override
  void put(LazyTextFieldStoredDraft draft) => drafts[draft.key] = draft;

  @override
  void delete(String key) => drafts.remove(key);
}

/// Drafts and the background save queue behind a
/// [LazyTextFieldEditController].
///
/// Internal: not exported from `package:lazy_text_field/lazy_text_field.dart`.
/// Use the controller's draft members instead.
class LazyTextFieldDraftQueue {
  /// Creates a queue that calls [notify] whenever drafts change.
  LazyTextFieldDraftQueue({
    required this.saveOrder,
    required this.notify,
    this.onSettled,
    this.store,
  });

  /// How commits are ordered.
  final LazyTextFieldSaveOrder saveOrder;

  /// Called whenever drafts or [pendingSaves] change.
  final VoidCallback notify;

  /// Called each time the queue becomes empty.
  final LazyTextFieldSavesSettled? onSettled;

  /// Where unsaved drafts are written, if anywhere.
  final LazyTextFieldDraftStore? store;

  bool _disposed = false;

  void _notify() {
    if (!_disposed) notify();
  }

  final Map<Object, LazyTextFieldDraft> _drafts =
      <Object, LazyTextFieldDraft>{};
  final Map<Object, LazyTextFieldDraftSaver> _savers =
      <Object, LazyTextFieldDraftSaver>{};
  final Map<String, LazyTextFieldStoredDraft> _stored =
      <String, LazyTextFieldStoredDraft>{};
  // The latest queued save of each key, until it finishes.
  final Map<Object, _QueuedSave> _inFlight = <Object, _QueuedSave>{};
  // The last job of each lane: a key, a row, or the whole queue.
  final Map<Object, Future<void>> _tails = <Object, Future<void>>{};
  // Store writes run one at a time, in order.
  Future<void> _storeTail = Future<void>.value();
  final Map<String, Object> _storeErrors = <String, Object>{};
  final List<Completer<void>> _settledWaiters = <Completer<void>>[];
  int _pendingSaves = 0;
  int _savedSinceSettle = 0;
  int _failedSinceSettle = 0;

  /// Number of saves queued or running.
  int get pendingSaves => _pendingSaves;

  /// Every draft, by key.
  Map<Object, LazyTextFieldDraft> get drafts => Map.unmodifiable(_drafts);

  /// Completes when the save queue is empty; immediately if it is.
  Future<void> whenSavesSettled() {
    if (_pendingSaves == 0) return Future<void>.value();
    final waiter = Completer<void>();
    _settledWaiters.add(waiter);
    return waiter.future;
  }

  /// The draft for [key], if any.
  LazyTextFieldDraft? draftFor(Object key) => _drafts[key];

  /// Text a cell should display for [key] when its source text is [source].
  ///
  /// Drops a saved draft once [source] no longer matches a text that
  /// predates it.
  String displayText(Object key, String source) {
    final draft = _drafts[key];
    if (draft == null) return source;
    if (draft.status == LazyTextFieldDraftStatus.saved &&
        !draft._staleSources.contains(source)) {
      // The source caught up. Listeners already show [source], so no notify.
      _remove(key);
      return source;
    }
    return draft.value;
  }

  /// Forgets the draft for [key]. A save that is still running continues,
  /// but its result is no longer shown.
  void clearDraft(Object key) {
    if (_remove(key)) _notify();
  }

  /// Registers how to save the draft for [key] later.
  void setSaver(Object key, LazyTextFieldDraftSaver saver) {
    _savers[key] = saver;
  }

  /// Keeps [value] as an unsaved draft for [key], saved later by [saver].
  ///
  /// Does nothing when [value] is already pending for [key].
  void hold({
    required Object key,
    required String source,
    required String value,
    required LazyTextFieldDraftSaver saver,
    bool notify = true,
  }) {
    final previous = _drafts[key];
    if (previous?.status == LazyTextFieldDraftStatus.pending &&
        previous?.value == value) {
      return;
    }
    _savers[key] = saver;
    _newDraft(key, source, value, LazyTextFieldDraftStatus.unsaved);
    if (notify) _notify();
  }

  /// Saves the unsaved drafts that have a saver, except the one for
  /// [except] (it is being edited again).
  void flushUnsaved({Object? except}) {
    final targets = <Object, LazyTextFieldDraft>{
      for (final entry in _drafts.entries)
        if (entry.key != except &&
            entry.value.status == LazyTextFieldDraftStatus.unsaved &&
            _savers.containsKey(entry.key))
          entry.key: entry.value,
    };
    for (final MapEntry(:key, value: draft) in targets.entries) {
      unawaited(_savers[key]!(draft));
    }
  }

  /// Saves every unsaved and failed draft; see
  /// `LazyTextFieldEditController.saveDrafts`.
  Future<LazyTextFieldSaveDraftsResult> saveDrafts({
    LazyTextFieldBatchCommit? batch,
  }) async {
    // Saves queued before this call (pending drafts, onSave submits) must
    // finish before the result can say what is left.
    final earlier = Set<Future<void>>.of(_tails.values);
    final targets = <Object, LazyTextFieldDraft>{
      for (final entry in _drafts.entries)
        if (entry.value.status == LazyTextFieldDraftStatus.unsaved ||
            entry.value.status == LazyTextFieldDraftStatus.failed)
          entry.key: entry.value,
    };

    var saved = 0;
    var failed = 0;
    var skipped = 0;
    if (targets.isEmpty) {
      // Nothing to send.
    } else if (batch != null) {
      final result = await _saveBatch(targets, batch);
      saved = result.saved;
      failed = result.failed;
    } else {
      final saves = <Future<bool>>[];
      for (final MapEntry(:key, value: draft) in targets.entries) {
        final saver = _savers[key];
        if (saver == null) {
          skipped++;
        } else {
          saves.add(saver(draft).catchError((Object _) => false));
        }
      }
      final results = await Future.wait(saves);
      saved = results.where((ok) => ok).length;
      failed = results.length - saved;
    }
    await Future.wait(earlier);
    return LazyTextFieldSaveDraftsResult(
      saved: saved,
      failed: failed,
      skipped: skipped,
      remaining: _drafts.values
          .where((draft) => draft.status != LazyTextFieldDraftStatus.saved)
          .length,
    );
  }

  Future<LazyTextFieldSaveDraftsResult> _saveBatch(
    Map<Object, LazyTextFieldDraft> targets,
    LazyTextFieldBatchCommit batch,
  ) {
    final pending = <Object, LazyTextFieldDraft>{
      for (final MapEntry(:key, value: draft) in targets.entries)
        key: draft._withStatus(LazyTextFieldDraftStatus.pending),
    };
    pending.forEach(_set);
    _pendingSaves += pending.length;
    _notify();

    final result = Completer<LazyTextFieldSaveDraftsResult>();
    // Starts after every earlier save of these keys; later saves of them
    // wait for it.
    _chain(
      [
        for (final key in targets.keys) (#key, key),
        if (saveOrder == LazyTextFieldSaveOrder.sequential) #queue,
      ],
      () async {
        Map<Object, Object?> errors;
        try {
          errors = await batch({
            for (final MapEntry(:key, value: draft) in targets.entries)
              key: draft.value,
          });
        } catch (error) {
          errors = {for (final key in targets.keys) key: error};
        }

        var saved = 0;
        try {
          pending.forEach((key, draft) {
            final error = errors[key];
            if (error == null) saved++;
            if (!identical(_drafts[key], draft)) return;
            _set(
              key,
              error == null
                  ? draft._withStatus(LazyTextFieldDraftStatus.saved)
                  : draft._withStatus(
                      LazyTextFieldDraftStatus.failed,
                      error: error,
                    ),
            );
          });
        } finally {
          final failed = pending.length - saved;
          _pendingSaves -= pending.length;
          _savedSinceSettle += saved;
          _failedSinceSettle += failed;
          _notify();
          result.complete(
            LazyTextFieldSaveDraftsResult(saved: saved, failed: failed),
          );
          if (_pendingSaves == 0) _settle();
        }
      },
    );
    return result.future;
  }

  /// Queues [commit] for [value] and keeps [value] as the draft for [key].
  ///
  /// [source] is the cell's source text at commit time. Returns whether the
  /// commit succeeded. Committing the value that is already queued for [key]
  /// returns that save instead of queuing another.
  Future<bool> enqueue({
    required Object key,
    required String source,
    required String value,
    required LazyTextFieldCommit commit,
    Object? rowKey,
    bool notify = true,
  }) => _saveDraft(
    key: key,
    source: source,
    value: value,
    rowKey: rowKey,
    notify: notify,
    save: () async {
      await commit(value);
      return true;
    },
  );

  /// Keeps [value] as a pending draft for [key] while [save] runs in the
  /// queue, then marks it saved (true) or failed (false, or the error [save]
  /// threw).
  Future<bool> track({
    required Object key,
    required String source,
    required String value,
    required Future<bool> Function() save,
    Object? rowKey,
    bool notify = true,
  }) => _saveDraft(
    key: key,
    source: source,
    value: value,
    rowKey: rowKey,
    notify: notify,
    save: save,
  );

  /// Runs [save] in the queue without keeping a draft; returns whether it
  /// saved (false if it threw). Queuing the value that is already queued for
  /// [key] returns that save.
  Future<bool> queue({
    required Object key,
    required String value,
    required Future<bool> Function() save,
    Object? rowKey,
    bool notify = true,
  }) {
    final job = _schedule(key: key, value: value, rowKey: rowKey, save: save);
    if (notify) _notify();
    return job.done.future;
  }

  Future<bool> _saveDraft({
    required Object key,
    required String source,
    required String value,
    required Object? rowKey,
    required bool notify,
    required Future<bool> Function() save,
  }) {
    final previous = _drafts[key];
    final running = _inFlight[key];
    if (running != null &&
        running.value == value &&
        previous?.status == LazyTextFieldDraftStatus.pending &&
        previous?.value == value) {
      return running.done.future;
    }
    final draft = _newDraft(
      key,
      source,
      value,
      LazyTextFieldDraftStatus.pending,
    );
    final job = _schedule(key: key, value: value, rowKey: rowKey, save: save);
    job.listeners.add((saved, error) {
      if (!identical(_drafts[key], draft)) return;
      _set(
        key,
        saved
            ? draft._withStatus(LazyTextFieldDraftStatus.saved)
            : draft._withStatus(LazyTextFieldDraftStatus.failed, error: error),
      );
    });
    if (notify) _notify();
    return job.done.future;
  }

  /// Queues [save] for [key]. It starts, always asynchronously, after every
  /// earlier save of [key] and of its lane ([saveOrder]) has finished.
  _QueuedSave _schedule({
    required Object key,
    required String value,
    required Object? rowKey,
    required Future<bool> Function() save,
  }) {
    final running = _inFlight[key];
    if (running != null && running.value == value) return running;
    final job = _QueuedSave(value);
    _inFlight[key] = job;
    _pendingSaves++;
    _chain(
      [
        (#key, key),
        if (saveOrder == LazyTextFieldSaveOrder.perRow)
          (#row, rowKey)
        else
          #queue,
      ],
      () async {
        var saved = false;
        Object? error;
        try {
          saved = await save();
        } catch (e) {
          error = e;
        }
        _pendingSaves--;
        if (saved) {
          _savedSinceSettle++;
        } else {
          _failedSinceSettle++;
        }
        if (identical(_inFlight[key], job)) _inFlight.remove(key);
        try {
          for (final listener in job.listeners) {
            listener(saved, error);
          }
        } finally {
          _notify();
          job.done.complete(saved);
          if (_pendingSaves == 0) _settle();
        }
      },
    );
    return job;
  }

  /// Runs [body] after the last job of every lane in [lanes], and makes it
  /// the last job of those lanes.
  void _chain(List<Object> lanes, Future<void> Function() body) {
    final before = <Future<void>>[for (final lane in lanes) ?_tails[lane]];
    final tail = Future.wait(before)
        .then((_) => body())
        .onError<Object>(
          (error, stack) => _report(error, stack, 'while saving a draft'),
        );
    for (final lane in lanes) {
      _tails[lane] = tail;
    }
    unawaited(
      tail.whenComplete(() {
        for (final lane in lanes) {
          if (identical(_tails[lane], tail)) _tails.remove(lane);
        }
      }),
    );
  }

  /// Restores the drafts in [store] that are not in memory as unsaved
  /// drafts; returns how many were restored.
  Future<int> load() async {
    final store = this.store;
    if (store == null) return 0;
    // Writes queued before the load land first.
    await _storeTail;
    final stored = await store.load();
    var restored = 0;
    for (final record in stored) {
      _stored[record.key] = record;
      if (_drafts.containsKey(record.key)) continue;
      _drafts[record.key] = LazyTextFieldDraft._(
        value: record.value,
        baseText: record.baseText,
        status: LazyTextFieldDraftStatus.unsaved,
        staleSources: {record.baseText}..remove(record.value),
      );
      restored++;
    }
    if (restored > 0) _notify();
    return restored;
  }

  LazyTextFieldDraft _newDraft(
    Object key,
    String source,
    String value,
    LazyTextFieldDraftStatus status,
  ) {
    final previous = _drafts[key];
    final stale = <String>{
      ...?previous?._staleSources,
      if (previous != null) previous.value,
      source,
    }..remove(value);
    final draft = LazyTextFieldDraft._(
      value: value,
      baseText: previous?.baseText ?? source,
      status: status,
      staleSources: stale,
    );
    _set(key, draft);
    return draft;
  }

  void _set(Object key, LazyTextFieldDraft draft) {
    _drafts[key] = draft;
    if (draft.status == LazyTextFieldDraftStatus.saved) _savers.remove(key);
    _persist(key, draft);
  }

  bool _remove(Object key) {
    _savers.remove(key);
    final removed = _drafts.remove(key) != null;
    if (removed) _persist(key, null);
    return removed;
  }

  // Unsaved, pending, and failed drafts are written; saved or removed ones
  // are deleted. Pending drafts are written too: if the app stops mid-save,
  // the text comes back as unsaved.
  void _persist(Object key, LazyTextFieldDraft? draft) {
    final store = this.store;
    if (store == null) return;
    assert(
      key is String,
      'A LazyTextFieldDraftStore needs String draft keys, unique within the '
      'store and stable across restarts; got ${key.runtimeType}.',
    );
    if (key is! String) return;
    final keep =
        draft != null && draft.status != LazyTextFieldDraftStatus.saved;
    // After a failed write the stored state is unknown: always write again.
    final unknown = _storeErrors.containsKey(key);
    if (keep) {
      final record = LazyTextFieldStoredDraft(
        key: key,
        value: draft.value,
        baseText: draft.baseText,
      );
      if (_stored[key] == record && !unknown) return;
      _stored[key] = record;
      _write(key, () => store.put(record));
    } else if (_stored.remove(key) != null || unknown) {
      _write(key, () => store.delete(key));
    }
  }

  // One chain for all keys, so a put and a later delete of the same key land
  // in that order even when the store would complete them out of order.
  void _write(String key, FutureOr<void> Function() write) {
    _storeTail = _storeTail
        .then((_) => write())
        .then<void>(
          (_) => _storeErrors.remove(key),
          onError: (Object error, StackTrace stack) {
            _storeErrors[key] = error;
            _report(error, stack, 'while writing a LazyTextFieldDraftStore');
          },
        );
  }

  /// Keys whose last store write failed, with the error.
  Map<String, Object> get storeErrors => Map.unmodifiable(_storeErrors);

  /// Waits for every store write queued so far, retries failed ones once,
  /// and returns whether the store now matches the drafts in memory.
  Future<bool> whenStored() async {
    if (store == null) return true;
    await _storeTail;
    if (_storeErrors.isEmpty) return true;
    if (!_disposed) {
      // Rewrite each failed key from its current state.
      for (final key in List.of(_storeErrors.keys)) {
        _persist(key, _drafts[key]);
      }
      await _storeTail;
    }
    return _storeErrors.isEmpty;
  }

  void _report(Object error, StackTrace stack, String context) {
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stack,
        library: 'lazy_text_field',
        context: ErrorDescription(context),
      ),
    );
  }

  void _settle() {
    final saved = _savedSinceSettle;
    final failed = _failedSinceSettle;
    _savedSinceSettle = 0;
    _failedSinceSettle = 0;
    final waiters = List.of(_settledWaiters);
    _settledWaiters.clear();
    for (final waiter in waiters) {
      waiter.complete();
    }
    if (!_disposed) onSettled?.call(saved, failed);
  }

  /// Stops notifying and forgets the drafts in memory; stored drafts stay in
  /// the store. Running commits finish.
  void dispose() {
    _disposed = true;
    _drafts.clear();
    _savers.clear();
  }
}

class _QueuedSave {
  _QueuedSave(this.value);

  final String value;
  // Sync, so callers' `then` callbacks (onSaved) run before the lane moves
  // on and before saveDrafts() returns.
  final Completer<bool> done = Completer<bool>.sync();
  final List<void Function(bool saved, Object? error)> listeners =
      <void Function(bool saved, Object? error)>[];
}
