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
