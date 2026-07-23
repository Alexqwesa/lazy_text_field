# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.1] - 2026-07-23

### Added

- `LazyTextField.overflowMarkerBuilder` and
  `LazyTextField.defaultOverflowMarkerBuilder` for customizing or hiding the
  read-only overflow marker.
- `LazyTextFieldOverflowMarkerDetails` for marker builder state.
- `scrollbarThickness` and `scrollbarAlignment` for customizing the bounded
  edit-mode scrollbar.
- `startEditSelection` for choosing beginning, end, clicked text position, or
  full-text selection when editing starts.

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

[Unreleased]: https://github.com/Alexqwesa/lazy_text_field/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/Alexqwesa/lazy_text_field/releases/tag/v1.0.0
