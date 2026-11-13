import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:lazy_text_field/src/lazy_text_field.dart';
import 'package:lazy_text_field/src/lazy_text_field_drafts.dart';

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
  /// When another cell starts editing, the previous cell's text goes to its
  /// commit handler (since 3.0.0; 2.x dropped it).
  LazyTextFieldEditController({
    this.saveMode = LazyTextFieldSaveMode.immediate,
    this.saveOrder = LazyTextFieldSaveOrder.sequential,
    this.onSavesSettled,
    this.draftStore,
    this.storeOpenEditsAfter,
  });

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
  /// A draft is written only when it says which record it belongs to: its
  /// key is a [LazyTextFieldDraftId] with a table, row, and field, and it
  /// has a version (for example the row's `updatedAt`). Set `tableId` on the
  /// [LazyTextFieldControllerScope], `rowId` and `version` on a
  /// `LazyTextFieldRowScope` (or the cell), and `fieldId` on each cell. A
  /// draft missing any of them is never written: it is kept in memory only,
  /// reported to [FlutterError] once (in release builds too), and makes
  /// [whenDraftsStored] return false while it exists. Call [loadDrafts] at
  /// startup to restore stored drafts.
  final LazyTextFieldDraftStore? draftStore;

  /// How long after the last keystroke the text of open editors is written
  /// to [draftStore] ([storeOpenEdits]); null (default) writes it only when
  /// an editor closes or [storeOpenEdits] is called.
  ///
  /// Without it, text in an open editor reaches the store only when the
  /// editor closes, so an app killed while the user types loses that text.
  final Duration? storeOpenEditsAfter;

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
  final Map<String, LazyTextFieldCommitHandler> _keepHandlers =
      <String, LazyTextFieldCommitHandler>{};
  final Map<String, _OpenEdit> _openEdits = <String, _OpenEdit>{};
  Timer? _storeOpenEditsTimer;
  int _editRequest = 0;
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
  /// cell closes it.
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

  /// Registers [handler] to keep [cellId]'s text as an
  /// [LazyTextFieldDraftStatus.unsaved] draft without saving it (for
  /// example with [holdDraft]).
  ///
  /// `saveDrafts(batch: ...)` calls it for open editors, so their text goes
  /// out in the batch. An open editor without one is committed with its
  /// commit handler instead, which saves it on its own.
  ///
  /// Only active cells can register. The handler is removed when the cell
  /// stops editing.
  void setKeepHandler(String cellId, LazyTextFieldCommitHandler handler) {
    if (!_controllers.containsKey(cellId)) return;
    _keepHandlers[cellId] = handler;
  }

  /// Removes [cellId]'s keep handler if it is still [handler].
  void removeKeepHandler(String cellId, LazyTextFieldCommitHandler handler) {
    if (identical(_keepHandlers[cellId], handler)) {
      _keepHandlers.remove(cellId);
    }
  }

  /// Starts a request to edit a cell, for a cell that waits for something
  /// (such as an asynchronous permission check) before it calls
  /// [startEditing]. Pass the result to [isLatestEditRequest] after the wait.
  ///
  /// A later request, or a [startEditing] call, from any cell of this
  /// controller supersedes it: the user's last click wins.
  int beginEditRequest() => ++_editRequest;

  /// Whether no cell requested or started editing since [request] (from
  /// [beginEditRequest]). If one did, do not start editing: the user has
  /// moved on.
  bool isLatestEditRequest(int request) => request == _editRequest;

  /// Starts editing [cellId] and returns its active controller.
  ///
  /// Unless [allowMultipleActiveEdits] is true, other active cells are stopped
  /// before this one starts editing. Their text goes to their commit handlers
  /// first, and in [LazyTextFieldSaveMode.immediate] unsaved drafts are
  /// saved, except the one for [draftKey] (default [cellId]), which this
  /// editor continues, and restored ones ([LazyTextFieldDraft.restored]).
  ///
  /// [version] is the record's current version; [storeOpenEdits] writes it
  /// with the editor's text (see [draftStore]).
  TextEditingController startEditing({
    required String cellId,
    required String initialValue,
    bool allowMultipleActiveEdits = false,
    LazyTextFieldStartEditSelection startEditSelection =
        LazyTextFieldStartEditSelection.end,
    int? textOffset,
    Object? draftKey,
    String? version,
  }) {
    // Supersedes edit requests still waiting (see beginEditRequest).
    _editRequest++;
    if (!allowMultipleActiveEdits) {
      _switching = true;
      try {
        _switchFrom(cellId);
      } finally {
        _switching = false;
      }
    }
    if (saveMode == LazyTextFieldSaveMode.immediate) {
      // The user moved on: text kept from cells that left the tree is saved.
      // Restored drafts are not: nobody has committed them yet.
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
    _trackOpenEdit(
      cellId,
      controller,
      draftKey ?? cellId,
      initialValue,
      version,
    );
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
  ///
  /// Text in an open editor is not a draft; [unsavedChanges] includes it.
  Map<Object, LazyTextFieldDraft> get drafts => _drafts.drafts;

  /// Everything not saved yet, one entry per draft key: drafts that are
  /// unsaved, saving, or failed, and open editors whose text differs from
  /// the text they opened with.
  ///
  /// For an open editor that continues a draft, the entry has the editor's
  /// text and the draft. Use it for "you have unsaved changes" prompts and
  /// lists; [hasUnsavedChanges] is the cheap yes/no.
  List<LazyTextFieldUnsavedChange> unsavedChanges() {
    final changes = <Object, LazyTextFieldUnsavedChange>{
      for (final MapEntry(:key, value: draft) in _drafts.drafts.entries)
        if (draft.status != LazyTextFieldDraftStatus.saved)
          key: LazyTextFieldUnsavedChange(
            key: key,
            value: draft.value,
            baseText: draft.baseText,
            baseVersion: draft.baseVersion,
            draft: draft,
          ),
    };
    for (final MapEntry(key: cellId, value: edit) in _openEdits.entries) {
      final text = _controllers[cellId]?.text;
      if (text == null) continue;
      final draft = changes[edit.key]?.draft;
      if (draft == null && text == edit.startText) continue;
      changes[edit.key] = LazyTextFieldUnsavedChange(
        key: edit.key,
        value: text,
        baseText: draft?.baseText ?? edit.baseText,
        baseVersion: draft != null ? draft.baseVersion : edit.baseVersion,
        draft: draft,
        cellId: cellId,
      );
    }
    return List.unmodifiable(changes.values);
  }

  /// Whether anything is not saved yet (see [unsavedChanges]).
  ///
  /// Listeners are notified when an open editor's text first differs from
  /// the text it opened with, and when it matches again; not on every
  /// keystroke.
  bool get hasUnsavedChanges =>
      _openEdits.values.any((edit) => edit.changed) ||
      _drafts.drafts.values.any(
        (draft) => draft.status != LazyTextFieldDraftStatus.saved,
      );

  /// Writes the text of every changed open editor to [draftStore] now,
  /// without closing the editors or saving anything; does nothing without a
  /// store.
  ///
  /// After an app restart, [loadDrafts] brings the text back as a restored
  /// draft. Call it when the app goes to the background, then await
  /// [whenDraftsStored]:
  ///
  /// ```dart
  /// if (state == AppLifecycleState.paused) {
  ///   editController.storeOpenEdits();
  ///   await editController.whenDraftsStored();
  /// }
  /// ```
  ///
  /// An editor whose text is back to what it opened with is removed from
  /// the store again. When an editor closes, the store holds its draft, if
  /// any, as before.
  void storeOpenEdits() {
    _storeOpenEditsTimer?.cancel();
    _storeOpenEditsTimer = null;
    if (draftStore == null) return;
    for (final MapEntry(key: cellId, value: edit) in _openEdits.entries) {
      final text = _controllers[cellId]?.text;
      if (text != null && text != edit.startText) {
        _drafts.storeOpen(edit.key, text, edit.baseText, edit.baseVersion);
      } else {
        _drafts.unstoreOpen(edit.key);
      }
    }
  }

  void _trackOpenEdit(
    String cellId,
    TextEditingController controller,
    Object key,
    String initialValue,
    String? version,
  ) {
    // An editor that continues a draft starts from the draft's base.
    final draft = _drafts.draftFor(key);
    final edit = _OpenEdit(
      key: key,
      startText: initialValue,
      baseText: draft?.baseText ?? initialValue,
      baseVersion: draft != null ? draft.baseVersion : version,
    );
    edit.listener = () => _openEditChanged(controller, edit);
    controller.addListener(edit.listener!);
    _openEdits[cellId] = edit;
  }

  void _openEditChanged(TextEditingController controller, _OpenEdit edit) {
    final text = controller.text;
    // Selection changes notify too; only text matters here.
    if (text == edit.lastText) return;
    edit.lastText = text;
    final changed = text != edit.startText;
    if (changed != edit.changed) {
      edit.changed = changed;
      // A controller's text can be set during a build (updateText).
      if (SchedulerBinding.instance.schedulerPhase ==
          SchedulerPhase.persistentCallbacks) {
        _notifyAfterFrame();
      } else {
        notifyListeners();
      }
    }
    final delay = storeOpenEditsAfter;
    if (delay != null && draftStore != null && !_disposed) {
      _storeOpenEditsTimer?.cancel();
      _storeOpenEditsTimer = Timer(delay, storeOpenEdits);
    }
  }

  /// Keeps [value] as an [LazyTextFieldDraftStatus.unsaved] draft for [key],
  /// to be saved later by [saver].
  ///
  /// [ScopedLazyTextField] uses this when an editor closes without a save
  /// (its cell left the tree, or [LazyTextFieldSaveMode.deferred]). The text
  /// is saved by [saveDrafts] or, in [LazyTextFieldSaveMode.immediate], when
  /// another cell starts editing. **Until then it exists only in memory** (and
  /// in [draftStore], if set): if neither happens, it is never saved.
  ///
  /// [version] is the record's version the text started from; see
  /// [draftStore].
  ///
  /// Set [notify] to false when calling from [State.dispose]; listeners are
  /// then notified after the frame.
  void holdDraft({
    required Object key,
    required String source,
    required String value,
    required LazyTextFieldDraftSaver saver,
    String? version,
    bool notify = true,
  }) {
    _drafts.hold(
      key: key,
      source: source,
      value: value,
      saver: saver,
      version: version,
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
  /// With [includeOpenEdits] (default), open editors are included and close.
  /// Without [batch] they are committed first ([commitAll]). With [batch]
  /// their text is kept as unsaved drafts (see [setKeepHandler]) and goes
  /// out in the batch, not through each cell's own save. The returned future also waits for saves that
  /// were queued before the call, so
  /// [LazyTextFieldSaveDraftsResult.allSaved] is true only when nothing is
  /// left to save, including text changed again while saving
  /// ([LazyTextFieldSaveDraftsResult.remaining]). Cells' `onSaved` run for
  /// the drafts saved through them; a [batch] does not call them.
  Future<LazyTextFieldSaveDraftsResult> saveDrafts({
    LazyTextFieldBatchCommit? batch,
    bool includeOpenEdits = true,
  }) {
    if (includeOpenEdits) {
      if (batch == null) {
        commitAll();
      } else {
        _keepAll();
      }
    }
    return _drafts.saveDrafts(batch: batch);
  }

  /// Restores the drafts in [draftStore] as unsaved drafts, keyed by their
  /// [LazyTextFieldDraftId]; returns how many were restored. Drafts already
  /// in memory win.
  ///
  /// Call it once at startup. A cell shows a restored draft, and registers
  /// how to save it, when it is built with the same draft id. Restored
  /// drafts ([LazyTextFieldDraft.restored]) are not saved when another cell
  /// starts editing: only when the user commits one from its cell, or by
  /// [saveDrafts].
  ///
  /// When several controllers share one store (one per table or screen),
  /// pass [where] so each loads only its own drafts:
  ///
  /// ```dart
  /// await controller.loadDrafts(where: (id) => id.table == 'tasks');
  /// ```
  Future<int> loadDrafts({bool Function(LazyTextFieldDraftId id)? where}) =>
      _drafts.load(where: where);

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
  /// [source] is the cell's source text at commit time, and [version] the
  /// record's version (see [draftStore]). [rowKey] picks the queue under
  /// [LazyTextFieldSaveOrder.perRow]. Returns whether the commit
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
    String? version,
    bool notify = true,
  }) {
    final result = _drafts.enqueue(
      key: key,
      source: source,
      value: value,
      commit: commit,
      rowKey: rowKey,
      version: version,
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
    String? version,
    bool notify = true,
  }) {
    final result = _drafts.track(
      key: key,
      source: source,
      value: value,
      save: save,
      rowKey: rowKey,
      version: version,
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
  Map<Object, Object> get draftStoreErrors => _drafts.storeErrors;

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
    _keepHandlers.remove(cellId);
    final controller = _controllers.remove(cellId);
    final focusNode = _focusNodes.remove(cellId);
    final edit = _openEdits.remove(cellId);
    if (edit != null) {
      controller?.removeListener(edit.listener!);
      // The store holds the key's draft again, not the editor's text.
      _drafts.unstoreOpen(edit.key);
    }
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
  /// another cell does: `onCommit` cells queue a save (or keep an unsaved
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

  /// Closes every open editor and keeps its changed text as an unsaved
  /// draft, for a batch. Editors without a keep handler are committed.
  void _keepAll() {
    for (final cellId in _controllers.keys.toList(growable: false)) {
      final handler = _keepHandlers[cellId] ?? _commitHandlers[cellId];
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
        if (handler != null && text != null) handler(text);
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
    _storeOpenEditsTimer?.cancel();
    for (final MapEntry(key: cellId, value: edit) in _openEdits.entries) {
      _controllers[cellId]?.removeListener(edit.listener!);
    }
    _openEdits.clear();
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
    _keepHandlers.clear();
    _completeEditingDone();
    super.dispose();
  }
}

/// An open editor: the draft key it edits, and the text it opened with.
class _OpenEdit {
  _OpenEdit({
    required this.key,
    required this.startText,
    required this.baseText,
    required this.baseVersion,
  }) : lastText = startText;

  final Object key;
  final String startText;
  final String baseText;
  final String? baseVersion;
  String lastText;
  bool changed = false;
  VoidCallback? listener;
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
