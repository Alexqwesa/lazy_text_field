---
name: lazy-text-field-maintenance
description: Maintain or modify the lazy_text_field Flutter package. Use when changing LazyTextField internals, LazyInputDecoration rendering, lazy controller/focus allocation, exact height measurement, static/edit text alignment, tests, docs, or the visual example.
---

# Lazy Text Field Maintenance

## Package Boundary

Keep this package pure Flutter. Do not add Riverpod, intl, dashboard_tree, or
application-specific dependencies.

This package owns:

- `LazyTextField`, `StatefulLazyTextField`, `ScopedLazyTextField`
- `LazyInputDecoration`
- `LazyTextFieldLayout` and `LazyTextFieldMetrics`
- static/edit alignment tests and the visual example

Keep save policies, date parsing, permissions, persistence, and app-specific
selection behavior in wrapper/app packages.

## Lazy Rendering Rules

- Keep read-only mode lazy: do not allocate `TextEditingController`,
  `FocusNode`, or `ScrollController` before edit mode.
- Use a real `TextField` in edit mode, but always pass `decoration: null`.
- Draw `LazyInputDecoration` outside the `TextField`; do not use
  `InputDecorator` for `LazyTextField`.
- Keep `padding` as the single content-padding source. Decoration must not add
  layout padding.
- Preserve deprecated `LazyTextEditField`, `LazyTextEditLayout`, and
  `LazyTextEditKeys` shims unless the user explicitly requests a breaking
  cleanup.

## Height Measurement

- Treat `LazyTextFieldLayout.compute` as the canonical row-height engine.
- Measure with `TextPainter`, strut style, text scaler, direction, and the same
  effective text width used by the widget.
- Preserve zero-width-space handling for empty text and trailing newlines.
- Subtract reserved leading/trailing widths for prefix/suffix/other controls
  before measuring wrapping.
- Ceil final heights to avoid subpixel row drift.
- When changing text layout, compare static and edit mode positions, not only
  sizes.

## Decoration

`LazyInputDecoration` is intentionally a height-neutral subset of
`InputDecoration`. Support fill, hover/focus colors, enabled/focused/error/
disabled borders, hint text, and prefix/suffix icon slots. Do not add labels,
helper/error rows, counters, or floating labels without redesigning height
measurement and tests.

`LazyInputDecorationVisibility.editing` is the default. Icon slot widths are
reserved whenever decoration can affect layout, even when chrome is only painted
in edit mode.

## Testing

Run these after edits:

```sh
flutter analyze
flutter test
```

For example changes:

```sh
cd example
flutter analyze
flutter build web --debug
```

Keep tests focused on invariants:

- read-only cells allocate no edit resources
- static and edit root/viewport rects do not drift
- bounded height reserves scrollbar gutter consistently
- constrained-width height matches `TextPainter`
- punctuation and soft wrapping stay aligned across modes
- failure messages for position tests say whether a value jumped left, right,
  up, down, wider, narrower, taller, or shorter

Use the `+\n+++ +++ ++` fixture when checking fragile soft-wrap behavior: at a
narrow width, the second logical line must wrap onto a third visual line and
static/edit glyph positions must stay aligned.
