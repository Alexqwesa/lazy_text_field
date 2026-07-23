import 'package:flutter/material.dart';
import 'package:lazy_text_field/src/lazy_text_field_layout.dart';

/// Default content padding used by [LazyTextField].
const EdgeInsets kDefaultLazyTextFieldPadding = EdgeInsets.symmetric(
  horizontal: 8,
  vertical: 6,
);

/// Computes exact constrained-width surface heights for [LazyTextField].
class LazyTextFieldMetrics {
  const LazyTextFieldMetrics._();

  /// Returns the [LazyTextField] surface height for a given [width].
  ///
  /// Pass [context] to inherit [DefaultTextStyle], text direction, and text
  /// scaler from the widget tree. Omit [context] when measuring outside build,
  /// for example while sizing data-table rows.
  static double computeHeightForWidth({
    BuildContext? context,
    required String text,
    required double width,
    TextStyle? style,
    StrutStyle? strutStyle,
    EdgeInsetsGeometry padding = kDefaultLazyTextFieldPadding,
    bool singleLine = false,
    TextDirection? textDirection,
    TextScaler? textScaler,
    double minHeight = 0,
    double reservedLeadingWidth = 0,
    double reservedTrailingWidth = 0,
    double? maxHeight,
    double scrollbarGutter = 12,
    double cursorWidth = 2,
  }) {
    if (context != null) {
      final resolvedStyle = style == null
          ? DefaultTextStyle.of(context).style
          : DefaultTextStyle.of(context).style.merge(style);
      return LazyTextFieldLayout.computeFromContext(
        context,
        text: text,
        width: width,
        padding: padding,
        singleLine: singleLine,
        style: resolvedStyle,
        strutStyle: strutStyle,
        minHeight: minHeight,
        reservedLeadingWidth: reservedLeadingWidth,
        reservedTrailingWidth: reservedTrailingWidth,
        maxHeight: maxHeight,
        scrollbarGutter: scrollbarGutter,
        editableTextGutter: _editableTextGutter(cursorWidth),
      ).height;
    }

    return LazyTextFieldLayout.compute(
      text: text,
      width: width,
      padding: padding,
      singleLine: singleLine,
      style: style,
      strutStyle: strutStyle,
      textDirection: textDirection ?? TextDirection.ltr,
      textScaler: textScaler ?? TextScaler.noScaling,
      minHeight: minHeight,
      reservedLeadingWidth: reservedLeadingWidth,
      reservedTrailingWidth: reservedTrailingWidth,
      maxHeight: maxHeight,
      scrollbarGutter: scrollbarGutter,
      editableTextGutter: _editableTextGutter(cursorWidth),
    ).height;
  }
}

double _editableTextGutter(double cursorWidth) {
  return cursorWidth + 1;
}
