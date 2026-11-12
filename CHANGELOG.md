# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).


## [3.0.1] - 2026-11-11

### Added

- `chainEditorScroll` (also on `ScopedLazyTextField`): set it to `false` so
  a mouse-wheel scroll over an editor whose text scrolls does not move the
  page once the text reaches its top or bottom. The default `true` keeps
  Flutter's behavior.


## [3.0.0] - 2026-11-11

Most of this release is about saving with `ScopedLazyTextField` and
`LazyTextFieldEditController`: text in a closed editor is no longer dropped,
and all saves run in one queue with drafts. For `LazyTextField` and
`StatefulLazyTextField` the only new option is a taller editor. Includes the
fixes from 2.0.3. The changes to `ScopedLazyTextField` and
`LazyTextFieldEditController` in short:

- Text left in an editor is now saved or kept as a draft, instead of being
  dropped. There is no option to keep the 2.0 behavior.
- All saves of a cell, including background ones, run in one queue. By
  default, saves of different cells run one at a time too.
- `onSaved` is called after background saves as well.

### LazyTextField, StatefulLazyTextField

#### Added

- `editingMaxHeight` and `onEditingExtraHeightChanged` (also on
  `ScopedLazyTextField`): the editor can grow taller than the read-only
  `maxHeight`, and the field reports how much taller it is (measured by its
  own layout) so a grid can grow the row while it edits.

### ScopedLazyTextField, LazyTextFieldEditController

#### Changed

- **Behavior change: text in a closed editor is kept.**
  - When another cell starts editing, the closed cell's changed text is saved
    with `onSave` in the background, and the new cell gets focus at once.
  - When an editing cell leaves the tree (recycled for another `cellId`, or
    disposed by a virtualized grid), its text becomes an `unsaved` draft. It
    is saved when another cell starts editing or by `saveDrafts()`. **If
    neither happens, it is never saved**, and it stays in memory only unless
    a `draftStore` is set.
  - If a save returns `false` or throws, the text stays as a failed draft:
    reopening the cell restores it, and Escape discards it.
  - There is no option to drop the text as 2.0 did: clicking anywhere
    outside the editor already saved it, so only switching cells and
    leaving the tree dropped it. To drop a kept draft, call
    `clearDraft(key)`.
- **Behavior change:** `onSave` calls go through the controller's save
  queue, like the new `onCommit`.
  - Saves of the same cell never overlap, including saves on switch and
    from `saveDrafts()` (2.0.3 already did this for submits).
  - Under the default `LazyTextFieldSaveOrder.sequential`, a submit also
    waits for earlier saves of other cells, and its editor stays open until
    then. Use `perRow` with `rowKey` to save different rows in parallel.
  - `pendingSaves` and `onSavesSettled` count `onSave` calls.
- **Behavior change:** `onSaved` is called after every successful save of
  the cell: on submit, on switch, from `saveDrafts()`, and after the cell
  left the tree. Batches do not call it.
- `stopEditing(notify: false)` now notifies listeners after the frame, so
  listeners also see editors closed by cells that left the tree. The new
  `holdDraft`, `enqueue`, and `trackDraft` do the same with `notify: false`.

#### Added

- Cell options:
  - `onCommit` (throw to fail), an alternative to `onSave`; give exactly one
    of the two.
  - `draftKey` and `rowKey`.
  - `closeOnSubmit` (`LazyTextFieldSubmitClose.afterSave` / `immediately`).
  - `errorMessageOf`.
- Drafts: `LazyTextFieldDraft` with `LazyTextFieldDraftStatus`
  (`pending`, `saved`, `failed`, `unsaved`). Controller members: `drafts`,
  `draftFor`, `displayText`, `clearDraft`, `holdDraft`, and
  `startEditing(draftKey:)`.
- The save queue: `LazyTextFieldSaveOrder` (`sequential` or `perRow`),
  `saveOrder`, `pendingSaves`, `onSavesSettled` (`LazyTextFieldSavesSettled`),
  `whenSavesSettled()`, and `whenEditingDone()` (switching cells does not
  complete it).
- For custom cells, saves in the queue:
  - `enqueue` saves a value as a draft.
  - `trackDraft` shows a value as a draft while a save you run reports
    success as a `bool`.
  - `queueSave` runs a save without a draft.
  - `setCommitHandler` / `removeCommitHandler`
    (`LazyTextFieldCommitHandler`) add commit-on-switch.
