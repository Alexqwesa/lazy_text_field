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

/// How a [LazyTextFieldEditController] orders its saves.
enum LazyTextFieldSaveOrder {
  /// One save at a time, in the order they were queued.
  ///
  /// The safe default: a commit never overlaps another commit from the same
  /// controller.
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
  });

  /// Drafts that were saved.
  final int saved;

  /// Drafts whose save failed; they stay as failed drafts.
  final int failed;

  /// Drafts left unsaved because no saver is known for them (a draft loaded
  /// from a [LazyTextFieldDraftStore] whose cell has not been built since).
  /// Pass a `batch` to save those too.
  final int skipped;

  /// Whether every draft was saved.
  bool get allSaved => failed == 0 && skipped == 0;

  @override
  String toString() =>
      'LazyTextFieldSaveDraftsResult(saved: $saved, failed: $failed, '
      'skipped: $skipped)';
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
  final Map<Object, Future<bool>> _inFlight = <Object, Future<bool>>{};
  final Map<Object?, Future<void>> _lanes = <Object?, Future<void>>{};
  final List<Completer<void>> _settledWaiters = <Completer<void>>[];
  int _pendingSaves = 0;
  int _savedSinceSettle = 0;
  int _failedSinceSettle = 0;

  /// Number of commits queued or running.
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
    final targets = <Object, LazyTextFieldDraft>{
      for (final entry in _drafts.entries)
        if (entry.value.status == LazyTextFieldDraftStatus.unsaved ||
            entry.value.status == LazyTextFieldDraftStatus.failed)
          entry.key: entry.value,
    };
    if (targets.isEmpty) return const LazyTextFieldSaveDraftsResult();
    if (batch != null) return _saveBatch(targets, batch);

    var skipped = 0;
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
    final saved = results.where((ok) => ok).length;
    return LazyTextFieldSaveDraftsResult(
      saved: saved,
      failed: results.length - saved,
      skipped: skipped,
    );
  }

  Future<LazyTextFieldSaveDraftsResult> _saveBatch(
    Map<Object, LazyTextFieldDraft> targets,
    LazyTextFieldBatchCommit batch,
  ) async {
    final pending = <Object, LazyTextFieldDraft>{
      for (final MapEntry(:key, value: draft) in targets.entries)
        key: draft._withStatus(LazyTextFieldDraftStatus.pending),
    };
    pending.forEach(_set);
    _pendingSaves += pending.length;
    _notify();

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
    pending.forEach((key, draft) {
      final error = errors[key];
      if (error == null) saved++;
      if (!identical(_drafts[key], draft)) return;
      _set(
        key,
        error == null
            ? draft._withStatus(LazyTextFieldDraftStatus.saved)
            : draft._withStatus(LazyTextFieldDraftStatus.failed, error: error),
      );
    });
    final failed = pending.length - saved;
    _pendingSaves -= pending.length;
    _savedSinceSettle += saved;
    _failedSinceSettle += failed;
    _notify();
    if (_pendingSaves == 0) _settle();
    return LazyTextFieldSaveDraftsResult(saved: saved, failed: failed);
  }

  /// Queues [commit] for [value] and keeps [value] as the draft for [key].
  ///
  /// [source] is the cell's source text at commit time. Returns whether the
  /// commit succeeded. Committing the value that is already pending for
  /// [key] returns the running save instead of queuing another.
  Future<bool> enqueue({
    required Object key,
    required String source,
    required String value,
    required LazyTextFieldCommit commit,
    Object? rowKey,
    bool notify = true,
  }) {
    final previous = _drafts[key];
    if (previous != null &&
        previous.status == LazyTextFieldDraftStatus.pending &&
        previous.value == value) {
      final running = _inFlight[key];
      if (running != null) return running;
    }

    final draft = _newDraft(
      key,
      source,
      value,
      LazyTextFieldDraftStatus.pending,
    );
    _pendingSaves++;
    if (notify) _notify();

    final lane = saveOrder == LazyTextFieldSaveOrder.perRow ? rowKey : null;
    final completer = Completer<bool>();
    final tail = (_lanes[lane] ?? Future<void>.value()).then((_) async {
      var saved = false;
      try {
        await commit(value);
        saved = true;
        if (identical(_drafts[key], draft)) {
          _set(key, draft._withStatus(LazyTextFieldDraftStatus.saved));
        }
      } catch (error) {
        if (identical(_drafts[key], draft)) {
          _set(
            key,
            draft._withStatus(LazyTextFieldDraftStatus.failed, error: error),
          );
        }
      } finally {
        _pendingSaves--;
        if (saved) {
          _savedSinceSettle++;
        } else {
          _failedSinceSettle++;
        }
        if (identical(_inFlight[key], completer.future)) _inFlight.remove(key);
        _notify();
        completer.complete(saved);
        if (_pendingSaves == 0) _settle();
      }
    });
    _lanes[lane] = tail;
    unawaited(
      tail.whenComplete(() {
        if (identical(_lanes[lane], tail)) _lanes.remove(lane);
      }),
    );
    _inFlight[key] = completer.future;
    return completer.future;
  }

  /// Keeps [value] as a pending draft for [key] while [save] runs, then marks
  /// it saved (true) or failed (false, or the error [save] threw).
  ///
  /// Unlike [enqueue], [save] runs right away, outside the queue, and does
  /// not count towards [pendingSaves]. It is called in a microtask, so this
  /// is safe to call while the widget tree is locked (pass [notify] false).
  Future<bool> track({
    required Object key,
    required String source,
    required String value,
    required Future<bool> Function() save,
    bool notify = true,
  }) async {
    final draft = _newDraft(
      key,
      source,
      value,
      LazyTextFieldDraftStatus.pending,
    );
    if (notify) _notify();
    await Future<void>.value();
    var saved = false;
    Object? error;
    try {
      saved = await save();
    } catch (e) {
      error = e;
    }
    if (identical(_drafts[key], draft)) {
      _set(
        key,
        draft._withStatus(
          saved
              ? LazyTextFieldDraftStatus.saved
              : LazyTextFieldDraftStatus.failed,
          error: error,
        ),
      );
    }
    _notify();
    return saved;
  }

  /// Restores the drafts in [store] that are not in memory as unsaved
  /// drafts; returns how many were restored.
  Future<int> load() async {
    final store = this.store;
    if (store == null) return 0;
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
    if (keep) {
      final record = LazyTextFieldStoredDraft(
        key: key,
        value: draft.value,
        baseText: draft.baseText,
      );
      if (_stored[key] == record) return;
      _stored[key] = record;
      _write(() => store.put(record));
    } else if (_stored.remove(key) != null) {
      _write(() => store.delete(key));
    }
  }

  void _write(FutureOr<void> Function() write) {
    unawaited(
      Future<void>.sync(write).catchError((Object error, StackTrace stack) {
        FlutterError.reportError(
          FlutterErrorDetails(
            exception: error,
            stack: stack,
            library: 'lazy_text_field',
            context: ErrorDescription(
              'while writing a LazyTextFieldDraftStore',
            ),
          ),
        );
      }),
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
