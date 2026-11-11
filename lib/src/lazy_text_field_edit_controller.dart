import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:lazy_text_field/src/lazy_text_field.dart';

/// What happens to an active edit when another cell starts editing.
enum LazyTextFieldSwitchPolicy {
  /// Close the previous editor and drop its unsaved text (2.0 behavior).
  discard,

  /// Pass the previous editor's text to its registered commit handler, then
  /// close it. This is the default.
  ///
  /// The new cell gets focus immediately; the commit runs in the background.
  commit,
}

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

/// Save state of a [LazyTextFieldDraft].
enum LazyTextFieldDraftStatus {
  /// Queued or saving.
  pending,

  /// Saved; shown until the source text catches up.
  saved,

  /// The commit threw; [LazyTextFieldDraft.error] holds the error.
  failed,
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

/// A committed value kept by a [LazyTextFieldEditController] after its
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

/// Receives the text of an editor that is being closed because another cell
/// started editing.
typedef LazyTextFieldCommitHandler = void Function(String text);

/// Manages lazy controller/focus allocation for many [ScopedLazyTextField]
/// cells, and the drafts and background save queue used by
/// [ScopedLazyTextField.onCommit].
///
/// While a draft is pending or failed, its cell shows the draft instead of
/// its source `text`. A saved draft is shown until the source text changes
/// (the refreshed value arrives). Drafts cost nothing until a cell commits.
class LazyTextFieldEditController extends ChangeNotifier {
  /// Creates an edit controller.
  ///
  /// [saveOrder] defaults to [LazyTextFieldSaveOrder.sequential].
  ///
  /// [switchPolicy] decides whether switching cells commits or discards the
  /// previous cell's text. Since 2.1.0 it defaults to
  /// [LazyTextFieldSwitchPolicy.commit]; pass
  /// [LazyTextFieldSwitchPolicy.discard] for the 2.0 behavior.
  LazyTextFieldEditController({
    this.switchPolicy = LazyTextFieldSwitchPolicy.commit,
    this.saveOrder = LazyTextFieldSaveOrder.sequential,
    this.onSavesSettled,
  });

  /// What happens to an active edit when another cell starts editing.
  final LazyTextFieldSwitchPolicy switchPolicy;

  /// How [ScopedLazyTextField.onCommit] saves are ordered.
  final LazyTextFieldSaveOrder saveOrder;

  /// Called each time the save queue becomes empty, for example to refresh
  /// the data once after a burst of saves.
  ///
  /// Not called after [dispose].
  final LazyTextFieldSavesSettled? onSavesSettled;

  final Map<String, TextEditingController> _controllers =
      <String, TextEditingController>{};
  final Map<String, FocusNode> _focusNodes = <String, FocusNode>{};
  final Map<String, LazyTextFieldCommitHandler> _commitHandlers =
      <String, LazyTextFieldCommitHandler>{};
  Completer<void>? _editingDone;
  bool _switching = false;
  bool _disposed = false;

  /// Active text controllers keyed by cell id.
  Map<String, TextEditingController> get controllers =>
      Map.unmodifiable(_controllers);

  /// Active focus nodes keyed by cell id.
  Map<String, FocusNode> get focusNodes => Map.unmodifiable(_focusNodes);

  /// Cell ids that are currently editing.
  Iterable<String> get activeIds => _controllers.keys;

  /// Whether [cellId] currently has both a controller and focus node.
  bool isEditing(String cellId) =>
      _controllers.containsKey(cellId) && _focusNodes.containsKey(cellId);

  /// Returns the active text controller for [cellId], if it is editing.
  TextEditingController? controllerFor(String cellId) => _controllers[cellId];

  /// Returns the active focus node for [cellId], if it is editing.
  FocusNode? focusNodeFor(String cellId) => _focusNodes[cellId];

  /// Completes when no cell is editing; immediately if none is.
  ///
  /// Switching from one cell to another does not complete it: the editing
  /// session continues in the new cell. Use it to defer work that would
  /// replace the cells under an open editor, such as applying a data
  /// refresh. Editing can start again afterwards, so check [activeIds] again
  /// if that matters.
  Future<void> whenEditingDone() {
    if (_controllers.isEmpty) return Future<void>.value();
    return (_editingDone ??= Completer<void>()).future;
  }

  /// Registers [handler] to receive [cellId]'s text when a switch to another
  /// cell closes it under [LazyTextFieldSwitchPolicy.commit].
  ///
  /// Only active cells can register. The handler is removed when the cell
  /// stops editing.
  void setCommitHandler(String cellId, LazyTextFieldCommitHandler handler) {
    if (!_controllers.containsKey(cellId)) return;
    _commitHandlers[cellId] = handler;
  }

  /// Removes [cellId]'s commit handler if it is still [handler].
  void removeCommitHandler(String cellId, LazyTextFieldCommitHandler handler) {
    if (identical(_commitHandlers[cellId], handler)) {
      _commitHandlers.remove(cellId);
    }
  }

