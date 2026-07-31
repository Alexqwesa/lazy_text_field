import 'package:flutter/material.dart';

/// Stable keys used by lazy text fields for tests and integrations.
final class LazyTextFieldKeys {
  const LazyTextFieldKeys._();

  /// Key for the root field surface.
  static Key root(String cellId) {
    return ValueKey('lazy-text-field.root.$cellId');
  }

  /// Key for the read-only tappable surface.
  static Key staticSurface(String cellId) {
    return ValueKey('lazy-text-field.static.$cellId');
  }

  /// Key for the editing surface containing the real [TextField].
  static Key editorSurface(String cellId) {
    return ValueKey('lazy-text-field.editor.$cellId');
  }

  /// Key for the measured text viewport.
  static Key textViewport(String cellId) {
    return ValueKey('lazy-text-field.text-viewport.$cellId');
  }

  /// Key for the package scrollbar painted in bounded edit mode.
  static Key scrollbar(String cellId) {
    return ValueKey('lazy-text-field.scrollbar.$cellId');
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
