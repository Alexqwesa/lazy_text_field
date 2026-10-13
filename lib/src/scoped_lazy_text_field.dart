import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lazy_text_field/src/lazy_text_field.dart';
import 'package:lazy_text_field/src/lazy_text_field_controller_scope.dart';
import 'package:lazy_text_field/src/lazy_text_field_edit_controller.dart';
import 'package:lazy_text_field/src/stateful_lazy_text_field.dart';

/// [LazyTextField] cell wired to a shared [LazyTextFieldEditController].
///
/// Must be placed under a [LazyTextFieldControllerScope].
class ScopedLazyTextField extends StatefulWidget {
  /// Creates a lazy text field backed by the nearest controller scope.
  const ScopedLazyTextField({
    required this.cellId,
    required this.text,
    required this.onSave,
    super.key,
    this.singleLine = false,
    this.style,
    this.textAlignVertical,
    this.decoration = const InputDecoration(),
    this.minHeight = 0,
    this.maxHeight,
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
  });

  /// Stable id used by the shared edit controller.
  final String cellId;

  /// Current read-only text value.
  final String text;

  /// Primary commit path: return true to accept and exit edit mode, or false
  /// to keep editing (e.g. validation failed).
  final LazyTextFieldSave onSave;

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

  /// Minimum text viewport height.
  ///
  /// Set this to the same finite value as [maxHeight] to activate fixed-height
  /// sizing for uniform rows.
  final double minHeight;

  /// Maximum text viewport height before vertical overflow is clipped.
  final double? maxHeight;

  /// Width reserved for the package scrollbar in bounded edit mode.
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
      _editController = editController;
    }

    final controller = editController.controllerFor(widget.cellId);
    final focusNode = editController.focusNodeFor(widget.cellId);
    final isEditing = controller != null && focusNode != null;
    if (isEditing) {
      _attachKeyboardHandler(focusNode);
    } else {
      _detachKeyboardHandler();
    }

    return LazyTextField(
      cellId: widget.cellId,
      text: widget.text,
      isEditing: isEditing,
      controller: controller,
      focusNode: focusNode,
      singleLine: widget.singleLine,
      style: widget.style,
      textAlignVertical: widget.textAlignVertical,
      decoration: widget.decoration,
      minHeight: widget.minHeight,
      maxHeight: widget.maxHeight,
      scrollbarGutter: widget.scrollbarGutter,
      scrollbarThickness: widget.scrollbarThickness,
      scrollbarAlignment: widget.scrollbarAlignment,
      readOnlyAsLink: widget.readOnlyAsLink,
      inputFormatters: widget.inputFormatters,
      onChanged: widget.onChanged,
      keyboardType: widget.keyboardType,
      textInputAction: widget.textInputAction,
      maxLength: widget.maxLength,
      errorMessage: widget.errorMessage,
      onStartEditing: () => unawaited(_startEditing(editController)),
      onStartEditingWithDetails: (details) => unawaited(
        _startEditing(editController, textOffset: details.textOffset),
      ),
      onSubmitted: (value) => unawaited(_save(value)),
      onTapOutside: (_) => unawaited(_save(controller?.text ?? widget.text)),
    );
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
    editController.startEditing(
      cellId: widget.cellId,
      initialValue: widget.text,
      allowMultipleActiveEdits: widget.allowMultipleActiveEdits,
      startEditSelection: widget.startEditSelection,
      textOffset: textOffset,
    );
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
    if (_saveInFlight || !(_editController?.isEditing(widget.cellId) ?? false)) {
      return;
    }
    _saveInFlight = true;
    final epoch = _editEpoch;
    final cellId = widget.cellId;
    final ok = await widget.onSave(value);
    if (!mounted || epoch != _editEpoch || widget.cellId != cellId) return;
    _saveInFlight = false;
    if (!ok) return;
    _editController?.stopEditing(widget.cellId);
    widget.onSaved?.call(value);
  }

  void _cancel() {
    _invalidateEditSession();
    _editController?.stopEditing(widget.cellId);
    widget.onCancel?.call();
  }

  void _invalidateEditSession() {
    _editEpoch++;
    _saveInFlight = false;
  }
}
