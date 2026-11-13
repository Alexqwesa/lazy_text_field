import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// What a keyboard shortcut does in an open editor of a
/// `StatefulLazyTextField` or `ScopedLazyTextField`.
///
/// Set shortcuts with `LazyTextFieldScope(shortcuts: ...)` or a field's
/// `shortcuts` parameter.
enum LazyTextFieldAction {
  /// Save the editor's text, as Enter does in a single-line field.
  save,

  /// Close the editor without saving. A `ScopedLazyTextField` also discards
  /// its unsaved or failed draft.
  cancel,
}

/// `LazyTextFieldScope.defaultShortcuts`. Not exported.
const Map<ShortcutActivator, LazyTextFieldAction>
lazyTextFieldDefaultShortcuts = {
  SingleActivator(LogicalKeyboardKey.escape): LazyTextFieldAction.cancel,
  SingleActivator(LogicalKeyboardKey.keyS, control: true):
      LazyTextFieldAction.save,
  // Cmd on macOS, the Meta key elsewhere.
  SingleActivator(LogicalKeyboardKey.keyS, meta: true):
      LazyTextFieldAction.save,
  SingleActivator(LogicalKeyboardKey.enter, control: true):
      LazyTextFieldAction.save,
  SingleActivator(LogicalKeyboardKey.numpadEnter, control: true):
      LazyTextFieldAction.save,
  SingleActivator(LogicalKeyboardKey.enter, meta: true):
      LazyTextFieldAction.save,
  SingleActivator(LogicalKeyboardKey.numpadEnter, meta: true):
      LazyTextFieldAction.save,
};

/// The action [shortcuts] binds to [event], if any. Not exported.
LazyTextFieldAction? lazyTextFieldActionFor(
  KeyEvent event,
  Map<ShortcutActivator, LazyTextFieldAction> shortcuts,
) {
  for (final MapEntry(key: activator, value: action) in shortcuts.entries) {
    if (activator.accepts(event, HardwareKeyboard.instance)) return action;
  }
  return null;
}
