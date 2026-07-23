import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lazy_text_field/src/lazy_input_decoration.dart';
import 'package:lazy_text_field/src/lazy_text_field.dart';
import 'package:lazy_text_field/src/lazy_text_field_controller_scope.dart';
import 'package:lazy_text_field/src/lazy_text_field_edit_controller.dart';
import 'package:lazy_text_field/src/lazy_text_field_metrics.dart';
import 'package:lazy_text_field/src/stateful_lazy_text_field.dart';

/// [LazyTextField] cell wired to a shared [LazyTextFieldEditController].
///
/// Must be placed under a [LazyTextFieldControllerScope].
class ScopedLazyTextField extends StatefulWidget {
  const ScopedLazyTextField({
    required this.cellId,
    required this.text,
    required this.onSave,
    super.key,
    this.singleLine = false,
    this.style,
    this.padding = kDefaultLazyTextFieldPadding,
    this.decoration = const LazyInputDecoration(),
    this.decorationVisibility = LazyInputDecorationVisibility.editing,
    this.minHeight = 0,
    this.maxHeight,
    this.scrollbarGutter = 12,
    this.readOnlyAsLink = false,
    this.allowMultipleActiveEdits = false,
    this.onWillStartEditing,
    this.onCancel,
    this.onSaved,
  });

  final String cellId;
  final String text;
  final LazyTextFieldSave onSave;
  final bool singleLine;
  final TextStyle? style;
  final EdgeInsetsGeometry padding;
  final LazyInputDecoration? decoration;
  final LazyInputDecorationVisibility decorationVisibility;
  final double minHeight;
  final double? maxHeight;
  final double scrollbarGutter;
  final bool readOnlyAsLink;
  final bool allowMultipleActiveEdits;
  final FutureOr<bool> Function()? onWillStartEditing;
  final VoidCallback? onCancel;
  final ValueChanged<String>? onSaved;

  @override
  State<ScopedLazyTextField> createState() => _ScopedLazyTextFieldState();
}

class _ScopedLazyTextFieldState extends State<ScopedLazyTextField> {
  LazyTextFieldEditController? _editController;
  FocusNode? _attachedFocusNode;
  FocusOnKeyEventCallback? _previousHandler;

  @override
  void dispose() {
    _detachKeyboardHandler();
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
      padding: widget.padding,
      decoration: widget.decoration,
      decorationVisibility: widget.decorationVisibility,
      minHeight: widget.minHeight,
      maxHeight: widget.maxHeight,
      scrollbarGutter: widget.scrollbarGutter,
      readOnlyAsLink: widget.readOnlyAsLink,
      onStartEditing: () => unawaited(_startEditing(editController)),
      onSubmitted: (value) => unawaited(_save(value)),
      onTapOutside: (_) => unawaited(_save(controller?.text ?? widget.text)),
    );
  }

  Future<void> _startEditing(LazyTextFieldEditController editController) async {
    final allowed = await Future<bool>.value(
      widget.onWillStartEditing?.call() ?? true,
    );
    if (!allowed || !mounted) return;
    editController.startEditing(
      cellId: widget.cellId,
      initialValue: widget.text,
      allowMultipleActiveEdits: widget.allowMultipleActiveEdits,
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
    final ok = await Future<bool>.value(widget.onSave(value));
    if (!ok || !mounted) return;
    _editController?.stopEditing(widget.cellId);
    widget.onSaved?.call(value);
  }

  void _cancel() {
    _editController?.stopEditing(widget.cellId);
    widget.onCancel?.call();
  }
}