  /// Starts editing [cellId] and returns its active controller.
  ///
  /// Unless [allowMultipleActiveEdits] is true, other active cells are stopped
  /// before this one starts editing. Under [LazyTextFieldSwitchPolicy.commit]
  /// their text goes to their commit handlers first.
  TextEditingController startEditing({
    required String cellId,
    required String initialValue,
    bool allowMultipleActiveEdits = false,
    LazyTextFieldStartEditSelection startEditSelection =
        LazyTextFieldStartEditSelection.end,
    int? textOffset,
  }) {
    if (!allowMultipleActiveEdits) {
      _switching = true;
      try {
        _switchFrom(cellId);
      } finally {
        _switching = false;
      }
    }

    final existing = _controllers[cellId];
    if (existing != null) {
      _focusExisting(
        cellId,
        existing,
        startEditSelection: startEditSelection,
        textOffset: textOffset,
      );
      return existing;
    }

    final controller = TextEditingController(text: initialValue);
    final focusNode = FocusNode(debugLabel: 'lazy-text-field-$cellId');
    _controllers[cellId] = controller;
    _focusNodes[cellId] = focusNode;
    notifyListeners();

    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!identical(_controllers[cellId], controller) ||
          !identical(_focusNodes[cellId], focusNode)) {
        return;
      }
      if (!focusNode.canRequestFocus) return;
      focusNode.requestFocus();
      controller.selection = _startEditSelectionFor(
        text: controller.text,
        policy: startEditSelection,
        textOffset: textOffset,
      );
    });
    return controller;
  }

  final Map<Object, LazyTextFieldDraft> _drafts =
      <Object, LazyTextFieldDraft>{};
  final Map<Object, Future<bool>> _inFlight = <Object, Future<bool>>{};
  final Map<Object?, Future<void>> _lanes = <Object?, Future<void>>{};
  final List<Completer<void>> _settledWaiters = <Completer<void>>[];
  int _pendingSaves = 0;
  int _savedSinceSettle = 0;
  int _failedSinceSettle = 0;

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

  /// Updates the active controller text for [cellId] without starting editing.
  void updateText(String cellId, String value) {
    final controller = _controllers[cellId];
    if (controller == null) return;
    if (controller.text != value) {
      controller.text = value;
    }
  }

  /// Stops editing [cellId] and disposes its edit resources.
  ///
  /// Set [notify] to false when releasing resources during [State.dispose],
  /// where notifying an [InheritedNotifier] would lock the widget tree.
  ///
  /// Controllers are disposed on the next frame after listeners rebuild so a
  /// still-connected IME cannot write into a disposed [TextEditingController]
  /// when quickly switching cells.
  void stopEditing(String cellId, {bool notify = true}) {
    _commitHandlers.remove(cellId);
    final controller = _controllers.remove(cellId);
    final focusNode = _focusNodes.remove(cellId);
    if (controller == null && focusNode == null) return;

    // Close the text input connection before the editor unmounts / disposes.
    if (focusNode != null && focusNode.hasFocus) {
      focusNode.unfocus();
    }
    if (notify) {
      notifyListeners();
    }
    if (_controllers.isEmpty && !_switching) _completeEditingDone();
    SchedulerBinding.instance.addPostFrameCallback((_) {
      controller?.dispose();
      focusNode?.dispose();
    });
  }

  /// Stops every active edit whose id matches [shouldStop].
  void stopWhere(bool Function(String cellId) shouldStop) {
    for (final cellId in _controllers.keys.toList(growable: false)) {
      if (shouldStop(cellId)) {
        stopEditing(cellId);
      }
    }
  }

  /// Stops all active edits.
  void stopAll() {
    stopWhere((_) => true);
  }

  void _switchFrom(String nextCellId) {
    for (final cellId in _controllers.keys.toList(growable: false)) {
      if (cellId == nextCellId) continue;
      final handler = _commitHandlers[cellId];
      final text = _controllers[cellId]?.text;
      try {
        if (switchPolicy == LazyTextFieldSwitchPolicy.commit &&
            handler != null &&
            text != null) {
          handler(text);
        }
      } finally {
        stopEditing(cellId);
      }
    }
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

  void _completeEditingDone() {
    final done = _editingDone;
    _editingDone = null;
    done?.complete();
  }

  void _focusExisting(
    String cellId,
    TextEditingController controller, {
    required LazyTextFieldStartEditSelection startEditSelection,
    int? textOffset,
  }) {
    final focusNode = _focusNodes[cellId];
    controller.selection = _startEditSelectionFor(
      text: controller.text,
      policy: startEditSelection,
      textOffset: textOffset,
    );
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!identical(_controllers[cellId], controller) ||
          !identical(_focusNodes[cellId], focusNode) ||
          focusNode == null ||
          !focusNode.canRequestFocus) {
        return;
      }
      focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _drafts.clear();
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    for (final focusNode in _focusNodes.values) {
      focusNode.dispose();
    }
    _controllers.clear();
    _focusNodes.clear();
    _commitHandlers.clear();
    _completeEditingDone();
    super.dispose();
  }
}

TextSelection _startEditSelectionFor({
  required String text,
  required LazyTextFieldStartEditSelection policy,
  int? textOffset,
}) {
  return switch (policy) {
    LazyTextFieldStartEditSelection.beginning => const TextSelection.collapsed(
      offset: 0,
    ),
    LazyTextFieldStartEditSelection.end => TextSelection.collapsed(
      offset: text.length,
    ),
    LazyTextFieldStartEditSelection.tapPosition => TextSelection.collapsed(
      offset: (textOffset ?? text.length).clamp(0, text.length),
    ),
    LazyTextFieldStartEditSelection.fullSelection => TextSelection(
      baseOffset: 0,
      extentOffset: text.length,
    ),
  };
}
