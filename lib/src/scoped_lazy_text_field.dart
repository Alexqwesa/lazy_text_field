import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lazy_text_field/src/lazy_text_field.dart';
import 'package:lazy_text_field/src/lazy_text_field_controller_scope.dart';
import 'package:lazy_text_field/src/lazy_text_field_drafts.dart';
import 'package:lazy_text_field/src/lazy_text_field_edit_controller.dart';
import 'package:lazy_text_field/src/stateful_lazy_text_field.dart';

/// [LazyTextField] cell wired to a shared [LazyTextFieldEditController].
///
/// Must be placed under a [LazyTextFieldControllerScope].
class ScopedLazyTextField extends StatefulWidget {
  /// Creates a lazy text field backed by the nearest controller scope.
  ///
  /// Provide exactly one of [onSave] or [onCommit].
  const ScopedLazyTextField({
    required this.cellId,
    required this.text,
    this.onSave,
    this.onCommit,
    this.draftKey,
    this.rowKey,
    this.closeOnSubmit = LazyTextFieldSubmitClose.afterSave,
    this.errorMessageOf,
    super.key,
    this.singleLine = false,
    this.style,
    this.textAlignVertical,
    this.decoration = const InputDecoration(),
    this.minHeight = 0,
    this.maxHeight,
    this.editingMaxHeight,
    this.onEditingExtraHeightChanged,
    this.scrollbarGutter = 12,
    this.scrollbarThickness = 6,
    this.scrollbarAlignment = LazyTextField.defaultScrollbarAlignment,
    this.startEditSelection = LazyTextFieldStartEditSelection.end,
    this.readOnlyAsLink = false,
    this.allowMultipleActiveEdits = false,
    this.inputFormatters,
    this.onChanged,
    this.keyboardType,
    this.textInputAction,
    this.maxLength,
    this.errorMessage,
    this.onWillStartEditing,
    this.onCancel,
    this.onSaved,
  }) : assert(
         (onSave == null) != (onCommit == null),
         'Provide exactly one of onSave or onCommit.',
       );

  /// Stable id used by the shared edit controller.
  final String cellId;

  /// Current read-only text value.
  final String text;

  /// Primary commit path: return true to accept and exit edit mode, or false
  /// to keep editing (e.g. validation failed).
  ///
  /// Under [LazyTextFieldSwitchPolicy.commit] (the default), an editor that
  /// closes because another cell starts editing also calls this with its
  /// changed text. That editor is already closed, so the text is kept as a
  /// draft: shown while saving, and kept as a failed draft if this returns
  /// false or throws. Reopening the cell restores it; Escape discards it.
  ///
  /// An editor whose cell leaves the tree (recycled, or disposed by a
  /// virtualized grid) does not call this: its text is kept as an
  /// [LazyTextFieldDraftStatus.unsaved] draft, saved when another cell starts
  /// editing or by [LazyTextFieldEditController.saveDrafts]. If neither
  /// happens, it is never saved.
  ///
  /// Return false to reject; a throw is reported to [FlutterError] and
  /// treated as a rejection.
  ///
  /// Calls go through the controller's save queue
  /// ([LazyTextFieldEditController.saveOrder]): a save of this cell starts
  /// only after its earlier save finished, so an older value cannot land
  /// after a newer one. Under the default
  /// [LazyTextFieldSaveOrder.sequential], a submit also waits for saves of
  /// other cells; the editor stays open meanwhile.
  final LazyTextFieldSave? onSave;

  /// Background commit path through the scope's save queue.
  ///
  /// The committed text becomes a draft that the cell keeps showing while it
  /// saves, and after it saved until [text] changes. Complete normally on
  /// success; throw to mark the draft failed. Commits are queued by the
  /// controller's [LazyTextFieldEditController.saveOrder].
  ///
  /// Submitting unchanged text closes the editor without a commit, unless the
  /// draft failed (then it retries).
  final LazyTextFieldCommit? onCommit;

