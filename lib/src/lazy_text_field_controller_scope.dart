import 'package:flutter/widgets.dart';
import 'package:lazy_text_field/src/lazy_text_field_edit_controller.dart';

/// Provides a shared [LazyTextFieldEditController] to [ScopedLazyTextField]
/// descendants.
class LazyTextFieldControllerScope extends StatefulWidget {
  /// Creates a controller scope for lazy text fields.
  ///
  /// When [controller] is omitted, the scope owns and disposes one.
  const LazyTextFieldControllerScope({
    required this.child,
    super.key,
    this.controller,
    this.tableId,
  });

  /// External controller to expose, or null to let the scope own one.
  final LazyTextFieldEditController? controller;

  /// The table, collection, or record type the cells below edit, for
  /// example `'tasks'`.
  ///
  /// With a row id (from a `LazyTextFieldRowScope` or the cell's `rowId`), a
  /// cell's `fieldId` makes its draft key
  /// `LazyTextFieldDraftId(table: tableId, row: rowId, field: fieldId)`, which
  /// a [LazyTextFieldEditController.draftStore] requires. Nest another scope
  /// with the same controller and another [tableId] for a second table.
  final String? tableId;

  /// Subtree that can read the shared controller.
  final Widget child;

  /// Returns the nearest controller and asserts when no scope exists.
  static LazyTextFieldEditController of(BuildContext context) {
    final controller = maybeOf(context);
    assert(
      controller != null,
      'No LazyTextFieldControllerScope found in context.',
    );
    return controller!;
  }

  /// Returns the nearest controller, or null when no scope exists.
  static LazyTextFieldEditController? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<_LazyTextFieldControllerInherited>()
        ?.notifier;
  }

  /// Returns the nearest scope's [tableId], or null.
  static String? tableIdOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<_LazyTextFieldControllerInherited>()
        ?.tableId;
  }

  @override
  State<LazyTextFieldControllerScope> createState() =>
      _LazyTextFieldControllerScopeState();
}

class _LazyTextFieldControllerScopeState
    extends State<LazyTextFieldControllerScope> {
  late LazyTextFieldEditController _ownedController;

  LazyTextFieldEditController get _controller =>
      widget.controller ?? _ownedController;

  @override
  void initState() {
    super.initState();
    _ownedController = LazyTextFieldEditController();
  }

  @override
  void dispose() {
    _ownedController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _LazyTextFieldControllerInherited(
      notifier: _controller,
      tableId: widget.tableId,
      child: widget.child,
    );
  }
}

class _LazyTextFieldControllerInherited
    extends InheritedNotifier<LazyTextFieldEditController> {
  const _LazyTextFieldControllerInherited({
    required super.notifier,
    required this.tableId,
    required super.child,
  });

  final String? tableId;

  @override
  bool updateShouldNotify(_LazyTextFieldControllerInherited oldWidget) =>
      super.updateShouldNotify(oldWidget) || oldWidget.tableId != tableId;
}
