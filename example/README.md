# lazy_text_field_example

Runnable examples for `lazy_text_field`.

Small example with one `StatefulLazyTextField`:

```sh
cd example
flutter run -d chrome
```

The full browser demo used by GitHub Pages (table layout, heights, edit
selection, styles):

```sh
flutter run -d chrome -t lib/main_live_demo.dart
```

Saving demo: `ScopedLazyTextField` cells in a `ListView` that unmounts them,
saved to a mock API. Switches cover the failing calls (none, all, every
second), latency, `onCommit` / `onSave`, `closeOnSubmit`, `switchPolicy`,
`saveMode`, `saveOrder`, and a draft store. It also has "Save all" (one save
per cell or one batch request), reload, and restart, plus a status bar with
draft counts and an event log:

```sh
flutter run -d chrome -t lib/main_saving_demo.dart
```
