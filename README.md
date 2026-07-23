# lazy_text_field

[![Tests](https://github.com/Alexqwesa/lazy_text_field/actions/workflows/lazy_text_field.yml/badge.svg)](https://github.com/Alexqwesa/lazy_text_field/actions/workflows/lazy_text_field.yml)
[![pub package](https://img.shields.io/pub/v/lazy_text_field.svg)](https://pub.dev/packages/lazy_text_field)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](https://opensource.org/licenses/MIT)

Pure Flutter lazy text-field primitives for table and grid cells.

`LazyTextField` renders read-only text without allocating edit resources, then
connects a real `TextField` only while editing. It also exposes fast
constrained-width height calculation through `LazyTextFieldLayout`,
`LazyTextFieldMetrics`, and `LazyTextField.computeHeightForWidth`.

## Installation

Add `lazy_text_field` to your `pubspec.yaml`:

```yaml
dependencies:
  lazy_text_field: ^1.0.0
```

Then import the public barrel:

```dart
import 'package:lazy_text_field/lazy_text_field.dart';
```

## Why not just `TextField`?

| | `TextField` in every cell | `LazyTextField` |
| --- | --- | --- |
| Controllers / focus nodes | One per visible cell | Created only for the active editor |
| Read-only rendering | Still pays `InputDecorator` layout cost | Lightweight `Text` / painter path |
| Static → edit switch | Often shifts line wraps or height | Keeps the same text layout boxes |
| Row height in tables | Hard to match edit height exactly | `computeHeightForWidth` uses the same engine as the widget |
| Decoration in grids | `InputDecoration` affects intrinsic height | `LazyInputDecoration` is height-neutral chrome |

Use `LazyTextField` when you render hundreds or thousands of editable cells and
need predictable memory use, stable row heights, and pixel-aligned transitions
between read-only and edit modes.

## Live demo

Explore the example app in the browser:

[Open the live demo](https://alexqwesa.github.io/lazy_text_field/)

The demo covers decoration modes, height modes, prefix icons, overflow markers,
and lazy controller allocation in a multi-column table.

## Choose a widget

| Widget | When to use |
| --- | --- |
| `LazyTextField` | You already own controller/focus state and pass them only while editing |
| `StatefulLazyTextField` | One-off cell where the widget can own its edit lifecycle |
| `LazyTextFieldControllerScope` + `ScopedLazyTextField` | Many cells sharing one edit manager |

## Usage

```dart
LazyTextField(
  cellId: 'row-42-title',
  text: value,
  isEditing: controller != null && focusNode != null,
  controller: controller,
  focusNode: focusNode,
  style: const TextStyle(fontSize: 14, height: 1.25),
  padding: kDefaultLazyTextFieldPadding,
  decoration: LazyInputDecoration(
    filled: true,
    border: const OutlineInputBorder(),
    hintText: 'Click to edit',
    prefixIcon: const Icon(Icons.notes, size: 16),
    prefixIconConstraints: const BoxConstraints(minWidth: 28),
  ),
  decorationVisibility: LazyInputDecorationVisibility.editing,
  onStartEditing: startEditing,
  onChanged: updateDraft,
)
```

When `isEditing` is true, provide both `controller` and `focusNode`. When it is
false, pass `null` for both so read-only mode stays lazy.

For simple local state, use `StatefulLazyTextField`. For many cells sharing one
edit manager, wrap a subtree in `LazyTextFieldControllerScope` and use
`ScopedLazyTextField`.

## Decoration

`LazyInputDecoration` is height-neutral chrome drawn outside the internal
`TextField`, which always receives `decoration: null`. Supported fields are
fill, hover/focus/error/disabled borders, hint text/style, prefix icon, suffix
icon, and icon constraints.

Decoration does not add padding. `LazyTextField.padding` is the only content
padding source.

## Overflow marker

When read-only text is clipped, `LazyTextField` shows a default red corner
marker. Customize it with `overflowMarkerBuilder`, or pass `null` to hide it:

```dart
LazyTextField(
  cellId: 'row-42-notes',
  text: value,
  isEditing: false,
  onStartEditing: startEditing,
  overflowMarkerBuilder: (context, details) {
    return Icon(
      details.expanded ? Icons.unfold_less : Icons.more_horiz,
      size: details.size,
      color: details.color,
    );
  },
)
```

The package still owns marker positioning and tap handling, so marker taps call
`onReadOnlyOverflowToggle` without also starting cell editing. Use
`LazyTextField.defaultOverflowMarkerBuilder` to delegate back to the default
triangle from a custom builder.

## Height Measurement

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

The layout path uses `TextPainter`, the effective text width, strut style, text
direction, text scaler, a zero-width space for empty text and trailing newlines,
and ceiled final heights.

For bounded editing, `scrollbarGutter` reserves text width for the package
scrollbar. Use `scrollbarThickness` and `scrollbarAlignment` to control the
thumb size and where it sits inside that reserved gutter.

## API documentation

Full API reference is published to [pub.dev/documentation](https://pub.dev/documentation/lazy_text_field/latest/)
after release.

To generate docs locally:

```sh
dart doc
open doc/api/index.html
```

## Example app

```sh
cd example
flutter run -d chrome
```

The example covers edit-only and always-visible decoration, constrained
wrapping, bounded height with scrollbar gutter, prefix/suffix icons, and lazy
controller allocation in large lists.

## License

MIT — see [LICENSE](LICENSE).
