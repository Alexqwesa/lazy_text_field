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

  late final LazyTextFieldDraftQueue _drafts = LazyTextFieldDraftQueue(
    saveOrder: saveOrder,
    notify: notifyListeners,
    onSettled: onSavesSettled,
  );

  /// Number of commits queued or running.
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
  /// Set [notify] to false when calling from [State.dispose]; [commit] always
  /// runs asynchronously.
  Future<bool> enqueue({
    required Object key,
    required String source,
    required String value,
    required LazyTextFieldCommit commit,
    Object? rowKey,
    bool notify = true,
  }) => _drafts.enqueue(
    key: key,
    source: source,
    value: value,
    commit: commit,
    rowKey: rowKey,
    notify: notify,
  );

  /// Shows [value] as the draft for [key] while a save you run yourself is in
  /// progress, and keeps it if the save fails.
  ///
  /// [save] runs right away (in a microtask), outside the save queue, and
  /// does not count towards [pendingSaves]. Returning true marks the draft
  /// saved; returning false or throwing marks it failed (with the thrown
  /// error, if any). [ScopedLazyTextField] uses this for `onSave` when an
  /// editor closes without a submit. Set [notify] to false when calling from
  /// [State.dispose].
  Future<bool> trackDraft({
    required Object key,
    required String source,
    required String value,
    required Future<bool> Function() save,
    bool notify = true,
  }) => _drafts.track(
    key: key,
    source: source,
    value: value,
    save: save,
    notify: notify,
  );

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
