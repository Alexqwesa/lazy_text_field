import 'package:flutter/material.dart';

final class LazyTextFieldKeys {
  const LazyTextFieldKeys._();

  static Key root(String cellId) {
    return ValueKey('lazy-text-field.root.$cellId');
  }

  static Key staticSurface(String cellId) {
    return ValueKey('lazy-text-field.static.$cellId');
  }

  static Key editorSurface(String cellId) {
    return ValueKey('lazy-text-field.editor.$cellId');
  }

  static Key textViewport(String cellId) {
    return ValueKey('lazy-text-field.text-viewport.$cellId');
  }

  static Key scrollbar(String cellId) {
    return ValueKey('lazy-text-field.scrollbar.$cellId');
  }

  static Key prefixIcon(String cellId) {
    return ValueKey('lazy-text-field.prefix-icon.$cellId');
  }

  static Key suffixIcon(String cellId) {
    return ValueKey('lazy-text-field.suffix-icon.$cellId');
  }

  /// Legacy key kept for existing integration tests.
  static Key legacyReadOnlySurface(String cellId) {
    return ValueKey('read-only-surface-$cellId');
  }

  /// Legacy key kept for existing integration tests.
  static Key legacyEditorFrame(String cellId) {
    return ValueKey('editor-frame-$cellId');
  }
}
