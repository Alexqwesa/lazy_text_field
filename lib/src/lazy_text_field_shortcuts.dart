import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// What a keyboard shortcut does in an open editor of a
/// `StatefulLazyTextField` or `ScopedLazyTextField`.
enum LazyTextFieldAction {
  /// Save the editor's text, as Enter does in a single-line field.
  save,

  /// Close the editor without saving. A `ScopedLazyTextField` also discards
  /// its unsaved or failed draft.
  cancel,
}

/// Sets the keyboard shortcuts of the `StatefulLazyTextField` and
/// `ScopedLazyTextField` editors below it.
///
/// Without this widget, editors use [defaults]. To turn a shortcut off, pass
/// a map without it; to change one, pass your own map:
///
/// ```dart
/// LazyTextFieldShortcuts(
///   // Escape is left to the surrounding dialog.
///   shortcuts: Map.of(LazyTextFieldShortcuts.defaults)
///     ..remove(LazyTextFieldShortcuts.escape),
///   child: grid,
/// )
/// ```
///
/// A field's own `shortcuts` parameter overrides this widget.
///
/// Enter in a single-line field always saves (it submits the text field);
/// it is not part of the map. Keys the map does not handle reach the text
/// field and the widgets above it as usual.
///
/// The field's focus node sees key events before any [Shortcuts] widget
/// above it, so use this widget, not [Shortcuts], to change these keys.
class LazyTextFieldShortcuts extends InheritedWidget {
  /// Sets [shortcuts] for the editors in [child].
  const LazyTextFieldShortcuts({
    required this.shortcuts,
    required super.child,
    super.key,
  });

  /// Escape: [LazyTextFieldAction.cancel] in [defaults].
  static const ShortcutActivator escape = SingleActivator(
    LogicalKeyboardKey.escape,
  );

  /// Ctrl+S: [LazyTextFieldAction.save] in [defaults].
  static const ShortcutActivator controlS = SingleActivator(
    LogicalKeyboardKey.keyS,
    control: true,
  );

  /// Cmd+S (macOS), the Meta key elsewhere: [LazyTextFieldAction.save] in
  /// [defaults].
  static const ShortcutActivator metaS = SingleActivator(
    LogicalKeyboardKey.keyS,
    meta: true,
  );

  /// Ctrl+Enter: [LazyTextFieldAction.save] in [defaults].
  static const ShortcutActivator controlEnter = SingleActivator(
    LogicalKeyboardKey.enter,
    control: true,
  );

  /// Ctrl+Enter on the numeric keypad: [LazyTextFieldAction.save] in
  /// [defaults].
  static const ShortcutActivator controlNumpadEnter = SingleActivator(
    LogicalKeyboardKey.numpadEnter,
    control: true,
  );

  /// Cmd+Enter (macOS): [LazyTextFieldAction.save] in [defaults].
  static const ShortcutActivator metaEnter = SingleActivator(
    LogicalKeyboardKey.enter,
    meta: true,
  );

  /// Cmd+Enter on the numeric keypad (macOS): [LazyTextFieldAction.save] in
  /// [defaults].
  static const ShortcutActivator metaNumpadEnter = SingleActivator(
    LogicalKeyboardKey.numpadEnter,
    meta: true,
  );

  /// The shortcuts editors use without a [LazyTextFieldShortcuts] above
  /// them: Escape cancels; Ctrl+S, Cmd+S, Ctrl+Enter and Cmd+Enter save.
  static const Map<ShortcutActivator, LazyTextFieldAction> defaults = {
    escape: LazyTextFieldAction.cancel,
    controlS: LazyTextFieldAction.save,
    metaS: LazyTextFieldAction.save,
    controlEnter: LazyTextFieldAction.save,
    controlNumpadEnter: LazyTextFieldAction.save,
    metaEnter: LazyTextFieldAction.save,
    metaNumpadEnter: LazyTextFieldAction.save,
  };

  /// What each key does in an open editor.
  final Map<ShortcutActivator, LazyTextFieldAction> shortcuts;

  /// The shortcuts of the closest [LazyTextFieldShortcuts] above [context],
  /// or [defaults].
  ///
  /// Does not make [context] depend on the widget: editors read it when a
  /// key is pressed.
  static Map<ShortcutActivator, LazyTextFieldAction> of(BuildContext context) =>
      context
          .getInheritedWidgetOfExactType<LazyTextFieldShortcuts>()
          ?.shortcuts ??
      defaults;

  /// The action [shortcuts] binds to [event], if any.
  static LazyTextFieldAction? actionFor(
    KeyEvent event,
    Map<ShortcutActivator, LazyTextFieldAction> shortcuts,
  ) {
    for (final MapEntry(key: activator, value: action) in shortcuts.entries) {
      if (activator.accepts(event, HardwareKeyboard.instance)) return action;
    }
    return null;
  }

  @override
  bool updateShouldNotify(LazyTextFieldShortcuts oldWidget) =>
      !identical(shortcuts, oldWidget.shortcuts);
}
