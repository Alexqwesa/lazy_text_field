# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [2.0.0] - 2026-10-13

### Added

- Native `InputDecoration` support, including labels, helper/error/counter
  content, prefix/suffix widgets, density, constraints, and Material themes.
- A persistent native `InputDecorator` across read-only and editing modes.
- Per-cell viewport layout caching for repeated intrinsic and layout queries.
- Fixed-height sizing without text measurement when `minHeight` and
  `maxHeight` are the same finite value.
- `textAlignVertical` and `buildCounter` support on `LazyTextField`.
- Documentation for fixed-slot visibility and overlay fallbacks.

### Changed

- Static and editing modes now share native decoration geometry while the
  lightweight text child is replaced by the real `TextField`.
- `minHeight` and `maxHeight` now constrain the text viewport; native
  supporting content remains outside those bounds.
- Full decorated height is measured by Flutter layout. Synchronous metrics
  remain exact for the undecorated text viewport.

### Removed

- `LazyInputDecoration` and `LazyInputDecorationVisibility`.
- The widget-level `padding` parameter. Use
  `InputDecoration.contentPadding`.

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

[Unreleased]: https://github.com/Alexqwesa/lazy_text_field/compare/v2.0.0...HEAD
[2.0.0]: https://github.com/Alexqwesa/lazy_text_field/compare/v1.0.3...v2.0.0
[1.0.3]: https://github.com/Alexqwesa/lazy_text_field/compare/v1.0.2...v1.0.3
[1.0.2]: https://github.com/Alexqwesa/lazy_text_field/compare/v1.0.1...v1.0.2
[1.0.1]: https://github.com/Alexqwesa/lazy_text_field/compare/v1.0.0...v1.0.1
[1.0.0]: https://github.com/Alexqwesa/lazy_text_field/releases/tag/v1.0.0
