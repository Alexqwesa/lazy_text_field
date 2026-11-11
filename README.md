# lazy_text_field

[![Tests](https://github.com/Alexqwesa/lazy_text_field/actions/workflows/lazy_text_field.yml/badge.svg)](https://github.com/Alexqwesa/lazy_text_field/actions/workflows/lazy_text_field.yml)
[![Coverage](https://codecov.io/gh/Alexqwesa/lazy_text_field/graph/badge.svg)](https://codecov.io/gh/Alexqwesa/lazy_text_field)
[![pub package](https://img.shields.io/pub/v/lazy_text_field.svg)](https://pub.dev/packages/lazy_text_field)
[![pub points](https://img.shields.io/pub/points/lazy_text_field)](https://pub.dev/packages/lazy_text_field/score)
[![Live demo](https://img.shields.io/badge/live%20demo-open-blue)](https://alexqwesa.github.io/lazy_text_field/)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](https://opensource.org/licenses/MIT)

Lazy Material text fields for large Flutter tables and grids.

LazyTextField renders lightweight text with native InputDecoration, creating a real TextField only while editing.
Switching modes preserves text alignment, wrapping, and layout without interrupting Material animations.

Most `InputDecoration` features are supported when kept geometry-equivalent
across the mode switch. Debug builds assert on layout-unstable
`errorText` / `error` (those slots are also stripped). Use `errorMessage`
for validation without layout shifts.

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
  lazy_text_field: ^2.1.0
```

```dart
import 'package:lazy_text_field/lazy_text_field.dart';
```

## Why use it?

|                             | `TextField` in every cell                | `LazyTextField`                                   |
|-----------------------------|------------------------------------------|---------------------------------------------------|
| Controllers and focus nodes | One per mounted field                    | Created only for active editors                   |
| Editing infrastructure      | Mounted for every field                  | Mounted only while editing                        |
| Material decoration         | Native `InputDecoration`                 | The same native `InputDecoration`                 |
| Static-to-edit switch       | Separate overlays can reflow or misalign | One persistent decorator and stable text viewport |
| Undecorated row metrics     | Requires separate measurement            | Exact text-viewport measurement helpers           |

## Choose a widget

| Widget                                                 | When to use                         |
|--------------------------------------------------------|-------------------------------------|
| `LazyTextField`                                        | You own controller and focus state  |
| `StatefulLazyTextField`                                | The cell can own its edit lifecycle |
| `LazyTextFieldControllerScope` + `ScopedLazyTextField` | Many cells share one edit manager   |

## Usage

```dart
LazyTextField
(
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
onChanged: updateDraft
,
)
```

When `isEditing` is true, provide both `controller` and `focusNode`. Pass null
for both in read-only mode.

`StatefulLazyTextField` and `ScopedLazyTextField` support
`startEditSelection`: `beginning`, `end`, `tapPosition`, or `fullSelection`.

### Switching between scoped cells

When a `ScopedLazyTextField` starts editing, the shared
`LazyTextFieldEditController` closes the other active cells. Its
`switchPolicy` decides what happens to their unsaved text:

- `LazyTextFieldSwitchPolicy.commit` (default since 2.1.0): the previous
  cell's `onSave` is called with its text, and the new cell gets focus
  immediately. The save runs in the background; the previous editor is
  already closed, so returning `false` only skips `onSaved`.
- `LazyTextFieldSwitchPolicy.discard`: the previous text is dropped
  (2.0 behavior).

```dart
final editController = LazyTextFieldEditController(
  switchPolicy: LazyTextFieldSwitchPolicy.discard, // opt out of commit
);
```

> **Behavior change in 2.1.0:** switching cells used to drop the previous
> draft. It is now passed to `onSave`. Make `onSave` tolerate being called
> for a cell that is no longer editing, or pass
> `LazyTextFieldSwitchPolicy.discard`.

### Background saves with drafts

For grids that save to a server, give cells `onCommit` instead of `onSave`.
No extra setup is needed: the scope's controller (your own
`LazyTextFieldEditController` or the one the scope creates) keeps a *draft*
of each committed value and shows it after the editor closes:

- **pending** while it is queued or saving,
- **saved** until the cell's `text` changes (the refreshed value arrives;
  stale refreshes that still return an older value are ignored),
- **failed** if `onCommit` threw, until it is saved again, Escape is pressed
  in that cell, or `clearDraft` is called.

```dart
LazyTextFieldControllerScope(child: grid); // saves one at a time

// In a cell:
ScopedLazyTextField(
  cellId: '${item.id}/name',
  text: item.name,
  rowKey: item.id,
  onCommit: (value) => api.updateName(item.id, value), // throw to fail
  errorMessageOf: (error) => 'Not saved: $error',
);

// Status for your own decoration (rebuilds when drafts change):
final status = LazyTextFieldControllerScope.maybeOf(context)
    ?.draftFor('${item.id}/name')
    ?.status;
```

- Clicking another cell focuses it immediately and queues the previous
  cell's draft.
- `closeOnSubmit` decides when Enter / Ctrl+S / tap outside close the editor:
  `afterSave` (default) keeps it open until the save succeeds and closes it
  only if the text did not change meanwhile; `immediately` closes at once.
- Submitting unchanged text closes the editor without a commit, unless the
  draft failed (then it retries).
- A failed draft's error is shown in the `errorMessage` popup while that cell
  is editing; typing hides it until the next commit.
- `draftKey` (default `cellId`) lets several cells share one draft.

**Save order.** `onCommit` runs when its turn in the queue comes, so it can
read state written by earlier saves (for example a row version). Pass
`saveOrder` to your own `LazyTextFieldEditController` to change it.

| `saveOrder`                     | Behavior                                                                                                          |
|---------------------------------|-------------------------------------------------------------------------------------------------------------------|
| `sequential` (default)          | One commit at a time, in queue order.                                                                             |
| `perRow`                        | Commits with the same `rowKey` run in order; different rows run in parallel. Cells without `rowKey` share a queue. |

### Refreshing data around edits

Replacing grid rows while a cell is editing disposes its editor and the
user's unsaved text. Two signals let the host time its refreshes:

- `LazyTextFieldEditController.whenEditingDone()` completes when no cell is
  editing (immediately if none is). Switching from one cell to another does
  not complete it. Await it before applying fetched rows; check `activeIds`
  again afterwards if editing may have restarted.
- `LazyTextFieldEditController(onSavesSettled: (saved, failed) { ... })` is
  called each time the save queue becomes empty, with counts since it was
  last empty. Refresh once there instead of after every save.
  `whenSavesSettled()` is the awaitable form.

```dart
late final drafts = LazyTextFieldEditController(
  onSavesSettled: (saved, _) {
    if (saved > 0) reloadPage();
  },
);

Future<List<Row>> fetchPage() async {
  final rows = await api.fetchPage();
  while (drafts.activeIds.isNotEmpty) {
    await drafts.whenEditingDone();
  }
  return rows;
}
```

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

`InputDecoration.errorText` and `InputDecoration.error` are not supported
(including empty `errorText: ''`). They are the only decoration slots treated
as known layout-unstable today; debug builds assert if they are set, and they
are stripped before the decorator mounts. `LazyTextField.isDecorationLayoutStable`
checks those slots only — it cannot prove that custom decoration widgets keep
stable intrinsic sizes across the mode switch.

Use `LazyTextField.errorMessage` instead. It displays validation errors in an
overlay without changing the field's layout. Keep `onSave` as the commit gate:

```dart
String? error;

StatefulLazyTextField
(
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
InputDecoration
(
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
Stack
(
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
child: Icon(Icons.
check
)
,
)
,
]
,
)
```

If different field geometry is required while editing, use a conventional
overlay `TextField`.

## Overflow marker

When read-only text is clipped by `maxHeight`, a corner marker is shown.
Customize or hide it with `overflowMarkerBuilder`:

```dart
LazyTextField
(
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
LazyTextField
(
cellId: row.id,
text: row.value,
isEditing: isEditing,
minHeight: 40,
maxHeight:
40
,
onStartEditing
:
startEditing
,
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

### How the height parameters relate

All heights are for the text viewport: the text area inside the decoration.

| Mode      | Viewport height                                         | Taller text |
|-----------|---------------------------------------------------------|-------------|
| read-only | text height, clamped to `minHeight`..`maxHeight`        | clipped, overflow marker |
| editing   | text height, clamped to `minHeight`..`editingMaxHeight` | scrolls     |

- `editingMaxHeight` defaults to `maxHeight`, so without it both modes use the
  same limits (the 2.0 behavior).
- `editingMaxHeight: double.infinity` means no limit while editing: the editor
  grows with all of its text and never scrolls; read-only stays clipped.
- `maxHeight: null` means no limit: the viewport grows with its text in both
  modes and `editingMaxHeight` is ignored.
- `onEditingExtraHeightChanged` reports `editorHeight - maxHeight` while
  editing (0 otherwise).

Example: `minHeight: 20, maxHeight: 20, editingMaxHeight: 60`

| Text needs | Read-only viewport | Editor viewport | Reported extra |
|------------|--------------------|-----------------|----------------|
| 10 px      | 20 px              | 20 px           | 0              |
| 40 px      | 20 px (clipped)    | 40 px           | 20             |
| 100 px     | 20 px (clipped)    | 60 px (scrolls) | 40             |

With `editingMaxHeight: double.infinity`, the last row becomes an editor of
100 px that does not scroll, reporting 80.

### Growing a row while a cell edits

Grid rows usually have a fixed height that clips long text. To let the editor
grow with its text while it is open, set `editingMaxHeight` above `maxHeight`
and grow the row by the amount reported in `onEditingExtraHeightChanged`:

```dart
ScopedLazyTextField(
  cellId: cellId,
  text: value,
  minHeight: twoLines,
  maxHeight: twoLines,                       // read-only clip
  editingMaxHeight: screenHeight * 0.6,      // editor may grow up to this
  onEditingExtraHeightChanged: (extra) =>    // editorHeight - maxHeight
      grid.setExtraRowHeight(rowKey, cellId, extra),
  onCommit: save,
);
```

- `extra` is measured by the field's own layout at its real width, so the
  caller does not measure text.
- It is reported after the frame and only when it changes: it grows and
  shrinks as the user types, and goes back to 0 when editing stops or the
  cell is disposed.
- Pass `editingMaxHeight: double.infinity` to let the editor grow with all of
  its text and never scroll. Only do this when the row grows too; otherwise
  the extra lines are clipped and cannot be scrolled to.
- The scrollbar gutter stays reserved in both modes (also with
  `double.infinity`), so wrapping does not change when the editor grows.
- If several cells in a row can edit, keep the largest `extra` per row.

## Migrating from 1.x

- Replace `LazyInputDecoration` with `InputDecoration`.
- Move `LazyTextField.padding` to `InputDecoration.contentPadding`.
- Remove `decorationVisibility`; the native decorator remains mounted in both
  modes to guarantee stable geometry.
- Replace edit-only decoration changes with fixed slots or overlays.

## License

MIT - see [LICENSE](LICENSE).
