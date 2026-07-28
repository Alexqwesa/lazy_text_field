import 'package:flutter/material.dart';

/// Controls when [LazyInputDecoration] chrome is painted.
enum LazyInputDecorationVisibility {
  /// Never paint decoration chrome.
  never,

  /// Paint decoration chrome only while the cell is editing.
  editing,

  /// Paint decoration chrome in both read-only and edit modes.
  always,
}

/// Height-neutral field chrome drawn outside the internal [TextField].
///
/// [LazyTextField] always passes `decoration: null` to its [TextField].
/// Padding comes only from [LazyTextField.padding], not from this decoration.
class LazyInputDecoration {
  /// Creates height-neutral decoration chrome for a lazy text field.
  const LazyInputDecoration({
    this.filled,
    this.fillColor,
    this.focusColor,
    this.hoverColor,
    this.border,
    this.enabledBorder,
    this.focusedBorder,
    this.errorBorder,
    this.focusedErrorBorder,
    this.disabledBorder,
    this.hintText,
    this.hintStyle,
    this.prefixIcon,
    this.suffixIcon,
    this.prefixIconConstraints,
    this.suffixIconConstraints,
    this.enabled = true,
    this.errorText,
  });

  /// Whether the field background should be filled.
  final bool? filled;

  /// Fill color used when [filled] is true.
  final Color? fillColor;

  /// Color used for focused decoration state where applicable.
  final Color? focusColor;

  /// Color used for hovered decoration state where applicable.
  final Color? hoverColor;

  /// Base border used when a more specific border is not provided.
  final InputBorder? border;

  /// Border used while the field is enabled and not focused.
  final InputBorder? enabledBorder;

  /// Border used while the field is focused.
  final InputBorder? focusedBorder;

  /// Border used while [errorText] is non-null and the field is not focused.
  final InputBorder? errorBorder;

  /// Border used while [errorText] is non-null and the field is focused.
  final InputBorder? focusedErrorBorder;

  /// Border used while [enabled] is false.
  final InputBorder? disabledBorder;

  /// Placeholder text shown when the field text is empty.
  final String? hintText;

  /// Style used for [hintText].
  final TextStyle? hintStyle;

  /// Widget reserved and painted before the editable text.
  final Widget? prefixIcon;

  /// Widget reserved and painted after the editable text.
  final Widget? suffixIcon;

  /// Layout constraints for [prefixIcon].
  final BoxConstraints? prefixIconConstraints;

  /// Layout constraints for [suffixIcon].
  final BoxConstraints? suffixIconConstraints;

  /// Whether the decoration should use enabled or disabled visual state.
  final bool enabled;

  /// Error text used to select error border state.
  final String? errorText;

  /// Whether this decoration is currently in an error state.
  bool get hasError => errorText != null;

  /// Whether a prefix icon slot is present.
  bool get hasPrefixIcon => prefixIcon != null;

  /// Whether a suffix icon slot is present.
  bool get hasSuffixIcon => suffixIcon != null;
}
