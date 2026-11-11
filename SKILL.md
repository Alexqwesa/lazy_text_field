---
name: lazy-text-field-api
description: "Lazy Material text fields for Flutter tables and grids: create real TextFields only while editing and keep native InputDecoration geometry stable."
---

# Lazy Text Field API

## Import

```dart
import 'package:lazy_text_field/lazy_text_field.dart';
```

Do not import from `src/` when consuming the package.

## Choose The Widget

Use `LazyTextField` when the caller owns edit state and supplies a
`TextEditingController` and `FocusNode` only while editing.

Use `StatefulLazyTextField` for local editing. Use
`LazyTextFieldControllerScope` with `ScopedLazyTextField` when many cells share
one edit manager.

When a scoped cell starts editing, the controller closes the others. With the
default `LazyTextFieldSwitchPolicy.commit` (since 2.1.0) the closed cell's
`onSave` receives its changed text in the background and the new cell is
focused immediately; if `onSave` returns `false` or throws, the text stays as
a failed draft (reopen restores it, Escape discards it). An editing cell that
is recycled or disposed (virtualized grids, data refresh) is not saved: its
text becomes an `unsaved` draft, saved when another cell starts editing or by
`saveDrafts()`, and never saved otherwise. Pass
`LazyTextFieldEditController(switchPolicy: LazyTextFieldSwitchPolicy.discard)`
to drop the text instead (2.0 behavior). Do not reimplement commit-on-switch
in `onWillStartEditing`.

## Background Saves

`unsaved` drafts are not saved on their own. Call
`editController.saveDrafts()` before leaving a screen, or check
`editController.drafts` for unsaved entries. For "Save all" screens use
`saveMode: LazyTextFieldSaveMode.deferred` with `saveDrafts()` or
`saveDrafts(batch: ...)`. To survive restarts, pass a
`LazyTextFieldDraftStore` (for example a Hive box) as `draftStore`, use
String draft keys that are unique and stable, and call `loadDrafts()` at
startup.

For server-backed grids, give cells `onCommit` (throw to fail) instead of
`onSave`; any `LazyTextFieldEditController` (including the one a scope creates
itself) handles drafts and the save queue. Do not keep your
own draft map, save queue, or "return false and close later" logic:

- The cell shows its draft while pending/failed, and a saved draft until
  `text` changes.
- Read `LazyTextFieldControllerScope.maybeOf(context)?.draftFor(key)?.status`
  to style pending/saved/failed cells.
- All saves (`onCommit`, `onSave`, `saveDrafts`, batches) share one queue.
  `saveOrder: LazyTextFieldSaveOrder.sequential` (default) never overlaps
  saves; `perRow` with `rowKey` runs different rows in parallel. Saves of one
  draft key never overlap in either order, so do not add your own
  "latest save wins" guards.
- `onCommit` runs when its queue turn comes; compute request state such as
  expected versions inside it.
- Map errors with `errorMessageOf`; Escape discards a failed draft.
- Refresh once per burst in `onSavesSettled: (saved, failed) {...}` (or
  await `whenSavesSettled()`), not after every save.
- Before replacing rows with fetched data, await
  `whenEditingDone()` (loop while `activeIds` is non-empty); switching cells
  does not complete it. Do not track your own "editing finished" completer.

## Direct LazyTextField

```dart
LazyTextField(
  cellId: 'row-42-title',
  text: value,
  isEditing: controller != null && focusNode != null,
  controller: controller,
  focusNode: focusNode,
  style: const TextStyle(fontSize: 14, height: 1.25),
  decoration: const InputDecoration(
    border: OutlineInputBorder(),
    hintText: 'Click to edit',
    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
  ),
  onStartEditing: startEditing,
  onChanged: updateDraft,
)
```

When `isEditing` is false, pass null for both controller and focus node.

## Decoration Stability

`LazyTextField` keeps one native `InputDecorator` mounted across the mode
switch. Keep layout-affecting decoration properties equivalent before and
during editing.

Fixed-size prefix/suffix/icon slots are supported. For edit-only controls,
reserve a fixed slot and animate opacity, or place the control in a `Stack` /
`Overlay` and reserve its width with `reservedTrailingWidth`.

Do not add, remove, or resize decoration slots, padding, constraints, borders,
or supporting-text rows when editing starts. Use a conventional overlay
`TextField` when the complete field geometry must differ.

## Height Measurement

`LazyTextField.computeHeightForWidth` and `LazyTextFieldMetrics` calculate the
undecorated text-viewport height. Arbitrary `InputDecoration` widget height is
known only during Flutter layout.

To grow a fixed-height grid row while a cell edits, set `editingMaxHeight`
(above `maxHeight`, or `double.infinity` for no limit) and add the value from
`onEditingExtraHeightChanged(extra)` to the row height (largest per row). Do
not measure editor text with your own `TextPainter`, and do not switch
`maxHeight` between modes yourself.
