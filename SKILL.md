---
name: lazy-text-field-api
description: "Fast editable cells for Flutter tables and grids: render thousands of fields cheaply, create TextFields only while editing, and keep row heights stable. No overlay is used, so text keeps the exact same position in view and edit modes."
---

# Lazy Text Field API

## Import

Use the public barrel:

```dart
import 'package:lazy_text_field/lazy_text_field.dart';
```

Do not import from `src/` when consuming the package.

## Choose The Widget

Use `LazyTextField` when the caller already owns edit state and can pass a
`TextEditingController` and `FocusNode` only while editing.

Use `StatefulLazyTextField` for one-off local editing where the widget may own
its controller/focus node.

Use `LazyTextFieldControllerScope` plus `ScopedLazyTextField` for many cells
sharing one edit manager.

## Direct LazyTextField

```dart
LazyTextField(
  cellId: 'row-42-title',
  text: value,
  isEditing: controller != null && focusNode != null,
  controller: controller,
  focusNode: focusNode,
  style: const TextStyle(fontSize: 14, height: 1.25),
  padding: kDefaultLazyTextFieldPadding,
  decoration: const LazyInputDecoration(
    border: OutlineInputBorder(),
    hintText: 'Click to edit',
  ),
  onStartEditing: startEditing,
  onChanged: updateDraft,
)
```

When `isEditing` is true, provide both `controller` and `focusNode`. When
`isEditing` is false, pass `null` for both so read-only mode stays lazy.

## Scoped Cells

```dart
LazyTextFieldControllerScope(
  child: ScopedLazyTextField(
    cellId: rowId,
    text: value,
    onSave: (nextValue) async {
      await repository.save(nextValue);
      return true;
    },
  ),
)
```

Return `true` from `onSave` to exit edit mode. Return `false` to keep editing.

## Decoration

`LazyInputDecoration` is TextField-like chrome drawn by this package, not
Flutter `InputDecoration`.

Supported fields: fill, hover/focus colors, enabled/focused/error/disabled
borders, hint text/style, prefix icon, suffix icon, and icon constraints.

Unsupported by design: labels, helper text rows, error rows, counters, floating
labels, and decoration content padding.

Visibility:

- `LazyInputDecorationVisibility.editing`: default; reserve icon slots in both
  modes, paint chrome only while editing.
- `LazyInputDecorationVisibility.always`: reserve and paint chrome in both
  modes.
- `LazyInputDecorationVisibility.never`: do not reserve or paint decoration
  chrome.

## Height Measurement

Use `LazyTextField.computeHeightForWidth` or
`LazyTextFieldMetrics.computeHeightForWidth`
when row height must be known before building cells:

```dart
final height = LazyTextField.computeHeightForWidth(
  text: value,
  width: columnWidth,
  style: const TextStyle(fontSize: 14, height: 1.25),
  padding: kDefaultLazyTextFieldPadding,
  reservedLeadingWidth: 28,
  reservedTrailingWidth: 28,
);
```

Use `reservedLeadingWidth` and `reservedTrailingWidth` for prefix/suffix
controls that consume horizontal text space. Use the same `TextStyle`,
`padding`, text direction, scaler, and width that the rendered field will use.

For context-aware measurement, pass `context:` to
`LazyTextField.computeHeightForWidth` or use `LazyTextField.measure` when you
need the full [LazyTextFieldLayout] breakdown.
