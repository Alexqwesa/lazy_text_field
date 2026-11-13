import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lazy_text_field/src/lazy_text_field.dart';
import 'package:lazy_text_field/src/lazy_text_field_shortcuts.dart';
import 'package:lazy_text_field/src/lazy_text_field_controller_scope.dart';
import 'package:lazy_text_field/src/lazy_text_field_drafts.dart';
import 'package:lazy_text_field/src/lazy_text_field_edit_controller.dart';
import 'package:lazy_text_field/src/lazy_text_field_row_scope.dart';
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
    this.fieldId,
    this.rowId,
    this.version,
    this.draftKey,
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
    this.chainEditorScroll = true,
    this.shortcuts,
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
  /// An editor that closes because another cell starts editing also calls
  /// this with its changed text. That editor is already closed, so the text
  /// is kept as a draft: shown while saving, and kept as a failed draft if
  /// this returns false or throws. Reopening the cell restores it; Escape
  /// discards it.
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

  /// The field of the record this cell edits, for example `'title'`.
  ///
  /// With a table ([LazyTextFieldControllerScope.tableId]) and a row
  /// ([rowId] or [LazyTextFieldRowScope.rowId]), the cell's draft key is
  /// `LazyTextFieldDraftId(table: tableId, row: '$rowId', field: fieldId)`:
  /// the draft belongs to the record, not to the cell, so it follows the
  /// record when rows are sorted, filtered, or reloaded, and two tables
  /// never share one. A [LazyTextFieldEditController.draftStore] requires
  /// it, together with a [version].
  final String? fieldId;

  /// The id of the record this cell edits; defaults to the nearest
  /// [LazyTextFieldRowScope.rowId]. Not its position in a list: the id must
  /// stay with the record when rows are sorted, filtered, or reloaded.
  ///
  /// Part of the draft key (see [fieldId]), and the cell's save lane under
  /// [LazyTextFieldSaveOrder.perRow] (ignored by other orders).
  final Object? rowId;

  /// The version of the record [text] comes from, as a token: for example
  /// its `updatedAt` (`row.updatedAt.toIso8601String()`), a revision
  /// number, or an ETag. Defaults to the nearest
  /// [LazyTextFieldRowScope.version].
  ///
  /// Kept with this cell's draft as [LazyTextFieldDraft.baseVersion]: the
  /// version the change started from. A
  /// [LazyTextFieldEditController.draftStore] requires it.
  final String? version;

  /// This cell's draft key, instead of the one made from the scopes and
  /// [fieldId].
  ///
  /// Without it, the key is the [LazyTextFieldDraftId] described at
  /// [fieldId], or [cellId] when the table, row, or field is missing. Pass a
  /// [LazyTextFieldDraftId] here for a cell that cannot use the scopes, or
  /// the same key in cells that show the same value.
  final Object? draftKey;

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

  /// {@macro lazy_text_field.chainEditorScroll}
  final bool chainEditorScroll;

  /// What keys do in the open editor. Null (default) uses the closest
  /// [LazyTextFieldShortcuts] above this field, or
  /// [LazyTextFieldShortcuts.defaults].
  final Map<ShortcutActivator, LazyTextFieldAction>? shortcuts;

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

  /// Called with the value after every successful save of this cell:
  /// [onSave] returned true or [onCommit] completed, whether it ran on
  /// submit, on switch, or later from
  /// [LazyTextFieldEditController.saveDrafts] or a flush.
  ///
  /// It may run after the cell left the tree (scrolled away, recycled), so
  /// do not use this cell's `BuildContext` in it; update your model instead.
  /// Saves through `saveDrafts(batch: ...)` do not call it; read the batch
  /// result or use [LazyTextFieldEditController.onSavesSettled].
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
  late final LazyTextFieldCommitHandler _keepHandler = _keepForBatch;
  // The draft key, row, and version of this cell, from the widget and its
  // scopes; updated before every build.
  _CellDraft? _resolved;

  _CellDraft get _draft => _resolved ?? _CellDraft.of(widget);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolveDraft(widget, release: true);
  }

  @override
  void didUpdateWidget(covariant ScopedLazyTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    final recycled = oldWidget.cellId != widget.cellId;
    if (recycled) {
      // A recycled cell: the old cell's text is kept as an unsaved draft.
      // This runs during build, where notifying the scope would mark an
      // ancestor dirty; this cell rebuilds anyway.
      _detachKeyboardHandler();
      _releaseEditor(oldWidget, _draft, notify: false);
      _invalidateEditSession();
    }
    _resolveDraft(oldWidget, release: !recycled);
  }

  /// Updates [_resolved]. If the draft key changed while the cell id did
  /// not (rows re-sorted under position-based cell ids), the cell now edits
  /// another record, so its open editor's text is kept for the previous
  /// one, with [previousConfig]'s text and save callbacks (that record's).
  void _resolveDraft(
    ScopedLazyTextField previousConfig, {
    required bool release,
  }) {
    final previous = _resolved;
    final next = _CellDraft.resolve(context, widget);
    _resolved = next;
    if (release && previous != null && previous.key != next.key) {
      _detachKeyboardHandler();
      _releaseEditor(previousConfig, previous, notify: false);
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
    _releaseEditor(widget, _draft, notify: false);
    _invalidateEditSession();
    super.dispose();
  }

  /// Closes [config]'s editor and keeps changed text as an unsaved draft
  /// for [cell].
  void _releaseEditor(
    ScopedLazyTextField config,
    _CellDraft cell, {
    required bool notify,
  }) {
    final editController = _editController;
    final editor = editController?.controllerFor(config.cellId);
    if (editController == null || editor == null) return;
    final value = editor.text;
    if (_needsSave(editController, config, cell, value)) {
      _hold(editController, config, cell, value, notify: false);
    }
    editController.stopEditing(config.cellId, notify: notify);
  }

  /// Whether [value] from [config]'s editor differs from what is saved or
  /// being saved.
  bool _needsSave(
    LazyTextFieldEditController editController,
    ScopedLazyTextField config,
    _CellDraft cell,
    String value,
  ) {
    final key = cell.key;
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
    _CellDraft cell,
    String value, {
    required bool notify,
  }) {
    editController.holdDraft(
      key: cell.key,
      source: config.text,
      value: value,
      saver: _saverFor(editController, config, cell),
      version: cell.version,
      notify: notify,
    );
  }

  /// Saves a draft of [config]'s cell later, after the cell may be gone.
  static LazyTextFieldDraftSaver _saverFor(
    LazyTextFieldEditController editController,
    ScopedLazyTextField config,
    _CellDraft cell,
  ) {
    if (config.onCommit case final commit?) {
      return (draft) => editController
          .enqueue(
            key: cell.key,
            source: draft.baseText,
            value: draft.value,
            commit: commit,
            rowKey: cell.rowId,
            version: cell.version,
          )
          .then(_afterSave(config.onSaved, draft.value));
    }
    final onSave = config.onSave!;
    final cellId = config.cellId;
    return (draft) => editController
        .trackDraft(
          key: cell.key,
          source: draft.baseText,
          value: draft.value,
          save: () => _runOnSave(onSave, draft.value, cellId),
          rowKey: cell.rowId,
          version: cell.version,
        )
        .then(_afterSave(config.onSaved, draft.value));
  }

  /// Calls [onSaved] with [value] after a successful save, even when the
  /// cell has left the tree since.
  static bool Function(bool saved) _afterSave(
    ValueChanged<String>? onSaved,
    String value,
  ) => (saved) {
    if (saved) onSaved?.call(value);
    return saved;
  };

  @override
  Widget build(BuildContext context) {
    final editController = LazyTextFieldControllerScope.of(context);
    if (_editController != editController) {
      _detachKeyboardHandler();
      _editController?.removeCommitHandler(widget.cellId, _commitHandler);
      _editController?.removeKeepHandler(widget.cellId, _keepHandler);
      _editController = editController;
    }

    final controller = editController.controllerFor(widget.cellId);
    final focusNode = editController.focusNodeFor(widget.cellId);
    final isEditing = controller != null && focusNode != null;
    if (isEditing) {
      _attachKeyboardHandler(focusNode);
      editController
        ..setCommitHandler(widget.cellId, _commitHandler)
        ..setKeepHandler(widget.cellId, _keepHandler);
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
        _saverFor(editController, widget, _draft),
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
      chainEditorScroll: widget.chainEditorScroll,
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

  Object get _draftKey => _draft.key;

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
    // Another cell clicked while this one waits for onWillStartEditing wins.
    final request = editController.beginEditRequest();
    final allowed = await Future<bool>.value(
      widget.onWillStartEditing?.call() ?? true,
    );
    if (!allowed ||
        !mounted ||
        epoch != _editEpoch ||
        widget.cellId != cellId ||
        !identical(_editController, editController) ||
        !editController.isLatestEditRequest(request)) {
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
      version: _draft.version,
    );
    // Register now: a switch can arrive before the rebuild that would do it.
    editController
      ..setCommitHandler(widget.cellId, _commitHandler)
      ..setKeepHandler(widget.cellId, _keepHandler);
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

    final action = LazyTextFieldShortcuts.actionFor(
      event,
      widget.shortcuts ?? LazyTextFieldShortcuts.of(context),
    );
    if (action == LazyTextFieldAction.cancel) {
      _cancel();
      return KeyEventResult.handled;
    }
    final isEnter =
        event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter;
    if (action == LazyTextFieldAction.save || (widget.singleLine && isEnter)) {
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
    // Submitting the text that is already being saved does nothing. Newer
    // text queues behind it.
    if (_saveInFlight &&
        identical(_inFlightEditor, editor) &&
        _inFlightValue == value) {
      return;
    }
    final epoch = _editEpoch;
    final cellId = widget.cellId;
    final key = _draftKey;
    final onSave = widget.onSave!;
    final onSaved = widget.onSaved;
    // Through the save queue: it starts after earlier saves of this cell, so
    // an older value cannot overwrite this one.
    final save = editController.queueSave(
      key: key,
      value: value,
      save: () => _runOnSave(onSave, value, cellId),
      rowKey: _draft.rowId,
    );
    _saveInFlight = true;
    _inFlightValue = value;
    _inFlightEditor = editor;
    _inFlightSave = save;
    final ok = await save;
    if (identical(_inFlightSave, save)) _clearInFlight();
    if (!ok) return;
    if (mounted && epoch == _editEpoch && widget.cellId == cellId) {
      // Forget a kept draft only if it holds this value; newer text stays.
      final kept = editController.draftFor(key);
      if ((kept?.status == LazyTextFieldDraftStatus.failed ||
              kept?.status == LazyTextFieldDraftStatus.unsaved) &&
          kept!.value == value) {
        editController.clearDraft(key);
      }
      // Close only the editor that submitted (a switch may have closed it
      // and the cell may be editing again), and only if nothing was typed
      // since.
      if (identical(editController.controllerFor(cellId), editor) &&
          editor.text == value) {
        editController.stopEditing(cellId);
      }
    }
    onSaved?.call(value);
  }

  /// Called by the controller while it closes this editor for another cell.
  void _commitOnSwitch(String value) {
    final editController = _editController;
    final editor = editController?.controllerFor(widget.cellId);
    if (editController == null || editor == null) return;
    _commitClosed(editController, widget, _draft, editor, value, notify: true);
  }

  /// Called by the controller for `saveDrafts(batch: ...)`: keeps this
  /// editor's text as an unsaved draft, so it goes out in the batch instead
  /// of through this cell's own save.
  void _keepForBatch(String value) {
    final editController = _editController;
    final editor = editController?.controllerFor(widget.cellId);
    if (editController == null || editor == null) return;
    // A submit of this text from this editor is already saving it.
    if (_saveInFlight &&
        identical(_inFlightEditor, editor) &&
        _inFlightValue == value) {
      return;
    }
    if (_needsSave(editController, widget, _draft, value)) {
      _hold(editController, widget, _draft, value, notify: true);
    }
  }

  /// Saves [value] from [editor], which is closing because another cell
  /// started editing. The value is kept as a draft, so it stays visible, and
  /// stays after a failed save. In [LazyTextFieldSaveMode.deferred], `onCommit`
  /// cells only keep it.
  void _commitClosed(
    LazyTextFieldEditController editController,
    ScopedLazyTextField config,
    _CellDraft cell,
    TextEditingController editor,
    String value, {
    required bool notify,
  }) {
    if (!_needsSave(editController, config, cell, value)) return;
    final cellId = config.cellId;
    final key = cell.key;

    final savedCallback = _afterSave(config.onSaved, value);

    if (config.onCommit case final commit?) {
      if (editController.saveMode == LazyTextFieldSaveMode.deferred) {
        _hold(editController, config, cell, value, notify: notify);
        return;
      }
      unawaited(
        editController
            .enqueue(
              key: key,
              source: config.text,
              value: value,
              commit: commit,
              rowKey: cell.rowId,
              version: cell.version,
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
      rowKey: cell.rowId,
      version: cell.version,
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
    if (!_needsSave(editController, widget, _draft, value)) {
      editController.stopEditing(cellId);
      return;
    }
    if (editController.saveMode == LazyTextFieldSaveMode.deferred) {
      _hold(editController, widget, _draft, value, notify: true);
      editController.stopEditing(cellId);
      return;
    }

    final editor = editController.controllerFor(cellId);
    final epoch = _editEpoch;
    final onSaved = widget.onSaved;
    final saved = editController.enqueue(
      key: key,
      source: widget.text,
      value: value,
      commit: widget.onCommit!,
      rowKey: _draft.rowId,
      version: _draft.version,
    );
    final closeAfterSave =
        widget.closeOnSubmit == LazyTextFieldSubmitClose.afterSave;
    if (!closeAfterSave) editController.stopEditing(cellId);
    if (!await saved) return;
    if (mounted &&
        widget.cellId == cellId &&
        closeAfterSave &&
        epoch == _editEpoch) {
      // Close only the editor that submitted, and only if it was not edited
      // while saving.
      final current = editController.controllerFor(cellId);
      if (current != null && identical(current, editor)) {
        if (current.text == value) editController.stopEditing(cellId);
      }
    }
    onSaved?.call(value);
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

/// A cell's draft key, row, and version, from the cell and its scopes.
@immutable
class _CellDraft {
  const _CellDraft({required this.key, this.rowId, this.version});

  /// From the cell alone, without scopes.
  _CellDraft.of(ScopedLazyTextField cell)
    : key = cell.draftKey ?? cell.cellId,
      rowId = cell.rowId,
      version = cell.version;

  /// From the cell, the nearest [LazyTextFieldRowScope], and the table of
  /// the nearest [LazyTextFieldControllerScope].
  factory _CellDraft.resolve(BuildContext context, ScopedLazyTextField cell) {
    final row = LazyTextFieldRowScope.maybeOf(context);
    final rowId = cell.rowId ?? row?.rowId;
    final table = LazyTextFieldControllerScope.tableIdOf(context);
    final field = cell.fieldId;
    return _CellDraft(
      key:
          cell.draftKey ??
          (table != null && rowId != null && field != null
              ? LazyTextFieldDraftId(table: table, row: '$rowId', field: field)
              : cell.cellId),
      rowId: rowId,
      version: cell.version ?? row?.version,
    );
  }

  final Object key;
  final Object? rowId;
  final String? version;
}