- "Save all" screens:
  - `LazyTextFieldSaveMode` (`immediate`, `deferred`).
  - `saveDrafts({batch, includeOpenEdits})` returns a
    `LazyTextFieldSaveDraftsResult`. It commits open editors and waits for
    running saves. `allSaved` is false while anything is `remaining`.
  - `commitAll()`, `setDraftSaver` (`LazyTextFieldDraftSaver`), and
    `LazyTextFieldBatchCommit`.
- Keeping drafts across restarts:
  - `LazyTextFieldDraftStore` (`draftStore`, `loadDrafts()`),
    `LazyTextFieldStoredDraft` (JSON), and `LazyTextFieldMemoryDraftStore`.
  - Store calls run one at a time, in order.
  - `whenDraftsStored()` retries failed writes and reports whether every
    draft is stored. `draftStoreErrors` lists the failed writes.
- New default example `example/lib/main.dart`: cells in a list that
  unmounts them, saved to a mock API that can be slow or fail, with
  switches for the save options, cell heights, and text style. The
  previous small example is now `example/lib/main_simple.dart`.

## [2.0.3] - 2026-11-12

### Fixed

- `ScopedLazyTextField`: an `onSave` submit that finished after the user had
  typed on, or closed and reopened the cell, closed the editor and dropped
  the newer text. The editor now closes only if it still shows the saved
  text.
- `ScopedLazyTextField`: `onSave` calls of one cell no longer overlap. A
  submit while a save is running (ignored before, or sent at once after
  Escape) now waits for it and then saves the current text, so an older save
  can no longer finish last and overwrite a newer value.
- `ScopedLazyTextField`: an exception thrown by `onSave` blocked every later
  save of the cell. It is now reported to `FlutterError` and treated as
  `false`.
- Recycling an editing `ScopedLazyTextField` for a new `cellId` notified the
  scope during build (`markNeedsBuild() called during build`).
- `LazyTextField` over `maxLength` set an empty `errorText` on the
  decoration. Only the counter takes the error color now; the border no
  longer turns red.

### Added

- `LazyTextField.isDecorationLayoutStable(decoration)`: the check behind the
  debug assert for unsupported `InputDecoration` error slots. The assert now
  also rejects `errorText: ''`.

## [2.0.2] - 2026-10-13

### Fixed

- Flutter requirement is `>=3.38.1` (down from an effective 3.41.0 floor).

## [2.0.1] - 2026-10-13

### Fixed

- Quickly switching between scoped cells no longer disposes the previous
  `TextEditingController` while the IME can still update it.

## [2.0.0] - 2026-10-13

Breaking rewrite around native Material decoration. Not previously published
to pub.dev (latest published was 1.0.3).

### Added

- Native `InputDecoration` support, including labels, helper/error/counter
  content, prefix/suffix widgets, density, constraints, and Material themes.
- A persistent native `InputDecorator` across read-only and editing modes so
  the lightweight text child can be swapped for a real `TextField` without
  remounting the decorator.
- Per-cell viewport layout caching for repeated intrinsic and layout queries.
- Fixed-height sizing without text measurement when `minHeight` and
  `maxHeight` are the same finite value.
- `textAlignVertical` and `buildCounter` support on `LazyTextField`.
- Wrapper passthroughs: `inputFormatters`, `onChanged`, `keyboardType`,
  `textInputAction`, and `maxLength`.
- `errorMessage` for layout-stable validation feedback (overlay popup). Prefer
  this over `InputDecoration.errorText`.
- Edit-session epoch / in-flight save guards; scoped dispose / `cellId`
  handling; `TextFieldTapRegion` around decorated editors.
- Documentation for the no-jump decoration contract, fixed-slot visibility,
  overlay fallbacks, and validation via `errorMessage` + `onSave`.

### Changed

- Static and editing modes now share native decoration geometry while the
  lightweight text child is replaced by the real `TextField`.
- `minHeight` and `maxHeight` now constrain the **text viewport**; native
  supporting content (helper/error/counter) remains outside those bounds.
- Full decorated height is measured by Flutter layout. Synchronous helpers
  (`LazyTextField.computeHeightForWidth`, `LazyTextFieldMetrics`,
  `LazyTextFieldLayout`) remain exact for the undecorated text viewport only.
- Wrappers (`StatefulLazyTextField`, `ScopedLazyTextField`) take
  `InputDecoration` instead of `LazyInputDecoration`.
- Prefer `InputDecoration.prefixIcon` / `suffixIcon` for field chrome;
  `reservedTrailingWidth` is for app-owned overlays outside the decorator.
