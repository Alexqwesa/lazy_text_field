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
  });

  /// External controller to expose, or null to let the scope own one.
  final LazyTextFieldEditController? controller;

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
      child: widget.child,
    );
  }
}

class _LazyTextFieldControllerInherited
    extends InheritedNotifier<LazyTextFieldEditController> {
  const _LazyTextFieldControllerInherited({
    required super.notifier,
    required super.child,
  });
}
