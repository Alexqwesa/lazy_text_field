import 'package:flutter/material.dart';

/// Controls when [LazyInputDecoration] chrome is painted.
enum LazyInputDecorationVisibility { never, editing, always }

/// Height-neutral field chrome drawn outside the internal [TextField].
///
/// [LazyTextField] always passes `decoration: null` to its [TextField].
/// Padding comes only from [LazyTextField.padding], not from this decoration.
class LazyInputDecoration {
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

  final bool? filled;
  final Color? fillColor;
  final Color? focusColor;
  final Color? hoverColor;
  final InputBorder? border;
  final InputBorder? enabledBorder;
  final InputBorder? focusedBorder;
  final InputBorder? errorBorder;
  final InputBorder? focusedErrorBorder;
  final InputBorder? disabledBorder;
  final String? hintText;
  final TextStyle? hintStyle;
  final Widget? prefixIcon;
  final Widget? suffixIcon;
  final BoxConstraints? prefixIconConstraints;
  final BoxConstraints? suffixIconConstraints;
  final bool enabled;
  final String? errorText;

  bool get hasError => errorText != null;

  bool get hasPrefixIcon => prefixIcon != null;

  bool get hasSuffixIcon => suffixIcon != null;
}