  /// Identifies this cell's draft in the [LazyTextFieldEditController].
  ///
  /// Defaults to [cellId]. Use a shared key when the same value is shown in
  /// several cells.
  final Object? draftKey;

  /// Row identity for [LazyTextFieldSaveOrder.perRow]; ignored otherwise.
  ///
  /// Without it, the cell saves in the queue shared by cells without a row.
  final Object? rowKey;

  /// When an explicit submit (Enter, Ctrl+S, tap outside) closes the editor
  /// with [onCommit].
  ///
  /// Switching to another cell always closes the editor immediately.
  final LazyTextFieldSubmitClose closeOnSubmit;

  /// Turns a failed commit's error into the message shown while this cell
  /// is editing. Defaults to `error.toString()`. [errorMessage] takes
  /// precedence.
  final String Function(Object error)? errorMessageOf;

  /// Whether the field should lay out and edit as one line.
  ///
  /// When true, read-only text is ellipsized to a single line and the editor
  /// rejects newline characters (including paste).
  final bool singleLine;

  /// Text style used in both read-only and edit modes.
  final TextStyle? style;

  /// Vertical text alignment used by the native [InputDecorator].
  final TextAlignVertical? textAlignVertical;

  /// Native Material decoration shared by read-only and editing modes.
  final InputDecoration? decoration;

  /// {@macro lazy_text_field.minHeight}
  final double minHeight;

  /// {@macro lazy_text_field.maxHeight}
  final double? maxHeight;

  /// {@macro lazy_text_field.editingMaxHeight}
  final double? editingMaxHeight;

  /// {@macro lazy_text_field.onEditingExtraHeightChanged}
  final ValueChanged<double>? onEditingExtraHeightChanged;

  /// Width reserved for the editor's scrollbar when [maxHeight] is finite.
  ///
  /// Reserved in both modes, so read-only and editing text wrap the same way.
  final double scrollbarGutter;

  /// Thickness of the package scrollbar thumb.
  final double scrollbarThickness;

  /// Alignment of the package scrollbar thumb inside its gutter.
  final AlignmentGeometry scrollbarAlignment;

  /// Selection policy applied when editing starts.
  final LazyTextFieldStartEditSelection startEditSelection;

  /// Whether read-only text should use link-like cursor/gesture behavior.
  final bool readOnlyAsLink;

  /// Whether this field can edit while other scoped fields remain active.
  final bool allowMultipleActiveEdits;

  /// Passed through to the internal [TextField.inputFormatters].
  final List<TextInputFormatter>? inputFormatters;

  /// Live edit callback; does not commit.
  ///
  /// Use [onSave] to accept or reject the value when editing ends.
  final ValueChanged<String>? onChanged;

  /// Passed through to the internal [TextField.keyboardType].
  final TextInputType? keyboardType;

  /// Passed through to the internal [TextField.textInputAction].
  final TextInputAction? textInputAction;

  /// Passed through to the internal [TextField.maxLength].
  final int? maxLength;

  /// Validation message shown in a layout-stable popup below the field.
  ///
  /// Prefer this over [InputDecoration.errorText] so commit failures do not
  /// change field height. Keep using [onSave] as the commit gate.
  final String? errorMessage;

  /// Optional guard called before edit resources are created.
  final FutureOr<bool> Function()? onWillStartEditing;

  /// Called when editing is canceled with Escape.
  final VoidCallback? onCancel;

  /// Called after [onSave] accepts a value.
  final ValueChanged<String>? onSaved;

  @override
  State<ScopedLazyTextField> createState() => _ScopedLazyTextFieldState();
}

class _ScopedLazyTextFieldState extends State<ScopedLazyTextField> {
  LazyTextFieldEditController? _editController;
  FocusNode? _attachedFocusNode;
  FocusOnKeyEventCallback? _previousHandler;
  int _editEpoch = 0;
  bool _saveInFlight = false;
  String? _inFlightValue;
  String? _editStartValue;
  LazyTextFieldDraft? _dismissedErrorDraft;
  // The editor a running onSave submit came from, and its result.
  TextEditingController? _inFlightEditor;
  Future<bool>? _inFlightSave;
  late final LazyTextFieldCommitHandler _commitHandler = _commitOnSwitch;

