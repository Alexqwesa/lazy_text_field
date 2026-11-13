import 'package:flutter/widgets.dart';

/// The record a row of `ScopedLazyTextField`s edits: its id and version.
///
/// Wrap each row once; its cells then need only a `fieldId`. Under a
/// `LazyTextFieldControllerScope` with a `tableId`, each cell's draft key is
/// `LazyTextFieldDraftId(table: tableId, row: '$rowId', field: fieldId)`,
/// and [version] is kept with the draft as its base version. A
/// `LazyTextFieldEditController.draftStore` requires both.
///
/// ```dart
/// LazyTextFieldControllerScope(
///   controller: editController,
///   tableId: 'tasks',
///   child: ListView.builder(
///     itemCount: tasks.length,
///     itemBuilder: (context, i) => LazyTextFieldRowScope(
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
/// A cell's own `rowId` and `version` take precedence.
class LazyTextFieldRowScope extends InheritedWidget {
  /// Creates a row scope.
  const LazyTextFieldRowScope({
    required this.rowId,
    required super.child,
    this.version,
    super.key,
  });

  /// The record's id, for example `task.id`. Not its position in a list:
  /// the id must stay with the record when rows are sorted, filtered, or
  /// reloaded. Stored as `'$rowId'`, so use a String or an int.
  ///
  /// Also the row's save lane under `LazyTextFieldSaveOrder.perRow`.
  final Object rowId;

  /// The record's version, as a token: for example its `updatedAt`
  /// (`task.updatedAt.toIso8601String()`), a revision number, or an ETag.
  final String? version;

  /// Returns the nearest row scope, or null.
  static LazyTextFieldRowScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<LazyTextFieldRowScope>();

  @override
  bool updateShouldNotify(LazyTextFieldRowScope oldWidget) =>
      oldWidget.rowId != rowId || oldWidget.version != version;
}
