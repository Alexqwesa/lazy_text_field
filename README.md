# lazy_text_field

[![Tests](https://github.com/Alexqwesa/lazy_text_field/actions/workflows/lazy_text_field.yml/badge.svg)](https://github.com/Alexqwesa/lazy_text_field/actions/workflows/lazy_text_field.yml)
[![pub package](https://img.shields.io/pub/v/lazy_text_field.svg)](https://pub.dev/packages/lazy_text_field)
[![pub points](https://img.shields.io/pub/points/lazy_text_field)](https://pub.dev/packages/lazy_text_field/score)
[![Live demo](https://img.shields.io/badge/live%20demo-open-blue)](https://alexqwesa.github.io/lazy_text_field/)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](https://opensource.org/licenses/MIT)

Lazy Material text fields for large Flutter tables and grids.

`LazyTextField` keeps a native `InputDecorator` visible in read-only mode, but
does not allocate a `TextField`, `EditableText`, controller, focus node, or
editing infrastructure until the cell is activated. The same decorator remains
mounted while its lightweight text child is replaced by the real editor.

When decoration geometry remains stable, switching between display and editing
modes preserves the field bounds, text viewport, baseline, wrapping, and glyph
position. Flutter's normal focus, floating-label, color, and border transitions
remain animated.

## Live demo

[Open the live demo](https://alexqwesa.github.io/lazy_text_field/)

The demo covers native decoration, constrained wrapping, bounded editing,
overflow markers, selection policies, and lazy controller allocation.
The whole page mounts only one real `TextField` / `EditableText` at a time.

Run it locally:

```sh
cd example
flutter run -d chrome -t lib/main_live_demo.dart
```

## Installation

```yaml
dependencies:
  lazy_text_field: ^2.0.2
```

```dart
import 'package:lazy_text_field/lazy_text_field.dart';
```

## Why use it?

| | `TextField` in every cell | `LazyTextField` |
| --- | --- | --- |
| Controllers and focus nodes | One per mounted field | Created only for active editors |
| Editing infrastructure | Mounted for every field | Mounted only while editing |
| Material decoration | Native `InputDecoration` | The same native `InputDecoration` |
| Static-to-edit switch | Separate overlays can reflow or misalign | One persistent decorator and stable text viewport |
| Undecorated row metrics | Requires separate measurement | Exact text-viewport measurement helpers |

## Choose a widget

| Widget | When to use |
| --- | --- |
| `LazyTextField` | You own controller and focus state |
| `StatefulLazyTextField` | The cell can own its edit lifecycle |
| `LazyTextFieldControllerScope` + `ScopedLazyTextField` | Many cells share one edit manager |

## Usage

```dart
LazyTextField(
  cellId: 'row-42-title',
  text: value,
  isEditing: controller != null && focusNode != null,
  controller: controller,
  focusNode: focusNode,
  style: const TextStyle(fontSize: 14, height: 1.25),
  decoration: const InputDecoration(
    filled: true,
    border: OutlineInputBorder(),
    labelText: 'Title',
    hintText: 'Click to edit',
    prefixIcon: Icon(Icons.notes),
    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
  ),
  onStartEditing: startEditing,
  onChanged: updateDraft,
)
```

When `isEditing` is true, provide both `controller` and `focusNode`. Pass null
for both in read-only mode.

`StatefulLazyTextField` and `ScopedLazyTextField` support
`startEditSelection`: `beginning`, `end`, `tapPosition`, or `fullSelection`.

## Decorations support and stability

`LazyTextField` uses Flutter's native `InputDecoration` and keeps the same
`InputDecorator` mounted in both display and editing modes.

### Supported decorations

- Filled and outlined borders
- Floating labels and hint text
- Prefix and suffix text/icons
- Helper text and character counters
- Content padding, density, and constraints
- Material 2 and Material 3 themes
- Focus, label, color, and border animations
- Custom decoration widgets with stable dimensions

### Limitations

**No-layout-jump guarantee**

The field bounds, text viewport, baseline, wrapping, and glyph position remain
stable when decoration geometry does not change between display and editing
modes.

Adding, removing, or resizing decoration content may change the layout. This
includes changes to padding, constraints, icon sizes, and supporting-text
regions.

**Validation errors**

`InputDecoration.errorText` and `InputDecoration.error` are not supported.

Use `LazyTextField.errorMessage` instead. It displays validation errors in an
overlay without changing the field's layout. Keep `onSave` as the commit gate:

```dart
String? error;

StatefulLazyTextField(
  cellId: 'quantity',
  text: quantity,
  errorMessage: error,
  onChanged: (_) => setState(() => error = null),
  onSave: (value) {
    if (value.isEmpty) {
      setState(() => error = 'Required');
      return false;
    }
    setState(() => error = null);
    return saveQuantity(value);
  },
)
```

In debug builds, a non-empty `InputDecoration.errorText` / non-null `error`
asserts. In all builds those fields are stripped before the decorator mounts
(`copyWith(errorText: null)` cannot clear them — Flutter keeps the old value).

**Dynamic decoration**

For controls that appear only during editing, reserve their layout space in both
modes and change only their visibility:

```dart
InputDecoration(
  suffixIconConstraints: const BoxConstraints.tightFor(
    width: 40,
    height: 40,
  ),
  suffixIcon: IgnorePointer(
    ignoring: !isEditing,
    child: AnimatedOpacity(
      duration: const Duration(milliseconds: 150),
      opacity: isEditing ? 1 : 0,
      child: const Icon(Icons.check),
    ),
  ),
)
```

Alternatively, use an external overlay. Reserve its width in both modes when it
must not cover text:

```dart
Stack(
  children: [
    LazyTextField(
      cellId: cellId,
      text: value,
      isEditing: isEditing,
      controller: controller,
      focusNode: focusNode,
      reservedTrailingWidth: 40,
      decoration: const InputDecoration(
        border: OutlineInputBorder(),
        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
      onStartEditing: startEditing,
    ),
    if (isEditing)
      const PositionedDirectional(
        end: 0,
        top: 0,
        width: 40,
        bottom: 0,
        child: Icon(Icons.check),
      ),
  ],
)
```

If different field geometry is required while editing, use a conventional
overlay `TextField`.

## Overflow marker

When read-only text is clipped by `maxHeight`, a corner marker is shown.
Customize or hide it with `overflowMarkerBuilder`:

```dart
LazyTextField(
  cellId: 'row-42-notes',
  text: value,
  isEditing: false,
  maxHeight: 48,
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

`minHeight` and `maxHeight` constrain the text viewport. Native label,
helper, error, and counter regions remain outside that viewport.

For uniform table rows, set both bounds to the same finite value:

```dart
LazyTextField(
  cellId: row.id,
  text: row.value,
  isEditing: isEditing,
  minHeight: 40,
  maxHeight: 40,
  onStartEditing: startEditing,
)
```

Equal bounds activate a fixed-height fast path. The viewport width and height
are derived without laying out the text during sizing, so each row avoids
content-dependent height measurement. Text layout is still required for
painting, hit testing, and overflow detection.

## Height measurement

`LazyTextField.computeHeightForWidth`, `LazyTextFieldLayout`, and
`LazyTextFieldMetrics` measure the undecorated text viewport exactly:

```dart
final viewportHeight = LazyTextField.computeHeightForWidth(
  text: value,
  width: columnWidth,
  style: const TextStyle(fontSize: 14, height: 1.25),
  padding: kDefaultLazyTextFieldPadding,
);
```

These synchronous helpers cannot include arbitrary `InputDecoration` widgets,
whose intrinsic sizes are known only during Flutter layout. Use fixed external
constraints or measure the rendered row when full decorated height is needed.

Each mounted lazy field caches its viewport layout per width and invalidates the
cache only when text or relevant layout inputs change. Uniform rows with equal
`minHeight` and `maxHeight` bypass that text measurement entirely during sizing.

## Migrating from 1.x

- Replace `LazyInputDecoration` with `InputDecoration`.
- Move `LazyTextField.padding` to `InputDecoration.contentPadding`.
- Remove `decorationVisibility`; the native decorator remains mounted in both
  modes to guarantee stable geometry.
- Replace edit-only decoration changes with fixed slots or overlays.

## License

MIT - see [LICENSE](LICENSE).