  @override
  void didUpdateWidget(covariant ScopedLazyTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.cellId != widget.cellId) {
      // A recycled cell: the old cell's text is kept as an unsaved draft.
      // This runs during build, where notifying the scope would mark an
      // ancestor dirty; this cell rebuilds anyway.
      _detachKeyboardHandler();
      _releaseEditor(oldWidget, notify: false);
      _invalidateEditSession();
    }
  }

  @override
  void dispose() {
    _detachKeyboardHandler();
    // Virtualized lists dispose cells that scroll away. Release the shared
    // edit resources and keep the text as an unsaved draft, which survives
    // the cell; leaving the tree is not a request to save. Skip notify:
    // InheritedNotifier cannot markNeedsBuild while the tree is locked.
    _releaseEditor(widget, notify: false);
    _invalidateEditSession();
    super.dispose();
  }

  /// Closes [config]'s editor and, under [LazyTextFieldSwitchPolicy.commit],
  /// keeps changed text as an unsaved draft.
  void _releaseEditor(ScopedLazyTextField config, {required bool notify}) {
    final editController = _editController;
    final editor = editController?.controllerFor(config.cellId);
    if (editController == null || editor == null) return;
    final value = editor.text;
    if (editController.switchPolicy == LazyTextFieldSwitchPolicy.commit &&
        _needsSave(editController, config, value)) {
      _hold(editController, config, value, notify: false);
    }
    editController.stopEditing(config.cellId, notify: notify);
  }

  /// Whether [value] from [config]'s editor differs from what is saved or
  /// being saved.
  bool _needsSave(
    LazyTextFieldEditController editController,
    ScopedLazyTextField config,
    String value,
  ) {
    final key = config.draftKey ?? config.cellId;
    final draft = editController.draftFor(key);
    return switch (draft?.status) {
      // Whoever queued this value is already waiting for it.
      LazyTextFieldDraftStatus.pending => draft!.value != value,
      LazyTextFieldDraftStatus.unsaved ||
      LazyTextFieldDraftStatus.failed => true,
      _ =>
        value !=
            (_editStartValue ?? editController.displayText(key, config.text)),
    };
  }

  void _hold(
    LazyTextFieldEditController editController,
    ScopedLazyTextField config,
    String value, {
    required bool notify,
  }) {
    editController.holdDraft(
      key: config.draftKey ?? config.cellId,
      source: config.text,
      value: value,
      saver: _saverFor(editController, config),
      notify: notify,
    );
  }

  /// Saves a draft of [config]'s cell later, after the cell may be gone.
  static LazyTextFieldDraftSaver _saverFor(
    LazyTextFieldEditController editController,
    ScopedLazyTextField config,
  ) {
    final key = config.draftKey ?? config.cellId;
    if (config.onCommit case final commit?) {
      final rowKey = config.rowKey;
      return (draft) => editController.enqueue(
        key: key,
        source: draft.baseText,
        value: draft.value,
        commit: commit,
        rowKey: rowKey,
      );
    }
    final onSave = config.onSave!;
    final cellId = config.cellId;
    final rowKey = config.rowKey;
    return (draft) => editController.trackDraft(
      key: key,
      source: draft.baseText,
      value: draft.value,
      save: () => _runOnSave(onSave, draft.value, cellId),
      rowKey: rowKey,
    );
  }

  @override
  Widget build(BuildContext context) {
    final editController = LazyTextFieldControllerScope.of(context);
    if (_editController != editController) {
      _detachKeyboardHandler();
      _editController?.removeCommitHandler(widget.cellId, _commitHandler);
      _editController = editController;
    }

    final controller = editController.controllerFor(widget.cellId);
    final focusNode = editController.focusNodeFor(widget.cellId);
    final isEditing = controller != null && focusNode != null;
    if (isEditing) {
      _attachKeyboardHandler(focusNode);
      editController.setCommitHandler(widget.cellId, _commitHandler);
    } else {
      _detachKeyboardHandler();
    }

    final drafts = _drafts;
    final text = _displayText();
    final draft = drafts?.draftFor(_draftKey);
    if (draft?.status == LazyTextFieldDraftStatus.unsaved ||
        draft?.status == LazyTextFieldDraftStatus.failed) {
      // Lets saveDrafts save a draft kept or restored before this build.
      editController.setDraftSaver(
        _draftKey,
        _saverFor(editController, widget),
      );
    }
    final draftError =
        isEditing &&
            draft?.status == LazyTextFieldDraftStatus.failed &&
            !identical(draft, _dismissedErrorDraft)
        ? draft!.error
        : null;
    final errorMessage =
        widget.errorMessage ??
        (draftError == null
            ? null
            : widget.errorMessageOf?.call(draftError) ?? '$draftError');

    return LazyTextField(
      cellId: widget.cellId,
      text: text,
      isEditing: isEditing,
      controller: controller,
      focusNode: focusNode,
      singleLine: widget.singleLine,
      style: widget.style,
      textAlignVertical: widget.textAlignVertical,
      decoration: widget.decoration,
      minHeight: widget.minHeight,
      maxHeight: widget.maxHeight,
      editingMaxHeight: widget.editingMaxHeight,
      onEditingExtraHeightChanged: widget.onEditingExtraHeightChanged,
      scrollbarGutter: widget.scrollbarGutter,
      scrollbarThickness: widget.scrollbarThickness,
      scrollbarAlignment: widget.scrollbarAlignment,
      readOnlyAsLink: widget.readOnlyAsLink,
      inputFormatters: widget.inputFormatters,
      onChanged: _handleDraftChanged,
      keyboardType: widget.keyboardType,
      textInputAction: widget.textInputAction,
      maxLength: widget.maxLength,
      errorMessage: errorMessage,
      onStartEditing: () => unawaited(_startEditing(editController)),
      onStartEditingWithDetails: (details) => unawaited(
        _startEditing(editController, textOffset: details.textOffset),
      ),
      onSubmitted: (value) => unawaited(_save(value)),
      onTapOutside: (_) => unawaited(_save(controller?.text ?? text)),
    );
  }

  /// The scope's controller, which also holds this cell's draft.
  LazyTextFieldEditController? get _drafts => _editController;

  Object get _draftKey => widget.draftKey ?? widget.cellId;

  String _displayText() =>
      _drafts?.displayText(_draftKey, widget.text) ?? widget.text;

  void _handleDraftChanged(String value) {
    // Typing hides the failed save's error until the next commit.
    final draft = _drafts?.draftFor(_draftKey);
    if (draft?.status == LazyTextFieldDraftStatus.failed &&
        !identical(draft, _dismissedErrorDraft)) {
      setState(() => _dismissedErrorDraft = draft);
    }
    widget.onChanged?.call(value);
  }

  Future<void> _startEditing(
    LazyTextFieldEditController editController, {
    int? textOffset,
  }) async {
    final epoch = _editEpoch;
    final cellId = widget.cellId;
    final allowed = await Future<bool>.value(
      widget.onWillStartEditing?.call() ?? true,
    );
    if (!allowed ||
        !mounted ||
        epoch != _editEpoch ||
        widget.cellId != cellId ||
        !identical(_editController, editController)) {
      return;
    }
    final initialValue = _displayText();
    _editStartValue = initialValue;
    editController.startEditing(
      cellId: widget.cellId,
      initialValue: initialValue,
      allowMultipleActiveEdits: widget.allowMultipleActiveEdits,
      startEditSelection: widget.startEditSelection,
      textOffset: textOffset,
      draftKey: _draftKey,
    );
    // Register now: a switch can arrive before the rebuild that would do it.
    editController.setCommitHandler(widget.cellId, _commitHandler);
  }

  void _attachKeyboardHandler(FocusNode focusNode) {
    if (_attachedFocusNode == focusNode) return;
    _detachKeyboardHandler();
    _attachedFocusNode = focusNode;
    _previousHandler = focusNode.onKeyEvent;
    focusNode.onKeyEvent = _handleKeyEvent;
  }

  void _detachKeyboardHandler() {
    final focusNode = _attachedFocusNode;
    if (focusNode != null && focusNode.onKeyEvent == _handleKeyEvent) {
      focusNode.onKeyEvent = _previousHandler;
    }
    _attachedFocusNode = null;
    _previousHandler = null;
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return _previousHandler?.call(node, event) ?? KeyEventResult.ignored;
    }
    final controller = _editController?.controllerFor(widget.cellId);
    if (controller == null) return KeyEventResult.ignored;

    final isEnter =
        event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter;
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      _cancel();
      return KeyEventResult.handled;
    }
    if ((HardwareKeyboard.instance.isControlPressed &&
            event.logicalKey == LogicalKeyboardKey.keyS) ||
        (HardwareKeyboard.instance.isControlPressed && isEnter) ||
        (widget.singleLine && isEnter)) {
      unawaited(_save(controller.text));
      return KeyEventResult.handled;
    }
    return _previousHandler?.call(node, event) ?? KeyEventResult.ignored;
  }

  Future<void> _save(String value) async {
    final editController = _editController;
    final editor = editController?.controllerFor(widget.cellId);
    if (editController == null || editor == null) return;
    if (widget.onCommit != null) return _commit(value);
    // One running save per editor. A reopened editor may submit again.
    if (_saveInFlight && identical(_inFlightEditor, editor)) return;
    final epoch = _editEpoch;
    final cellId = widget.cellId;
    final key = _draftKey;
    final onSave = widget.onSave!;
    // Through the save queue: it starts after earlier saves of this cell, so
    // an older value cannot overwrite this one.
    final save = editController.queueSave(
      key: key,
      value: value,
      save: () => _runOnSave(onSave, value, cellId),
      rowKey: widget.rowKey,
    );
    _saveInFlight = true;
    _inFlightValue = value;
    _inFlightEditor = editor;
    _inFlightSave = save;
    final ok = await save;
    if (identical(_inFlightSave, save)) _clearInFlight();
    if (!ok || !mounted || epoch != _editEpoch || widget.cellId != cellId) {
      return;
    }
    final kept = editController.draftFor(key)?.status;
    if (kept == LazyTextFieldDraftStatus.failed ||
        kept == LazyTextFieldDraftStatus.unsaved) {
      editController.clearDraft(key);
    }
    // Close only the editor that submitted: a switch may have closed it and
    // the cell may be editing again.
    if (identical(editController.controllerFor(cellId), editor)) {
      editController.stopEditing(cellId);
    }
    widget.onSaved?.call(value);
  }

  /// Called by the controller while it closes this editor for another cell.
  void _commitOnSwitch(String value) {
    final editController = _editController;
    final editor = editController?.controllerFor(widget.cellId);
    if (editController == null || editor == null) return;
    _commitClosed(editController, widget, editor, value, notify: true);
  }

  /// Saves [value] from [editor], which is closing because another cell
  /// started editing. The value is kept as a draft, so it stays visible, and
  /// stays after a failed save. In [LazyTextFieldSaveMode.deferred], `onCommit`
  /// cells only keep it.
  void _commitClosed(
    LazyTextFieldEditController editController,
    ScopedLazyTextField config,
    TextEditingController editor,
    String value, {
    required bool notify,
  }) {
    if (!_needsSave(editController, config, value)) return;
    final cellId = config.cellId;
    final key = config.draftKey ?? cellId;

    void savedCallback(bool saved) {
      if (saved && mounted && widget.cellId == cellId) {
        widget.onSaved?.call(value);
      }
    }

    if (config.onCommit case final commit?) {
      if (editController.saveMode == LazyTextFieldSaveMode.deferred) {
        _hold(editController, config, value, notify: notify);
        return;
      }
      unawaited(
        editController
            .enqueue(
              key: key,
              source: config.text,
              value: value,
              commit: commit,
              rowKey: config.rowKey,
              notify: notify,
            )
            .then(savedCallback),
      );
      return;
    }

    // A submit of this text from this editor is already queued: the queue
    // reuses that save instead of saving twice, and that submit calls
    // onSaved.
    final submitted =
        _saveInFlight &&
        identical(_inFlightEditor, editor) &&
        _inFlightValue == value;
    final onSave = config.onSave!;
    final tracked = editController.trackDraft(
      key: key,
      source: config.text,
      value: value,
      save: () => _runOnSave(onSave, value, cellId),
      rowKey: config.rowKey,
      notify: notify,
    );
    if (!submitted) unawaited(tracked.then(savedCallback));
  }

  /// Runs [onSave], reporting a throw to [FlutterError] before rethrowing:
  /// `onSave` signals rejection by returning false, so a throw is a bug.
  static Future<bool> _runOnSave(
    LazyTextFieldSave onSave,
    String value,
    String cellId,
  ) async {
    try {
      return await onSave(value);
    } catch (error, stack) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stack,
          library: 'lazy_text_field',
          context: ErrorDescription(
            'while running ScopedLazyTextField.onSave for cell "$cellId"',
          ),
        ),
      );
      rethrow;
    }
  }

  Future<void> _commit(String value) async {
    final editController = _editController;
    if (editController == null) return;
    final cellId = widget.cellId;
    final key = _draftKey;
    final draft = editController.draftFor(key);
    // Whoever queued this value is already waiting for it.
    if (draft?.status == LazyTextFieldDraftStatus.pending &&
        draft?.value == value) {
      return;
    }
    if (!_needsSave(editController, widget, value)) {
      editController.stopEditing(cellId);
      return;
    }
    if (editController.saveMode == LazyTextFieldSaveMode.deferred) {
      _hold(editController, widget, value, notify: true);
      editController.stopEditing(cellId);
      return;
    }

    final editor = editController.controllerFor(cellId);
    final epoch = _editEpoch;
    final saved = editController.enqueue(
      key: key,
      source: widget.text,
      value: value,
      commit: widget.onCommit!,
      rowKey: widget.rowKey,
    );
    final closeAfterSave =
        widget.closeOnSubmit == LazyTextFieldSubmitClose.afterSave;
    if (!closeAfterSave) editController.stopEditing(cellId);
    if (!await saved || !mounted || widget.cellId != cellId) return;
    if (closeAfterSave && epoch == _editEpoch) {
      // Close only the editor that submitted, and only if it was not edited
      // while saving.
      final current = editController.controllerFor(cellId);
      if (current != null && identical(current, editor)) {
        if (current.text == value) editController.stopEditing(cellId);
      }
    }
    widget.onSaved?.call(value);
  }

  void _cancel() {
    _invalidateEditSession();
    _editController?.stopEditing(widget.cellId);
    // Escape discards text that was kept but not saved.
    final drafts = _drafts;
    final key = _draftKey;
    final kept = drafts?.draftFor(key)?.status;
    if (kept == LazyTextFieldDraftStatus.failed ||
        kept == LazyTextFieldDraftStatus.unsaved) {
      drafts!.clearDraft(key);
    }
    widget.onCancel?.call();
  }

  void _invalidateEditSession() {
    _editEpoch++;
    _clearInFlight();
  }

  void _clearInFlight() {
    _saveInFlight = false;
    _inFlightValue = null;
    _inFlightEditor = null;
    _inFlightSave = null;
  }
}
