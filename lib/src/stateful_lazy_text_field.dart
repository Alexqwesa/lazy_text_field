import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lazy_text_field/src/lazy_text_field.dart';

/// Saves an edited lazy text field value.
///
/// Return true to accept the value and exit edit mode, or false to keep editing.
typedef LazyTextFieldSave = FutureOr<bool> Function(String value);

/// Self-contained [LazyTextField] wrapper that owns its edit lifecycle.
class StatefulLazyTextField extends StatefulWidget {
  /// Creates a lazy text field that owns its controller and focus node.
  const StatefulLazyTextField({
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
    this.onWillStartEditing,
    this.onCancel,
    this.onSaved,
  });

  /// Stable id used for keys and edit tracking.
  final String cellId;

  /// Current read-only text value.
  final String text;

  /// Called when editing should save.
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

  /// Optional guard called before edit resources are created.
  final FutureOr<bool> Function()? onWillStartEditing;

  /// Called when editing is canceled with Escape.
  final VoidCallback? onCancel;

  /// Called after [onSave] accepts a value.
  final ValueChanged<String>? onSaved;

  @override
  State<StatefulLazyTextField> createState() => _StatefulLazyTextFieldState();
}

class _StatefulLazyTextFieldState extends State<StatefulLazyTextField> {
  TextEditingController? _controller;
  FocusNode? _focusNode;
  int _editEpoch = 0;
  bool _saveInFlight = false;

  bool get _isEditing => _controller != null && _focusNode != null;

  @override
  void didUpdateWidget(covariant StatefulLazyTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.cellId != widget.cellId) {
      _invalidateEditSession();
      // build() runs after didUpdateWidget; do not setState here.
      _disposeEditState();
    }
  }

  @override
  void dispose() {
    _invalidateEditSession();
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
      textAlignVertical: widget.textAlignVertical,
      decoration: widget.decoration,
      minHeight: widget.minHeight,
      maxHeight: widget.maxHeight,
      scrollbarGutter: widget.scrollbarGutter,
      scrollbarThickness: widget.scrollbarThickness,
      scrollbarAlignment: widget.scrollbarAlignment,
      readOnlyAsLink: widget.readOnlyAsLink,
      onStartEditing: () => unawaited(_startEditing()),
      onStartEditingWithDetails: (details) =>
          unawaited(_startEditing(textOffset: details.textOffset)),
      onSubmitted: (value) => unawaited(_save(value)),
      onTapOutside: (_) => unawaited(_save(_controller?.text ?? widget.text)),
    );
  }

  Future<void> _startEditing({int? textOffset}) async {
    final epoch = _editEpoch;
    final cellId = widget.cellId;
    final allowed = await Future<bool>.value(
      widget.onWillStartEditing?.call() ?? true,
    );
    if (!allowed ||
        !mounted ||
        _isEditing ||
        epoch != _editEpoch ||
        widget.cellId != cellId) {
      return;
    }
    final controller = TextEditingController(text: widget.text);
    final focusNode = FocusNode(
      debugLabel: 'stateful-lazy-text-field-${widget.cellId}',
    );
    setState(() {
      _controller = controller;
      _focusNode = focusNode;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          !identical(_controller, controller) ||
          !identical(_focusNode, focusNode) ||
          !focusNode.canRequestFocus) {
        return;
      }
      focusNode.requestFocus();
      controller.selection = _startEditSelectionFor(
        text: controller.text,
        textOffset: textOffset,
        policy: widget.startEditSelection,
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
    if (_saveInFlight || !_isEditing) return;
    _saveInFlight = true;
    final epoch = _editEpoch;
    final ok = await widget.onSave(value);
    if (!mounted || epoch != _editEpoch) return;
    _saveInFlight = false;
    if (!ok) return;
    _disposeEditState(update: true);
    widget.onSaved?.call(value);
  }

  void _cancel() {
    _invalidateEditSession();
    _disposeEditState(update: true);
    widget.onCancel?.call();
  }

  void _invalidateEditSession() {
    _editEpoch++;
    _saveInFlight = false;
  }

  void _disposeEditState({bool update = false}) {
    final controller = _controller;
    final focusNode = _focusNode;
    _controller = null;
    _focusNode = null;
    if (update && mounted) {
      setState(() {});
    }
    // Dispose after the editor unmounts so EditableText never sees a
    // disposed controller/focus node during the same frame.
    if (controller != null || focusNode != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        controller?.dispose();
        focusNode?.dispose();
      });
    }
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
