import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lazy_text_field/src/lazy_input_decoration.dart';
import 'package:lazy_text_field/src/lazy_text_field.dart';
import 'package:lazy_text_field/src/lazy_text_field_metrics.dart';

typedef LazyTextFieldSave = FutureOr<bool> Function(String value);

/// Self-contained [LazyTextField] wrapper that owns its edit lifecycle.
class StatefulLazyTextField extends StatefulWidget {
  const StatefulLazyTextField({
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
    this.scrollbarThickness = 6,
    this.scrollbarAlignment = Alignment.centerRight,
    this.readOnlyAsLink = false,
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
  final double scrollbarThickness;
  final AlignmentGeometry scrollbarAlignment;
  final bool readOnlyAsLink;
  final FutureOr<bool> Function()? onWillStartEditing;
  final VoidCallback? onCancel;
  final ValueChanged<String>? onSaved;

  @override
  State<StatefulLazyTextField> createState() => _StatefulLazyTextFieldState();
}

class _StatefulLazyTextFieldState extends State<StatefulLazyTextField> {
  TextEditingController? _controller;
  FocusNode? _focusNode;

  bool get _isEditing => _controller != null && _focusNode != null;

  @override
  void dispose() {
    _disposeEditState();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isEditing) {
      _focusNode!.onKeyEvent = _handleKeyEvent;
    }

    return LazyTextField(
      cellId: widget.cellId,
      text: widget.text,
      isEditing: _isEditing,
      controller: _controller,
      focusNode: _focusNode,
      singleLine: widget.singleLine,
      style: widget.style,
      padding: widget.padding,
      decoration: widget.decoration,
      decorationVisibility: widget.decorationVisibility,
      minHeight: widget.minHeight,
      maxHeight: widget.maxHeight,
      scrollbarGutter: widget.scrollbarGutter,
      scrollbarThickness: widget.scrollbarThickness,
      scrollbarAlignment: widget.scrollbarAlignment,
      readOnlyAsLink: widget.readOnlyAsLink,
      onStartEditing: () => unawaited(_startEditing()),
      onSubmitted: (value) => unawaited(_save(value)),
      onTapOutside: (_) => unawaited(_save(_controller?.text ?? widget.text)),
    );
  }

  Future<void> _startEditing() async {
    final allowed = await Future<bool>.value(
      widget.onWillStartEditing?.call() ?? true,
    );
    if (!allowed || !mounted || _isEditing) return;
    final controller = TextEditingController(text: widget.text);
    final focusNode = FocusNode(
      debugLabel: 'stateful-lazy-text-field-${widget.cellId}',
    );
    setState(() {
      _controller = controller;
      _focusNode = focusNode;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !focusNode.canRequestFocus) return;
      focusNode.requestFocus();
      controller.selection = TextSelection.collapsed(
        offset: controller.text.length,
      );
    });
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final controller = _controller;
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
    return KeyEventResult.ignored;
  }

  Future<void> _save(String value) async {
    final ok = await Future<bool>.value(widget.onSave(value));
    if (!ok || !mounted) return;
    _disposeEditState();
    widget.onSaved?.call(value);
    if (mounted) setState(() {});
  }

  void _cancel() {
    _disposeEditState();
    widget.onCancel?.call();
    if (mounted) setState(() {});
  }

  void _disposeEditState() {
    final controller = _controller;
    final focusNode = _focusNode;
    _controller = null;
    _focusNode = null;
    controller?.dispose();
    focusNode?.dispose();
  }
}
