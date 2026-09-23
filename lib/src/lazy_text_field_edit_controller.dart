import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:lazy_text_field/src/lazy_text_field.dart';

/// Manages lazy controller/focus allocation for many [ScopedLazyTextField]
/// cells.
class LazyTextFieldEditController extends ChangeNotifier {
  final Map<String, TextEditingController> _controllers =
      <String, TextEditingController>{};
  final Map<String, FocusNode> _focusNodes = <String, FocusNode>{};

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

  /// Starts editing [cellId] and returns its active controller.
  ///
  /// Unless [allowMultipleActiveEdits] is true, other active cells are stopped
  /// before this one starts editing.
  TextEditingController startEditing({
    required String cellId,
    required String initialValue,
    bool allowMultipleActiveEdits = false,
    LazyTextFieldStartEditSelection startEditSelection =
        LazyTextFieldStartEditSelection.end,
    int? textOffset,
  }) {
    if (!allowMultipleActiveEdits) {
      stopWhere((id) => id != cellId);
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

  /// Updates the active controller text for [cellId] without starting editing.
  void updateText(String cellId, String value) {
    final controller = _controllers[cellId];
    if (controller == null) return;
    if (controller.text != value) {
      controller.text = value;
    }
  }

  /// Stops editing [cellId] and disposes its edit resources.
  void stopEditing(String cellId) {
    final controller = _controllers.remove(cellId);
    final focusNode = _focusNodes.remove(cellId);
    controller?.dispose();
    focusNode?.dispose();
    if (controller != null || focusNode != null) {
      notifyListeners();
    }
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
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    for (final focusNode in _focusNodes.values) {
      focusNode.dispose();
    }
    _controllers.clear();
    _focusNodes.clear();
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
