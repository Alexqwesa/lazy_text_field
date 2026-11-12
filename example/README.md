# lazy_text_field_example

Runnable examples for `lazy_text_field`.

The default example: `ScopedLazyTextField` cells in a `ListView` that
unmounts them, saved to a mock API. It has switches for:

- the mock API: failing calls (none, all, every second) and latency
- the cells: `onCommit` / `onSave`, `closeOnSubmit`, note height (fixed,
  full, full while editing), `startEditSelection`, icons, font size, bold
  and italic
- the edit controller: `switchPolicy`, `saveMode`, `saveOrder`, and a draft
  store

It also has "Save all" (one save per cell or one batch request), reload,
and restart, plus a status bar with draft counts and an event log.

```sh
cd example
flutter run -d chrome
```

A single `StatefulLazyTextField`:

```sh
flutter run -d chrome -t lib/main_simple.dart
```

The basic demo, published on GitHub Pages under `/basic/`: `LazyTextField`
cells whose edit state the screen keeps itself, without a save controller:

```sh
flutter run -d chrome -t lib/main_live_demo.dart
```
