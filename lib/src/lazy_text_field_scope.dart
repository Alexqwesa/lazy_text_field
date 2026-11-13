import 'package:flutter/widgets.dart';
import 'package:lazy_text_field/src/lazy_text_field_edit_controller.dart';
import 'package:lazy_text_field/src/lazy_text_field_shortcuts.dart';

/// Settings for the lazy text fields below it.
///
/// - [LazyTextFieldScope.new]: the [LazyTextFieldEditController] that
///   `ScopedLazyTextField`s share, the table they edit, and the keyboard
///   shortcuts of every field below.
/// - [LazyTextFieldScope.row]: the record a row of cells edits.
///
/// ```dart
/// LazyTextFieldScope(
///   controller: editController,
///   tableId: 'tasks',
///   child: ListView.builder(
///     itemCount: tasks.length,
///     itemBuilder: (context, i) => LazyTextFieldScope.row(
///       rowId: tasks[i].id,
///       version: tasks[i].updatedAt.toIso8601String(),
///       child: Row(
///         children: [
///           Expanded(
///             child: ScopedLazyTextField(
///               cellId: 'tasks/${tasks[i].id}/title',
///               fieldId: 'title',
///               text: tasks[i].title,
///               onCommit: (value) => api.updateTitle(tasks[i].id, value),
///             ),
///           ),
///         ],
///       ),
///     ),
///   ),
/// )
/// ```
///
/// Scopes nest: what a scope leaves out comes from the scope above it.
abstract class LazyTextFieldScope implements Widget {
  /// Provides a controller, a table, and shortcuts to the fields in [child].
  ///
  /// - `controller`: the [LazyTextFieldEditController] that the
  ///   `ScopedLazyTextField`s below share (drafts, the save queue, which
  ///   cell is editing). Null uses the controller of the scope above, or,
  ///   when there is none, one this scope creates and disposes.
  /// - `tableId`: the table, collection, or record type the cells below
  ///   edit, for example `'tasks'`. With a row id and a cell's `fieldId`, a
  ///   cell's draft key is
  ///   `LazyTextFieldDraftId(table: tableId, row: rowId, field: fieldId)`,
  ///   which a [LazyTextFieldEditController.draftStore] requires. Null uses
  ///   the table of the scope above, unless this scope sets its own
  ///   `controller` (another grid). Nest a scope with another `tableId` for
  ///   a second table with the same controller.
  /// - `shortcuts`: what keys do in the open editors below (of
  ///   `ScopedLazyTextField` and `StatefulLazyTextField`). Null uses the
  ///   shortcuts of the scope above, or [defaultShortcuts]. To turn one off,
  ///   pass a map without it:
  ///
  ///   ```dart
  ///   LazyTextFieldScope(
  ///     // Escape is left to the surrounding dialog.
  ///     shortcuts: Map.of(LazyTextFieldScope.defaultShortcuts)
  ///       ..removeWhere((_, action) => action == LazyTextFieldAction.cancel),
  ///     child: grid,
  ///   )
  ///   ```
  ///
  ///   Enter in a single-line field always saves (it submits the text
  ///   field); it is not part of the map. A field's own `shortcuts`
  ///   parameter overrides the scope. The field's focus node sees key events
  ///   before any [Shortcuts] widget above it, so use this, not [Shortcuts],
  ///   to change these keys.
  const factory LazyTextFieldScope({
    required Widget child,
    Key? key,
    LazyTextFieldEditController? controller,
    String? tableId,
    Map<ShortcutActivator, LazyTextFieldAction>? shortcuts,
  }) = _SettingsScope;

  /// The record that the cells in [child] edit: one row of a grid.
  ///
  /// - `rowId`: the record's id, for example `task.id`. Not its position in
  ///   a list: the id must stay with the record when rows are sorted,
  ///   filtered, or reloaded. Part of each cell's draft key (as `'$rowId'`,
  ///   so use a String or an int), and the row's save lane under
  ///   [LazyTextFieldSaveOrder.perRow].
  /// - `version`: the record's version, as a token: for example its
  ///   `updatedAt` (`task.updatedAt.toIso8601String()`), a revision number,
  ///   or an ETag. Kept with each draft as [LazyTextFieldDraft.baseVersion];
  ///   a [LazyTextFieldEditController.draftStore] requires it.
  ///
  /// A cell's own `rowId` and `version` win over the row scope's.
  const factory LazyTextFieldScope.row({
    required Object rowId,
    required Widget child,
    Key? key,
    String? version,
  }) = _RowScope;

