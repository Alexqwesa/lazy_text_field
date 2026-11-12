# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
