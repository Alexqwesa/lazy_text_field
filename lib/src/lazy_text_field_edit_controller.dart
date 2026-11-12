import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:lazy_text_field/src/lazy_text_field.dart';
import 'package:lazy_text_field/src/lazy_text_field_drafts.dart';

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
    this.saveMode = LazyTextFieldSaveMode.immediate,
    this.saveOrder = LazyTextFieldSaveOrder.sequential,
    this.onSavesSettled,
    this.draftStore,
  });

  /// What happens to an active edit when another cell starts editing.
  final LazyTextFieldSwitchPolicy switchPolicy;

  /// When [ScopedLazyTextField.onCommit] cells save.
  ///
  /// [LazyTextFieldSaveMode.immediate] (default) saves on submit and on
  /// switch; [LazyTextFieldSaveMode.deferred] keeps everything as unsaved
  /// drafts until [saveDrafts].
  final LazyTextFieldSaveMode saveMode;

  /// How saves are ordered: `onCommit` commits, `onSave` calls, and batches
  /// all go through the same queue.
  ///
  /// In every order, saves of the same draft key never overlap: a newer
  /// value is sent only after the older save finished, so it cannot be
  /// overwritten by it.
  final LazyTextFieldSaveOrder saveOrder;

  /// Where unsaved, pending, and failed drafts are written so they survive an
  /// app restart (for example a Hive box); null keeps them in memory only.
  ///
  /// Requires [String] draft keys that are unique within the store and
  /// stable across restarts. Call [loadDrafts] at startup to restore them.
  final LazyTextFieldDraftStore? draftStore;

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
  bool _notifyScheduled = false;

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
  /// their text goes to their commit handlers first, and in
  /// [LazyTextFieldSaveMode.immediate] unsaved drafts are saved, except the
  /// one for [draftKey] (default [cellId]), which this editor continues.
  TextEditingController startEditing({
    required String cellId,
    required String initialValue,
    bool allowMultipleActiveEdits = false,
    LazyTextFieldStartEditSelection startEditSelection =
        LazyTextFieldStartEditSelection.end,
    int? textOffset,
    Object? draftKey,
  }) {
    if (!allowMultipleActiveEdits) {
      _switching = true;
      try {
        _switchFrom(cellId);
      } finally {
        _switching = false;
      }
    }
    if (switchPolicy == LazyTextFieldSwitchPolicy.commit &&
        saveMode == LazyTextFieldSaveMode.immediate) {
      // The user moved on: text kept from cells that left the tree is saved.
      _drafts.flushUnsaved(except: draftKey ?? cellId);
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

  late final LazyTextFieldDraftQueue _drafts = LazyTextFieldDraftQueue(
    saveOrder: saveOrder,
    notify: notifyListeners,
    onSettled: onSavesSettled,
    store: draftStore,
  );

  /// Every draft, by key; filter by [LazyTextFieldDraft.status], for example
  /// to show how many changes are not saved yet.
  Map<Object, LazyTextFieldDraft> get drafts => _drafts.drafts;

  /// Keeps [value] as an [LazyTextFieldDraftStatus.unsaved] draft for [key],
  /// to be saved later by [saver].
  ///
  /// [ScopedLazyTextField] uses this when an editor closes without a save
  /// (its cell left the tree, or [LazyTextFieldSaveMode.deferred]). The text
  /// is saved by [saveDrafts] or, in [LazyTextFieldSaveMode.immediate], when
  /// another cell starts editing. **Until then it exists only in memory** (and
  /// in [draftStore], if set): if neither happens, it is never saved.
  ///
  /// Set [notify] to false when calling from [State.dispose]; listeners are
  /// then notified after the frame.
  void holdDraft({
    required Object key,
    required String source,
    required String value,
    required LazyTextFieldDraftSaver saver,
    bool notify = true,
  }) {
    _drafts.hold(
      key: key,
      source: source,
      value: value,
      saver: saver,
      notify: notify,
    );
    if (!notify) _notifyAfterFrame();
  }

  /// Registers how to save the draft for [key] later, for example for a
  /// draft restored by [loadDrafts] once its cell is built again.
  void setDraftSaver(Object key, LazyTextFieldDraftSaver saver) =>
      _drafts.setSaver(key, saver);

  /// Saves every [LazyTextFieldDraftStatus.unsaved] and
  /// [LazyTextFieldDraftStatus.failed] draft, for example from a "Save all"
  /// button or before leaving a screen.
  ///
  /// Without [batch], each draft is saved by its own cell's `onCommit`
  /// (through the save queue) or `onSave`. Drafts without a known saver (loaded
  /// from [draftStore] and not shown since) are skipped. With [batch], all of
  /// them are sent in one call; see [LazyTextFieldBatchCommit].
  ///
  /// With [includeOpenEdits] (default), open editors are committed first
  /// ([commitAll]) and close. The returned future also waits for saves that
  /// were queued before the call, so
  /// [LazyTextFieldSaveDraftsResult.allSaved] is true only when nothing is
  /// left to save, including text changed again while saving
  /// ([LazyTextFieldSaveDraftsResult.remaining]). Cells' `onSaved` run for
  /// the drafts saved through them; a [batch] does not call them.
  Future<LazyTextFieldSaveDraftsResult> saveDrafts({
    LazyTextFieldBatchCommit? batch,
    bool includeOpenEdits = true,
  }) {
    if (includeOpenEdits) commitAll();
    return _drafts.saveDrafts(batch: batch);
  }

  /// Restores the drafts in [draftStore] as unsaved drafts; returns how many
  /// were restored. Drafts already in memory win.
  ///
  /// Call it once at startup. Cells show restored drafts, and register how to
  /// save them, when they are built.
  Future<int> loadDrafts() => _drafts.load();

  /// Number of saves queued or running (`onCommit` and `onSave`).
  int get pendingSaves => _drafts.pendingSaves;

  /// Completes when the save queue is empty; immediately if it is.
  Future<void> whenSavesSettled() => _drafts.whenSavesSettled();

  /// The draft for [key], if any.
  LazyTextFieldDraft? draftFor(Object key) => _drafts.draftFor(key);

  /// Text a cell should display for [key] when its source text is [source].
  ///
  /// Drops a saved draft once [source] no longer matches a text that
  /// predates it.
  String displayText(Object key, String source) =>
      _drafts.displayText(key, source);

  /// Forgets the draft for [key]. A save that is still running continues,
  /// but its result is no longer shown.
  void clearDraft(Object key) => _drafts.clearDraft(key);

  /// Queues [commit] for [value] and keeps [value] as the draft for [key].
  ///
  /// [source] is the cell's source text at commit time. [rowKey] picks the
  /// queue under [LazyTextFieldSaveOrder.perRow]. Returns whether the commit
  /// succeeded. Committing the value that is already pending for [key]
  /// returns the running save instead of queuing another.
  ///
  /// Set [notify] to false when calling from [State.dispose] (listeners are
  /// then notified after the frame); [commit] always runs asynchronously.
  Future<bool> enqueue({
    required Object key,
    required String source,
    required String value,
    required LazyTextFieldCommit commit,
    Object? rowKey,
    bool notify = true,
  }) {
    final result = _drafts.enqueue(
      key: key,
      source: source,
      value: value,
      commit: commit,
      rowKey: rowKey,
      notify: notify,
    );
    if (!notify) _notifyAfterFrame();
    return result;
  }

  /// Shows [value] as the draft for [key] while [save] runs in the save
  /// queue, and keeps it if the save fails.
  ///
  /// Like [enqueue], but [save] reports the outcome: true marks the draft
  /// saved; false or a throw marks it failed (with the thrown error, if any).
  /// [ScopedLazyTextField] uses this for `onSave` when an editor closes
  /// without a submit. Set [notify] to false when calling from
  /// [State.dispose] (listeners are then notified after the frame); [save]
  /// always runs asynchronously.
  Future<bool> trackDraft({
    required Object key,
    required String source,
    required String value,
    required Future<bool> Function() save,
    Object? rowKey,
    bool notify = true,
  }) {
    final result = _drafts.track(
      key: key,
      source: source,
      value: value,
      save: save,
      rowKey: rowKey,
      notify: notify,
    );
    if (!notify) _notifyAfterFrame();
    return result;
  }

  /// Runs [save] in the save queue without keeping a draft, for a save whose
  /// editor stays open until it finishes (as `onSave` on submit does).
  ///
  /// Returns whether it saved; a throw counts as false. Queuing the [value]
  /// that is already queued for [key] returns that save.
  Future<bool> queueSave({
    required Object key,
    required String value,
    required Future<bool> Function() save,
    Object? rowKey,
  }) => _drafts.queue(key: key, value: value, save: save, rowKey: rowKey);

  /// Waits until every [draftStore] write requested so far has finished,
  /// retries failed writes once, and returns whether the store now holds
  /// every unsaved draft (true when there is no store).
  ///
  /// Writes run one at a time, in the order the drafts changed, but they are
  /// asynchronous: the app can stop before they land. Await this before
  /// telling the user their changes are kept, or before leaving a screen.
  Future<bool> whenDraftsStored() => _drafts.whenStored();

  /// Draft keys whose last [draftStore] write failed, with the error. Each
  /// failure is also reported to [FlutterError]; a later successful write
  /// of the key clears it.
  Map<String, Object> get draftStoreErrors => _drafts.storeErrors;

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
  /// Set [notify] to false when releasing resources during [State.dispose]
  /// or a build, where notifying an [InheritedNotifier] would fail; listeners
  /// are then notified after the frame.
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
    } else {
      _notifyAfterFrame();
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

  /// Closes every open editor and commits its changed text, as switching to
  /// another cell does under [LazyTextFieldSwitchPolicy.commit] (whatever
  /// [switchPolicy] is): `onCommit` cells queue a save (or keep an unsaved
  /// draft in [LazyTextFieldSaveMode.deferred]); `onSave` cells call it.
  ///
  /// Editors without a commit handler (custom cells that never called
  /// [setCommitHandler]) are only closed.
  void commitAll() {
    for (final cellId in _controllers.keys.toList(growable: false)) {
      final handler = _commitHandlers[cellId];
      final text = _controllers[cellId]?.text;
      try {
        if (handler != null && text != null) handler(text);
      } finally {
        stopEditing(cellId);
      }
    }
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

  /// Notifies once after the current frame, for changes made where
  /// notifying is not allowed (State.dispose, build), so listeners such as
  /// draft counters still see them.
  void _notifyAfterFrame() {
    if (_notifyScheduled || _disposed) return;
    _notifyScheduled = true;
    SchedulerBinding.instance
      ..addPostFrameCallback((_) {
        _notifyScheduled = false;
        notifyListeners();
      })
      ..ensureVisualUpdate();
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
    _drafts.dispose();
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
