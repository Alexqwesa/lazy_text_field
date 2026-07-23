import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// Manages lazy controller/focus allocation for many [ScopedLazyTextField]
/// cells.
class LazyTextFieldEditController extends ChangeNotifier {
  final Map<String, TextEditingController> _controllers =
      <String, TextEditingController>{};
  final Map<String, FocusNode> _focusNodes = <String, FocusNode>{};

  Map<String, TextEditingController> get controllers =>
      Map.unmodifiable(_controllers);
  Map<String, FocusNode> get focusNodes => Map.unmodifiable(_focusNodes);
  Iterable<String> get activeIds => _controllers.keys;

  bool isEditing(String cellId) =>
      _controllers.containsKey(cellId) && _focusNodes.containsKey(cellId);
  TextEditingController? controllerFor(String cellId) => _controllers[cellId];
  FocusNode? focusNodeFor(String cellId) => _focusNodes[cellId];

  TextEditingController startEditing({
    required String cellId,
    required String initialValue,
    bool allowMultipleActiveEdits = false,
  }) {
    if (!allowMultipleActiveEdits) {
      stopWhere((id) => id != cellId);
    }

    final existing = _controllers[cellId];
    if (existing != null) {
      _focusExisting(cellId, existing);
      return existing;
    }

    final controller = TextEditingController(text: initialValue);
    final focusNode = FocusNode(debugLabel: 'lazy-text-field-$cellId');
    _controllers[cellId] = controller;
    _focusNodes[cellId] = focusNode;
    notifyListeners();

    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!focusNode.canRequestFocus) return;
      focusNode.requestFocus();
      controller.selection = TextSelection.collapsed(
        offset: controller.text.length,
      );
    });
    return controller;
  }

  void updateText(String cellId, String value) {
    final controller = _controllers[cellId];
    if (controller == null) return;
    if (controller.text != value) {
      controller.text = value;
    }
  }

  void stopEditing(String cellId) {
    final controller = _controllers.remove(cellId);
    final focusNode = _focusNodes.remove(cellId);
    controller?.dispose();
    focusNode?.dispose();
    if (controller != null || focusNode != null) {
      notifyListeners();
    }
  }

  void stopWhere(bool Function(String cellId) shouldStop) {
    for (final cellId in _controllers.keys.toList(growable: false)) {
      if (shouldStop(cellId)) {
        stopEditing(cellId);
      }
    }
  }

  void stopAll() {
    stopWhere((_) => true);
  }

  void _focusExisting(String cellId, TextEditingController controller) {
    final focusNode = _focusNodes[cellId];
    controller.selection = TextSelection.collapsed(
      offset: controller.text.length,
    );
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (focusNode == null || !focusNode.canRequestFocus) return;
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
