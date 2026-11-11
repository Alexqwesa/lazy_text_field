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
  /// When the scope's controller uses [LazyTextFieldSwitchPolicy.commit],
  /// this is also called with the draft when another cell starts editing.
  /// That editor is already closed, so returning false only skips [onSaved].
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
  late final LazyTextFieldCommitHandler _commitHandler = _commitOnSwitch;

  @override
  void didUpdateWidget(covariant ScopedLazyTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.cellId != widget.cellId) {
      _invalidateEditSession();
      _detachKeyboardHandler();
      _editController?.stopEditing(oldWidget.cellId);
    }
  }

  @override
  void dispose() {
    _invalidateEditSession();
    _detachKeyboardHandler();
    // Virtualized lists must release shared edit resources when the cell
    // leaves the tree; retention would orphan controllers across recycle.
    // Skip notify: InheritedNotifier cannot markNeedsBuild while locked.
    _editController?.stopEditing(widget.cellId, notify: false);
    super.dispose();
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
      onChanged: drafts == null ? widget.onChanged : _handleDraftChanged,
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

  /// The controller when this cell commits through drafts, else null.
  LazyTextFieldEditController? get _drafts =>
      widget.onCommit == null ? null : _editController;

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
    if (!(_editController?.isEditing(widget.cellId) ?? false)) return;
    if (widget.onCommit != null) return _commit(value, fromSwitch: false);
    if (_saveInFlight) return;
    _saveInFlight = true;
    _inFlightValue = value;
    final epoch = _editEpoch;
    final cellId = widget.cellId;
    final ok = await widget.onSave!(value);
    if (!mounted || epoch != _editEpoch || widget.cellId != cellId) return;
    _saveInFlight = false;
    _inFlightValue = null;
    if (!ok) return;
    _editController?.stopEditing(widget.cellId);
    widget.onSaved?.call(value);
  }

  /// Called by the controller while it closes this editor for another cell.
  void _commitOnSwitch(String value) {
    if (widget.onCommit != null) {
      unawaited(_commit(value, fromSwitch: true));
      return;
    }
    // A submit of the same text is already running and will call onSaved.
    if (_saveInFlight && _inFlightValue == value) return;
    final cellId = widget.cellId;
    unawaited(() async {
      final ok = await widget.onSave!(value);
      if (!ok || !mounted || widget.cellId != cellId) return;
      widget.onSaved?.call(value);
    }());
  }

  Future<void> _commit(String value, {required bool fromSwitch}) async {
    final drafts = _drafts;
    final editController = _editController;
    if (drafts == null || editController == null) return;
    final cellId = widget.cellId;
    final key = _draftKey;
    final draft = drafts.draftFor(key);
    // Whoever queued this value is already waiting for it.
    if (draft?.status == LazyTextFieldDraftStatus.pending &&
        draft?.value == value) {
      return;
    }
    final unchanged =
        value == (_editStartValue ?? _displayText()) &&
        draft?.status != LazyTextFieldDraftStatus.failed;
    if (unchanged) {
      if (!fromSwitch) editController.stopEditing(cellId);
      return;
    }

    final editor = editController.controllerFor(cellId);
    final epoch = _editEpoch;
    final saved = drafts.enqueue(
      key: key,
      source: widget.text,
      value: value,
      commit: widget.onCommit!,
      rowKey: widget.rowKey,
    );
    final closeAfterSave =
        !fromSwitch &&
        widget.closeOnSubmit == LazyTextFieldSubmitClose.afterSave;
    if (!fromSwitch && !closeAfterSave) editController.stopEditing(cellId);
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
    final drafts = _drafts;
    final key = _draftKey;
    if (drafts?.draftFor(key)?.status == LazyTextFieldDraftStatus.failed) {
      drafts!.clearDraft(key);
    }
    widget.onCancel?.call();
  }

  void _invalidateEditSession() {
    _editEpoch++;
    _saveInFlight = false;
    _inFlightValue = null;
  }
}