  /// The shortcuts editors use without a scope that sets them: Escape
  /// cancels; Ctrl+S, Cmd+S, Ctrl+Enter and Cmd+Enter (also on the numeric
  /// keypad) save.
  static const Map<ShortcutActivator, LazyTextFieldAction> defaultShortcuts =
      lazyTextFieldDefaultShortcuts;

  /// Returns the nearest scope's controller and asserts when there is no
  /// scope.
  static LazyTextFieldEditController of(BuildContext context) {
    final controller = maybeOf(context);
    assert(controller != null, 'No LazyTextFieldScope found in context.');
    return controller!;
  }

  /// Returns the nearest scope's controller, or null when there is no
  /// scope. The caller rebuilds when the controller notifies.
  static LazyTextFieldEditController? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_ScopeData>()?.notifier;
}

/// The nearest scope's table, if any. Not exported.
String? lazyTextFieldTableIdOf(BuildContext context) =>
    context.dependOnInheritedWidgetOfExactType<_ScopeData>()?.tableId;

/// The id and version of the nearest [LazyTextFieldScope.row], if any. Not
/// exported.
({Object rowId, String? version})? lazyTextFieldRowOf(BuildContext context) {
  final row = context.dependOnInheritedWidgetOfExactType<_RowScope>();
  return row == null ? null : (rowId: row.rowId, version: row.version);
}

/// The shortcuts of the nearest scope that sets them, or the defaults.
/// Does not make [context] depend on the scope: editors read it when a key
/// is pressed. Not exported.
Map<ShortcutActivator, LazyTextFieldAction> lazyTextFieldShortcutsOf(
  BuildContext context,
) =>
    context.getInheritedWidgetOfExactType<_ScopeData>()?.shortcuts ??
    lazyTextFieldDefaultShortcuts;

class _SettingsScope extends StatefulWidget implements LazyTextFieldScope {
  const _SettingsScope({
    required this.child,
    super.key,
    this.controller,
    this.tableId,
    this.shortcuts,
  });

  final Widget child;
  final LazyTextFieldEditController? controller;
  final String? tableId;
  final Map<ShortcutActivator, LazyTextFieldAction>? shortcuts;

  @override
  State<_SettingsScope> createState() => _SettingsScopeState();
}

class _SettingsScopeState extends State<_SettingsScope> {
  // Created only when neither this scope nor one above has a controller.
  LazyTextFieldEditController? _owned;

  @override
  void dispose() {
    _owned?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final outer = context.dependOnInheritedWidgetOfExactType<_ScopeData>();
    final own = widget.controller;
    return _ScopeData(
      notifier:
          own ?? outer?.notifier ?? (_owned ??= LazyTextFieldEditController()),
      // A scope with its own controller is another grid: it does not take
      // the table of the scope above.
      tableId: widget.tableId ?? (own == null ? outer?.tableId : null),
      shortcuts: widget.shortcuts ?? outer?.shortcuts,
      child: widget.child,
    );
  }
}

class _ScopeData extends InheritedNotifier<LazyTextFieldEditController> {
  const _ScopeData({
    required super.notifier,
    required this.tableId,
    required this.shortcuts,
    required super.child,
  });

  final String? tableId;
  final Map<ShortcutActivator, LazyTextFieldAction>? shortcuts;

  @override
  bool updateShouldNotify(_ScopeData oldWidget) =>
      super.updateShouldNotify(oldWidget) ||
      oldWidget.tableId != tableId ||
      !identical(oldWidget.shortcuts, shortcuts);
}

class _RowScope extends InheritedWidget implements LazyTextFieldScope {
  const _RowScope({
    required this.rowId,
    required super.child,
    super.key,
    this.version,
  });

  final Object rowId;
  final String? version;

  @override
  bool updateShouldNotify(_RowScope oldWidget) =>
      oldWidget.rowId != rowId || oldWidget.version != version;
}
