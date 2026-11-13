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

### Main demo: data saving (3.0)

[Open the main demo](https://alexqwesa.github.io/lazy_text_field/)

Explore `ScopedLazyTextField` with queued saves, draft recovery, mock API failures, and virtualized cells. 
Configure save policies, draft storage, cell height, and text styling. 
Monitor changes through a live status bar and event log.

### Basic demo: standalone fields

[Open the basic demo](https://alexqwesa.github.io/lazy_text_field/basic/)

Explore `LazyTextField` without a shared save controller. Demonstrates native decorations, 
text wrapping, overflow handling, selection, and lazy editor allocation.

## Installation

```yaml
dependencies:
  lazy_text_field: ^3.0.0
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
| `LazyTextFieldScope` + `ScopedLazyTextField` | Many cells share one edit manager   |

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

### Keyboard shortcuts

In an open `StatefulLazyTextField` or `ScopedLazyTextField` editor:

| Key | Action |
|---|---|
| Ctrl+S, Cmd+S, Ctrl+Enter, Cmd+Enter | save |
| Escape | cancel: close without saving (a scoped cell also discards its unsaved or failed draft) |
| Enter in a `singleLine` field | save (always on) |

Change them for every field below a `LazyTextFieldScope` (its `shortcuts`),
or for one field with its `shortcuts` parameter. Leave a key out of the map
to turn it off:

```dart
// Escape is left to the surrounding dialog; F2 cancels instead.
final shortcuts = Map.of(LazyTextFieldScope.defaultShortcuts)
  ..remove(const SingleActivator(LogicalKeyboardKey.escape))
  ..[const SingleActivator(LogicalKeyboardKey.f2)] = LazyTextFieldAction.cancel;

LazyTextFieldScope(shortcuts: shortcuts, child: grid);
```

The field's focus node sees keys before a `Shortcuts` widget above it, so a
`Shortcuts` widget cannot change these keys; use the scope's `shortcuts`.
A `LazyTextFieldScope` that only sets `shortcuts` works for
`StatefulLazyTextField` too; inside a grid's scope it keeps the grid's
controller.

### Switching between scoped cells

When a `ScopedLazyTextField` starts editing, the shared
`LazyTextFieldEditController` closes the other active cells and saves their
text, as a tap outside the editor does: the previous cell's `onSave` (or
`onCommit`) is called with its changed text, and the new cell gets focus
immediately. The save runs in the background. The previous editor is already
closed, so its text is kept as a draft: shown while saving and, if `onSave`
returns `false` or throws, kept as a failed draft that reopening the cell
restores and Escape discards. Unchanged text is not saved.

An editing cell that leaves the tree without a submit (recycled for another
`cellId`, or disposed by a virtualized grid that scrolled it away) is not
saved: its text is kept as an `unsaved` draft (see
[Unsaved drafts](#unsaved-drafts-save-all-and-local-storage)). Flutter's
`ListView` keeps a focused field alive by default, so there the editor simply
stays open.

> **Behavior change in 3.0.0:** switching cells used to drop the unsaved
> text. It is now passed to `onSave` / `onCommit`, and text of cells that
> leave the tree is kept as an unsaved draft. Make `onSave` tolerate being
> called for a cell that is no longer editing. See
> [Migrating from 2.x](#migrating-from-2x).

### Background saves with drafts

For grids that save to a server, give cells `onCommit` instead of `onSave`.
No extra setup is needed: the scope's controller (your own
`LazyTextFieldEditController` or the one the scope creates) keeps a *draft*
of each committed value and shows it after the editor closes:

- **unsaved** when it was kept without saving (see below),
- **pending** while it is queued or saving,
- **saved** until the cell's `text` changes (the refreshed value arrives;
  stale refreshes that still return an older value are ignored),
- **failed** if `onCommit` threw, until it is saved again, Escape is pressed
  in that cell, or `clearDraft` is called.

```dart
LazyTextFieldScope(child: grid); // saves one at a time

// In a cell:
ScopedLazyTextField(
  cellId: '${item.id}/name',
  text: item.name,
  rowId: item.id,
  onCommit: (value) => api.updateName(item.id, value), // throw to fail
  errorMessageOf: (error) => 'Not saved: $error',
);

// Status for your own decoration (rebuilds when drafts change):
final status = LazyTextFieldScope.maybeOf(context)
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
- A draft belongs to its cell (`cellId`) unless the cell says which record
  it edits: a `tableId` on the scope, a row id, and a `fieldId` on the cell
  (see [Keeping drafts across restarts](#keeping-drafts-across-restarts-hive-etc)).
  Then it follows the record when rows are sorted, filtered, or reloaded,
  and two tables never share one. `draftKey` sets the key directly, for
  example to let several cells share one draft.

**Save order.** Every save goes through one queue: `onCommit` commits,
`onSave` calls (on submit and on switch), `saveDrafts()`, and batches. A save
runs when its turn comes, so it can read state written by earlier saves (for
example a row version). Pass `saveOrder` to your own
`LazyTextFieldEditController` to change it.

| `saveOrder`                     | Behavior                                                                                                          |
|---------------------------------|-------------------------------------------------------------------------------------------------------------------|
| `sequential` (default)          | One save at a time, in queue order.                                                                               |
| `perRow`                        | Saves with the same `rowId` (from the cell or a `LazyTextFieldScope.row`) run in order; different rows run in parallel. Cells without a row share a queue. |

In both orders, **saves of the same draft key never overlap**: a newer value
is sent only after the older save finished, so the older one cannot land
last and overwrite it on the server. Under `sequential`, an `onSave` submit
waits for earlier saves, also of other cells, and its editor stays open
until its turn. The queue keeps one client in order; if several clients edit
the same record, check row versions on the server as well.

### Unsaved drafts, "Save all", and local storage

An `unsaved` draft is text that was kept but not saved:

- **A cell left the tree while editing.** A virtualized grid disposed it
  while scrolling, a data refresh replaced it, or it was recycled for another
  `cellId`. That is not a request to save, so half-typed text is not sent.
  The cell shows the draft when it is built again, and reopening it continues
  the text; Escape discards it.
- **Deferred mode** (below): every change is kept until you save it.

> **Unsaved drafts are not saved on their own.** A draft kept when its cell
> left the tree is saved when another cell starts editing (in `immediate`
> mode) or when you call `saveDrafts()`. If the user never edits another cell
> and the app never calls `saveDrafts()` (for example the screen closes or the
> app is killed), **the text is never saved**. It lives only in memory, unless
> you set a `draftStore`. Call `saveDrafts()` before leaving the screen, or
> check `unsavedChanges()` and ask the user.

```dart
// Before leaving the screen: commits open editors, saves every unsaved and
// failed draft, and waits for saves that were already running.
final result = await editController.saveDrafts();
if (!result.allSaved) showUnsavedChangesDialog(result.remaining);

// Or ask first. unsavedChanges() lists drafts that are not saved and open
// editors whose text changed; hasUnsavedChanges is the yes/no.
if (editController.hasUnsavedChanges) {
  showUnsavedChangesDialog(editController.unsavedChanges().length);
}
```

Each `LazyTextFieldUnsavedChange` has the draft key, the text not saved yet
(the editor's text while `isEditing`), the text and record version before
the change (`baseText`, `baseVersion`), and the `draft`, if any, with its
status. Listeners of the
controller are notified when an open editor's text first differs from the
text it opened with, and when it matches again, not on every keystroke.

#### Deferred mode: "Save all"

```dart
final editController = LazyTextFieldEditController(
  saveMode: LazyTextFieldSaveMode.deferred,
);

// Save button: each draft through its own cell's onCommit (queued)...
await editController.saveDrafts();

// ...or all drafts in one request.
await editController.saveDrafts(
  batch: (values) async {          // {draftKey: value}
    final rejected = await api.saveMany(values);
    return rejected;               // {draftKey: error} for failed drafts
  },
);
```

- In `deferred` mode, Enter, switching cells, and cells leaving the tree only
  keep `onCommit` text as `unsaved` drafts. Nothing is sent until
  `saveDrafts()`. `onSave` cells still save on submit and on switch.
- `saveDrafts()` first commits open editors (`includeOpenEdits: false` to
  skip them), then saves `unsaved` and `failed` drafts. With `batch`, the
  text of open editors goes out in the batch too, not through each cell's
  own save. It also waits for saves that were already queued or running,
  including `onSave` submits.
- The result counts what this call sent (`saved`, `failed`, `skipped`) and
  what is still not saved when it returns (`remaining`): failures, drafts
  without a saver, earlier saves that failed, and **text changed again while
  saving**. `allSaved` is true only when `failed` and `remaining` are 0, so
  it never claims success while a newer change is waiting.
- Each saved draft calls its cell's `onSaved`, even if the cell left the
  tree. A `batch` does not call `onSaved`; use its result or
  `onSavesSettled`.
- A batch gets `{draftKey: value}` and returns the errors of drafts that
  failed (missing or null means saved). If it throws, every draft fails with
  that error. For cells that know their record (see below), each key is a
  `LazyTextFieldDraftId` that names the table, row, and field to write.
- `immediate` mode (default) also saves unsaved drafts when another cell
  starts editing.

#### Keeping drafts across restarts (Hive, etc.)

Give the controller a `LazyTextFieldDraftStore`. It writes `unsaved`,
`pending`, and `failed` drafts, and deletes them once saved or discarded:

```dart
class HiveDraftStore implements LazyTextFieldDraftStore {
  HiveDraftStore(this.box);
  final Box<Map> box;

  @override
  Iterable<LazyTextFieldStoredDraft> load() => box.values.map(
    (m) => LazyTextFieldStoredDraft.fromJson(m.cast<String, Object?>()),
  );

  @override
  Future<void> put(LazyTextFieldStoredDraft draft) =>
      box.put(draft.key, draft.toJson());

  @override
  Future<void> delete(String key) => box.delete(key);
}

final editController = LazyTextFieldEditController(
  saveMode: LazyTextFieldSaveMode.deferred,
  draftStore: HiveDraftStore(box),
);
await editController.loadDrafts(); // at startup
```

**Every draft must say which record it belongs to**, or it is never
written to the store. Name the table once on the scope, the row and its
version once per row, and the field on each cell:

```dart
LazyTextFieldScope(
  controller: editController,
  tableId: 'orders',                          // table, collection, or type
  child: ListView.builder(
    itemCount: orders.length,
    itemBuilder: (context, i) {
      final order = orders[i];
      return LazyTextFieldScope.row(
        rowId: order.id,                      // the record's id, not i
        version: order.updatedAt.toIso8601String(), // or a revision, ETag
        child: Row(
          children: [
            Expanded(
              child: ScopedLazyTextField(
                cellId: 'orders/${order.id}/name',
                fieldId: 'name',
                text: order.name,
                onCommit: (value) => api.updateName(order.id, value),
              ),
            ),
            // ...more cells with their own fieldId
          ],
        ),
      );
    },
  ),
);
```

- The cell's draft key is then
  `LazyTextFieldDraftId(table: 'orders', row: '42', field: 'name')`. A cell's
  own `rowId` and `version` win over the row scope's, so cells without a row
  scope can give them directly. A nested `LazyTextFieldScope(tableId: ...)`
  covers a second table with the same controller (a scope without a
  `controller` uses the one above).
- `draftKey: LazyTextFieldDraftId(...)` on a cell sets the id directly, for
  a cell that cannot use the scopes (it still needs a `version`).
- A draft is stored only with a `LazyTextFieldDraftId` key whose table, row,
  and field are not empty, and a version. If any is missing (for example a
  cell without `fieldId`, whose key is then its `cellId`), the draft is
  **not written at all**: it is kept in memory only, reported to
  `FlutterError` once (in release builds too) with what is missing, and
  `whenDraftsStored()` returns false while it exists. Without a store,
  nothing is required.
- The id is the store key (`'orders/42/name'`, `LazyTextFieldStoredDraft.key`),
  so after a restart a draft goes back to the same record, whichever cell
  shows it now. Even with cell ids that are list positions, a draft never
  lands in the wrong row: if rows are re-sorted while an editor is open, its
  text is kept as a draft for the record it was opened on.
- `version` is stored as the draft's `baseVersion`: the version of the record
  the change started from. It stays the version of the first change until
  the draft is saved or discarded.
- Several controllers can share one store (one per account, for example).
  Each loads only its own drafts with
  `loadDrafts(where: (id) => id.table == 'orders')`.
- Restored drafts come back as `unsaved`, also those that were saving when
  the app stopped, so they may be sent again. Make the save idempotent.
- A restored draft is shown, and gets its saver, when its cell is built.
  `saveDrafts()` skips restored drafts whose cell has not been built yet;
  `saveDrafts(batch: ...)` includes them.
- **Restored drafts are not saved on their own.** Unlike text kept in this
  session, they are not saved when another cell starts editing: the user
  has not seen them yet, and the server value may have changed while the
  app was closed. They are saved when the user commits one from its cell,
  or by `saveDrafts()`. `draft.restored` tells them apart, for example to
  mark them in the cell or compare `draft.baseVersion` (or `baseText`) with
  the record on the server first.
- Failure errors are not stored.
- Store calls run one at a time, in the order the drafts changed: a `delete`
  starts only after the earlier `put` finished, so a deleted draft cannot
  come back. A failed write is reported to `FlutterError` and the next one
  still runs; `draftStoreErrors` lists the keys whose last write failed.
  `loadDrafts()` waits for queued writes.
- **Writes are asynchronous: the app can stop before they land.** Before
  telling the user their changes are kept, or before leaving the screen,
  await `whenDraftsStored()`. It waits for queued writes, retries failed ones
  once, and returns whether the store holds every unsaved draft.

```dart
if (!await editController.whenDraftsStored()) {
  showError('Could not keep your unsaved changes on this device.');
}
```

- **Text in an open editor is not a draft**, so by default it reaches the
  store only when the editor closes; an app killed while the user types
  loses it. `storeOpenEdits()` writes it now, without closing the editor or
  saving anything, for example when the app goes to the background.
  `storeOpenEditsAfter` does the same after a pause in typing. After a
  restart, `loadDrafts()` brings the text back as a restored draft. When the
  editor closes, the store holds its draft again, if any.

```dart
final editController = LazyTextFieldEditController(
  draftStore: HiveDraftStore(box),
  storeOpenEditsAfter: const Duration(seconds: 1),
);

// In a WidgetsBindingObserver:
@override
void didChangeAppLifecycleState(AppLifecycleState state) {
  if (state == AppLifecycleState.paused) editController.storeOpenEdits();
}
```

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

`editingMaxHeight` is the deliberate exception: above `maxHeight`, it lets the
editor grow taller than the read-only field as text is typed (see
[Growing a row while a cell edits](#growing-a-row-while-a-cell-edits)). Width,
wrapping, and glyph positions still do not change.

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
  suffixIconConstraints: const BoxConstraints.tightFor(width: 40, height: 40),
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

When an editor scrolls and its text reaches the top or bottom, further
mouse-wheel scrolling moves the surrounding page or grid, as in any Flutter
app. Pass `chainEditorScroll: false` to keep the page still while the pointer
is over such an editor. Editors whose text fits, and read-only cells, still
let the page scroll.

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
  onEditingExtraHeightChanged: (extra) {      // editorHeight - maxHeight
    if (mounted) grid.setExtraRowHeight(rowKey, cellId, extra);
  },
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
- The final 0 after a dispose arrives in the next frame, when your widget may
  be disposed too (the screen was popped): check `mounted` before
  `setState`.
- A new callback instance (an inline closure rebuilt each frame) is treated
  as the same consumer: it gets the next change, and the current value is not
  re-sent, which would loop through `setState`. To hand the field to a
  different consumer, pass null for one build or give the field a new key.

## Migrating from 2.x

`LazyTextFieldControllerScope` is now `LazyTextFieldScope` (same arguments,
plus `tableId` and `shortcuts`): rename it.

Code that uses only `LazyTextField` or `StatefulLazyTextField` needs no
changes. 3.0 is a major version because `ScopedLazyTextField` with a
`LazyTextFieldEditController` now keeps text that 2.x dropped, and saves in
one queue. The API is the same, so your code compiles; check these
behaviors:

1. **Switching cells saves the text.** In 2.x, clicking another cell dropped
   the text typed in the open one. Now `onSave` is called with it in the
   background, after its editor has closed. Make sure `onSave` does not rely
   on the cell still editing (its controller or context). If `onSave`
   returns `false` or throws, the text stays as a failed draft. There is no
   option to drop the text as 2.x did; a tap outside the editor already
   saved it in 2.x too.

2. **Cells that leave the tree keep their text.** A cell recycled for
   another `cellId` or disposed by a virtualized grid while editing keeps
   its text as an `unsaved` draft. It is saved when another cell starts
   editing or by `saveDrafts()`, and otherwise never. Save it before the
   user leaves the screen:

   ```dart
   final result = await editController.saveDrafts();
   if (!result.allSaved) showUnsavedChangesDialog(result.remaining);
   ```

3. **`onSave` calls go through one save queue.** Saves of one cell never
   overlap. With the default `LazyTextFieldSaveOrder.sequential`, saves of
   different cells do not overlap either: a submit waits for earlier saves,
   and its editor stays open until then. If your rows are independent and
   the server is slow, use `saveOrder: LazyTextFieldSaveOrder.perRow` and
   give cells a `rowId` (or a `LazyTextFieldScope.row`). Remove your own "latest save wins" or "save in
   flight" guards; the queue does this.
4. **`onSaved` runs after every successful save,** including saves on
   switch, from `saveDrafts()`, and after the cell left the tree. Update
   your model in it; do not use the cell's `BuildContext`.
5. **Counters include `onSave`:** `pendingSaves`, `onSavesSettled`, and
   `whenSavesSettled()` count `onSave` calls too.
6. **`stopEditing(notify: false)` notifies after the frame,** so listeners
   of the controller may see one more notification.

Optional: if you kept your own draft map, save queue, or "Save all" logic
around `ScopedLazyTextField`, see
[Background saves with drafts](#background-saves-with-drafts) and
[Unsaved drafts](#unsaved-drafts-save-all-and-local-storage): `onCommit`,
`drafts`, `saveDrafts()`, and `draftStore` replace them. The
[main demo](https://alexqwesa.github.io/lazy_text_field/) shows each option.

## Migrating from 1.x

- Replace `LazyInputDecoration` with `InputDecoration`.
- Move `LazyTextField.padding` to `InputDecoration.contentPadding`.
- Remove `decorationVisibility`; the native decorator remains mounted in both
  modes to guarantee stable geometry.
- Replace edit-only decoration changes with fixed slots or overlays.

## License

MIT - see [LICENSE](LICENSE).
