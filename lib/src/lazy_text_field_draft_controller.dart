import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:lazy_text_field/src/lazy_text_field_controller_scope.dart';
import 'package:lazy_text_field/src/lazy_text_field_edit_controller.dart';

/// Writes a committed value, typically to a server.
///
/// Complete normally on success; throw to mark the draft as failed. The
/// callback runs when its turn in the save queue comes, so it can read state
/// written by earlier saves (for example a row version).
typedef LazyTextFieldCommit = Future<void> Function(String value);

/// Called when a [LazyTextFieldDraftController]'s queue becomes empty.
///
/// [saved] and [failed] count the commits that finished since the queue was
/// last empty.
typedef LazyTextFieldSavesSettled = void Function(int saved, int failed);

/// Save state of a [LazyTextFieldDraft].
enum LazyTextFieldDraftStatus {
  /// Queued or saving.
  pending,

  /// Saved; shown until the source text catches up.
  saved,

  /// The commit threw; [LazyTextFieldDraft.error] holds the error.
  failed,
}

/// How a [LazyTextFieldDraftController] orders its saves.
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

/// When an explicit submit closes a [ScopedLazyTextField] that uses
/// `onCommit`.
enum LazyTextFieldSubmitClose {
  /// Keep the editor open until the commit succeeds, then close it if its
  /// text has not changed meanwhile. On failure the editor stays open with
  /// the error.
  afterSave,

  /// Close the editor at once and save in the background.
  immediately,
}

/// A committed value kept by a [LazyTextFieldDraftController] after its
/// editor closed.
@immutable
class LazyTextFieldDraft {
  const LazyTextFieldDraft._({
    required this.value,
    required this.baseText,
    required this.status,
    required Set<String> staleSources,
    this.error,
  }) : _staleSources = staleSources;

  /// The committed text.
  final String value;

  /// The source text the cell displayed when the first unsaved draft for
  /// this key was committed.
  final String baseText;

  /// Save state.
  final LazyTextFieldDraftStatus status;

  /// What the commit threw, when [status] is
  /// [LazyTextFieldDraftStatus.failed].
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

/// [LazyTextFieldEditController] that keeps committed drafts beyond the
/// lifetime of their cells and saves them through a background queue.
///
/// Use with [ScopedLazyTextField.onCommit]. While a draft is pending or
/// failed, the cell shows the draft instead of its source `text`. A saved
/// draft is shown until the source text changes (the refreshed value
/// arrives).
class LazyTextFieldDraftController extends LazyTextFieldEditController {
  /// Creates a draft controller.
  ///
  /// [saveOrder] defaults to [LazyTextFieldSaveOrder.sequential].
  LazyTextFieldDraftController({
    this.saveOrder = LazyTextFieldSaveOrder.sequential,
    this.onSavesSettled,
    super.switchPolicy,
  });

  /// How saves are ordered.
  final LazyTextFieldSaveOrder saveOrder;

  /// Called each time the save queue becomes empty, for example to refresh
  /// the data once after a burst of saves.
  ///
  /// Not called after [dispose].
  final LazyTextFieldSavesSettled? onSavesSettled;

  /// Returns the nearest draft controller, or null when the nearest scope has
  /// none.
  ///
  /// Registers a dependency, so the caller rebuilds when drafts change.
  static LazyTextFieldDraftController? maybeOf(BuildContext context) {
    final controller = LazyTextFieldControllerScope.maybeOf(context);
    return controller is LazyTextFieldDraftController ? controller : null;
  }

  final Map<Object, LazyTextFieldDraft> _drafts =
      <Object, LazyTextFieldDraft>{};
  final Map<Object, Future<bool>> _inFlight = <Object, Future<bool>>{};
  final Map<Object?, Future<void>> _lanes = <Object?, Future<void>>{};
  final List<Completer<void>> _settledWaiters = <Completer<void>>[];
  int _pendingSaves = 0;
  int _savedSinceSettle = 0;
  int _failedSinceSettle = 0;
  bool _disposed = false;

  /// Number of commits queued or running.
  int get pendingSaves => _pendingSaves;

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
      _drafts.remove(key);
      return source;
    }
    return draft.value;
  }

  /// Forgets the draft for [key]. A save that is still running continues,
  /// but its result is no longer shown.
  void clearDraft(Object key) {
    if (_drafts.remove(key) != null && !_disposed) notifyListeners();
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
  }) {
    final previous = _drafts[key];
    if (previous != null &&
        previous.status == LazyTextFieldDraftStatus.pending &&
        previous.value == value) {
      final running = _inFlight[key];
      if (running != null) return running;
    }

    final stale = <String>{
      ...?previous?._staleSources,
      if (previous != null) previous.value,
      source,
    }..remove(value);
    final draft = LazyTextFieldDraft._(
      value: value,
      baseText: previous?.baseText ?? source,
      status: LazyTextFieldDraftStatus.pending,
      staleSources: stale,
    );
    _drafts[key] = draft;
    _pendingSaves++;
    notifyListeners();

    final lane = saveOrder == LazyTextFieldSaveOrder.perRow ? rowKey : null;
    final completer = Completer<bool>();
    final tail = (_lanes[lane] ?? Future<void>.value()).then((_) async {
      var saved = false;
      try {
        await commit(value);
        saved = true;
        if (identical(_drafts[key], draft)) {
          _drafts[key] = draft._withStatus(LazyTextFieldDraftStatus.saved);
        }
      } catch (error) {
        if (identical(_drafts[key], draft)) {
          _drafts[key] = draft._withStatus(
            LazyTextFieldDraftStatus.failed,
            error: error,
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
        if (!_disposed) notifyListeners();
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

  @override
  void notifyListeners() {
    if (_disposed) return;
    super.notifyListeners();
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
    if (!_disposed) onSavesSettled?.call(saved, failed);
  }

  @override
  void dispose() {
    _disposed = true;
    _drafts.clear();
    super.dispose();
  }
}
