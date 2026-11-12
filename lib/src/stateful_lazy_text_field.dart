import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lazy_text_field/src/lazy_text_field.dart';
import 'package:lazy_text_field/src/lazy_text_field_shortcuts.dart';

/// Commits an edited lazy text field value.
///
/// This is the primary validation hook on save. Return true to accept the
/// value and exit edit mode, or false to keep editing.
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
    this.editingMaxHeight,
    this.onEditingExtraHeightChanged,
    this.scrollbarGutter = 12,
    this.scrollbarThickness = 6,
    this.scrollbarAlignment = LazyTextField.defaultScrollbarAlignment,
    this.startEditSelection = LazyTextFieldStartEditSelection.end,
    this.readOnlyAsLink = false,
    this.chainEditorScroll = true,
    this.shortcuts,
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

  /// Stable id used for keys and edit tracking.
  final String cellId;

  /// Current read-only text value.
  final String text;

  /// Primary commit path: return true to accept and exit edit mode, or false
  /// to keep editing (e.g. validation failed). A throw is reported to
  /// [FlutterError] and treated as a rejection.
  ///
  /// The editor stays open while it runs. If the text changed meanwhile,
  /// the editor stays open with the newer text; a submit made meanwhile is
  /// saved after this one.
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
  State<StatefulLazyTextField> createState() => _StatefulLazyTextFieldState();
}

class _StatefulLazyTextFieldState extends State<StatefulLazyTextField> {
  TextEditingController? _controller;
  FocusNode? _focusNode;
  int _editEpoch = 0;
  bool _saveInFlight = false;
  // The value the running save sends, and newer text submitted while it
  // runs, saved after it.
  String? _savingValue;
  String? _nextValue;

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
      editingMaxHeight: widget.editingMaxHeight,
      onEditingExtraHeightChanged: widget.onEditingExtraHeightChanged,
      scrollbarGutter: widget.scrollbarGutter,
      scrollbarThickness: widget.scrollbarThickness,
      scrollbarAlignment: widget.scrollbarAlignment,
      readOnlyAsLink: widget.readOnlyAsLink,
      chainEditorScroll: widget.chainEditorScroll,
      inputFormatters: widget.inputFormatters,
      onChanged: widget.onChanged,
      keyboardType: widget.keyboardType,
      textInputAction: widget.textInputAction,
      maxLength: widget.maxLength,
      errorMessage: widget.errorMessage,
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
    return KeyEventResult.ignored;
  }

  Future<void> _save(String value) async {
    final editor = _controller;
    if (editor == null || !_isEditing) return;
    if (_saveInFlight) {
      // Newer text saves after the running save; the same text is already
      // being saved.
      _nextValue = value == _savingValue ? null : value;
      return;
    }
    _saveInFlight = true;
    final epoch = _editEpoch;
    var current = value;
    while (true) {
      _savingValue = current;
      final ok = await _runOnSave(current);
      // Canceled, disposed, or recycled meanwhile: that reset the flags.
      if (!mounted || epoch != _editEpoch) return;
      final next = _nextValue;
      _nextValue = null;
      if (next != null && identical(_controller, editor)) {
        if (ok) widget.onSaved?.call(current);
        current = next;
        continue;
      }
      _saveInFlight = false;
      _savingValue = null;
      if (!ok) return;
      // Text typed while saving stays in the editor.
      if (identical(_controller, editor) && editor.text == current) {
        _disposeEditState(update: true);
      }
      widget.onSaved?.call(current);
      return;
    }
  }

  /// Runs [StatefulLazyTextField.onSave]; a throw is reported to
  /// [FlutterError] and counts as a rejection, so the editor stays open.
  Future<bool> _runOnSave(String value) async {
    try {
      return await widget.onSave(value);
    } catch (error, stack) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stack,
          library: 'lazy_text_field',
          context: ErrorDescription(
            'while running StatefulLazyTextField.onSave for cell '
            '"${widget.cellId}"',
          ),
        ),
      );
      return false;
    }
  }

  void _cancel() {
    _invalidateEditSession();
    _disposeEditState(update: true);
    widget.onCancel?.call();
  }

  void _invalidateEditSession() {
    _editEpoch++;
    _saveInFlight = false;
    _savingValue = null;
    _nextValue = null;
  }

  void _disposeEditState({bool update = false}) {
    final controller = _controller;
    final focusNode = _focusNode;
    _controller = null;
    _focusNode = null;
    // Drop focus first so TextInput stops sending updates to this editor.
    if (focusNode != null && focusNode.hasFocus) {
      focusNode.unfocus();
    }
    if (update && mounted) {
      setState(() {});
    }
    // Dispose after the editor unmounts so a queued IME update cannot hit a
    // disposed controller (e.g. save/cancel then immediately edit elsewhere).
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
