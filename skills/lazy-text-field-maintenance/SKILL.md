---
name: lazy-text-field-maintenance
description: Maintain or modify the lazy_text_field Flutter package, including native InputDecoration layout, lazy edit allocation, viewport measurement, static/edit alignment, tests, docs, and examples.
---

# Lazy Text Field Maintenance

## Package Boundary

Keep this package pure Flutter and application-agnostic. It owns the lazy field
widgets, edit controller/scope, text viewport measurement, native decoration
integration, transition tests, and examples.

Drafts and the save queue live in `LazyTextFieldDraftQueue`
(`src/lazy_text_field_drafts.dart`). It is internal: the barrel exports that
file with `hide LazyTextFieldDraftQueue`, and `LazyTextFieldEditController`
forwards its public draft members to it. Keep queue logic there and
widget-free; test it in `test/lazy_text_field_draft_queue_test.dart`.

Every save must go through `_schedule` / `_chain` (lanes: the draft key, plus
the row or the whole queue), including `onSave` calls, so saves of one key
never overlap. Draft-store calls go through the single `_write` chain so a
`put` and a later `delete` cannot land out of order. Do not start a save or a
store call outside those chains.

Restored drafts are checked against their record in `displayText`, which runs
during build: the queue must not notify there (the controller notifies after
the frame). Every `displayText` call for a cell must pass that cell's
`version`; without it the check falls back to text and can flip a draft
between verified and conflict. Only `restored` drafts are checked; anything
that saves (`flushUnsaved`, `saveDrafts`, batches) must skip conflicts and
unverified drafts.

## Lazy Rendering Rules

- Do not allocate `TextEditingController`, `FocusNode`, `ScrollController`,
  `TextField`, or `EditableText` in read-only mode.
- Keep one native `InputDecorator` mounted in both modes when decoration is
  non-null.
- Pass `decoration: null` to the inner editing `TextField`.
- Swap only the lightweight static text child for the real editor.
- Use `InputDecoration.contentPadding`; do not add widget-level padding.
- Keep layout-affecting decoration structure stable across the switch.
- Use fixed slots or external overlays for edit-only controls.

## Height And Baseline

- Treat `LazyTextFieldLayout.compute` as the canonical text-viewport engine.
- Keep the viewport render object's per-width cache and invalidate it whenever
  text, style, strut, scale, direction, or sizing inputs change.
- Preserve zero-width-space handling for empty text and trailing newlines.
- Keep static and editor text widths equal, including the editable cursor
  gutter and reserved scrollbar/overlay widths.
- Report an alphabetic baseline from the viewport render object.
- Do not attempt synchronous full-height measurement of arbitrary decoration
  widgets.

## Testing

Run:

```sh
flutter analyze
flutter test --coverage
cd example
flutter analyze
flutter test
flutter build web --debug -t lib/main_live_demo.dart
```

Protect these invariants:

- no edit resources exist in read-only mode
- the same `InputDecorator` state survives the mode switch
- root, viewport, baseline, wrapping, and glyph positions do not jump
- native focus and floating-label transitions animate across frames
- fixed decoration slots remain stable
- bounded height reserves the scrollbar gutter consistently
- RTL, scaling, Material 2/3, overflow, selection, and context menus work