- `singleLine` rejects newlines; overflow accounts for scrollbar gutter;
  overflow marker supports RTL + semantics; `tapPosition` honors `textAlign`.
- Minimum Flutter SDK raised to `>=3.38.1`.

### Removed

- `LazyInputDecoration` and `LazyInputDecorationVisibility`.
- The widget-level `padding` parameter. Use
  `InputDecoration.contentPadding`.

### Migration

- Replace `LazyInputDecoration(...)` with `InputDecoration(...)`.
- Move `padding:` to `decoration: InputDecoration(contentPadding: ...)`.
- Keep decoration layout-equivalent across the read-only → edit switch
  (do not add/remove/resize helper, error, icons, or padding when editing
  starts). Reserve stable slots or use overlays for edit-only controls.
- Do not use `InputDecoration.errorText` for validation; use `errorMessage`
  and keep `onSave` as the commit gate.
- If you sized rows with `computeHeightForWidth`, that value is still the
  text-viewport height; add decorator chrome separately or let Flutter lay
  out the full field.

## [1.0.3] - 2026-07-28

### Added

- Public dartdoc coverage for the exported API surface.
- Small default example app while keeping the full browser demo available as
  `example/lib/main_live_demo.dart`.

### Changed

- Moved live-demo guidance before installation in the README and clarified that
  the full demo mounts only one real `TextField` / `EditableText` at a time.
- Updated the GitHub Pages workflow to build the full live demo entrypoint.

## [1.0.2] - 2026-07-28

### Added

- Regression test coverage for stopping edit mode from an outside tap.

### Changed

- Excluded generated `build/` and `coverage/` outputs from the published
  package archive.

## [1.0.1] - 2026-07-24

### Added

- `LazyTextField.overflowMarkerBuilder` and
  `LazyTextField.defaultOverflowMarkerBuilder` for customizing or hiding the
  read-only overflow marker.
- `LazyTextFieldOverflowMarkerDetails` for marker builder state.
- `scrollbarThickness` and `scrollbarAlignment` for customizing the bounded
  edit-mode scrollbar.
- `startEditSelection` for choosing beginning, end, clicked text position, or
  full-text selection when editing starts.

### Removed

- `LazyTextField.onCalendarPressed` and the built-in calendar trailing button.
  Use `LazyInputDecoration.suffixIcon` instead.
- Deprecated `LazyTextEditField`, `LazyTextEditKeys`, and `LazyTextEditLayout`
  typedef shims. Use `LazyTextField`, `LazyTextFieldKeys`, and
  `LazyTextFieldLayout`.

### Changed

- Clarified that `reservedTrailingWidth` is for extra non-decoration chrome;
  prefix/suffix icons should use `LazyInputDecoration` icon slots.

### Fixed

- Hard-to-find soft-wrap drift between static and edit modes when
  `maxHeight` / scrollbar gutter reservations differed across the switch
  (notably example `onEditFull`). Viewport width and wrap breaks are now
  covered by regression tests for font sizes 10-16.

## [1.0.0] - 2026-07-23

### Added

- Initial pub.dev release.
- `LazyTextField` for lazy read-only rendering with on-demand edit resources.
- `StatefulLazyTextField` for single-cell local edit lifecycle.
- `LazyTextFieldControllerScope`, `ScopedLazyTextField`, and
  `LazyTextFieldEditController` for shared multi-cell edit management.
- `LazyInputDecoration` for height-neutral field chrome outside the internal
  `TextField`.
- `LazyTextFieldLayout`, `LazyTextFieldMetrics`, and
  `LazyTextField.computeHeightForWidth` for exact constrained-width row height
  calculation.
- Visual example app under `example/`.

[Unreleased]: https://github.com/Alexqwesa/lazy_text_field/compare/v2.0.2...HEAD
[2.0.2]: https://github.com/Alexqwesa/lazy_text_field/compare/v2.0.1...v2.0.2
[2.0.1]: https://github.com/Alexqwesa/lazy_text_field/compare/v2.0.0...v2.0.1
[2.0.0]: https://github.com/Alexqwesa/lazy_text_field/compare/v1.0.3...v2.0.0
[1.0.3]: https://github.com/Alexqwesa/lazy_text_field/compare/v1.0.2...v1.0.3
[1.0.2]: https://github.com/Alexqwesa/lazy_text_field/compare/v1.0.1...v1.0.2
[1.0.1]: https://github.com/Alexqwesa/lazy_text_field/compare/v1.0.0...v1.0.1
[1.0.0]: https://github.com/Alexqwesa/lazy_text_field/releases/tag/v1.0.0
