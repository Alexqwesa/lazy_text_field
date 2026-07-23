import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Canonical row-height engine shared by [LazyTextField] and
/// [LazyTextFieldMetrics].
class LazyTextFieldLayout {
  const LazyTextFieldLayout({
    required this.height,
    required this.contentHeight,
    required this.textViewportWidth,
    required this.textLayoutWidth,
    required this.hasVerticalOverflow,
    required this.reservedScrollbarWidth,
  });

  final double height;
  final double contentHeight;
  final double textViewportWidth;
  final double textLayoutWidth;
  final bool hasVerticalOverflow;
  final double reservedScrollbarWidth;

  static String measureText(String text) {
    if (text.isEmpty) {
      return '\u200B';
    }
    if (text.endsWith('\n')) {
      return '$text\u200B';
    }
    return text;
  }

  static double paintedTextHeight({
    required String text,
    required TextStyle style,
    required double width,
    required bool singleLine,
    TextDirection textDirection = TextDirection.ltr,
    TextScaler textScaler = TextScaler.noScaling,
    StrutStyle? strutStyle,
  }) {
    final painter = TextPainter(
      text: TextSpan(text: measureText(text), style: style),
      textDirection: textDirection,
      textScaler: textScaler,
      strutStyle: strutStyle ?? StrutStyle.fromTextStyle(style),
      maxLines: singleLine ? 1 : null,
      ellipsis: singleLine ? '\u2026' : null,
    )..layout(maxWidth: math.max<double>(0, width));

    return painter.height;
  }

  static LazyTextFieldLayout compute({
    required String text,
    required double width,
    required EdgeInsetsGeometry padding,
    required bool singleLine,
    TextStyle? style,
    TextDirection textDirection = TextDirection.ltr,
    TextScaler textScaler = TextScaler.noScaling,
    StrutStyle? strutStyle,
    double minHeight = 0,
    double reservedLeadingWidth = 0,
    double reservedTrailingWidth = 0,
    double? maxHeight,
    double scrollbarGutter = 0,
    double editableTextGutter = 3,
  }) {
    final resolvedPadding = padding.resolve(textDirection);
    final resolvedStyle = style ?? const TextStyle();
    final effectiveMaxHeight = maxHeight;
    final bounded = effectiveMaxHeight != null && effectiveMaxHeight.isFinite;
    final reservedScrollbarWidth = bounded ? scrollbarGutter : 0.0;
    final horizontalPadding = math.max<double>(
      0,
      resolvedPadding.horizontal -
          (reservedScrollbarWidth > 0 ? resolvedPadding.right : 0),
    );

    final fullTextWidth = math.max<double>(
      0,
      width - horizontalPadding - reservedLeadingWidth - reservedTrailingWidth,
    );
    final fullTextLayoutWidth = math.max<double>(
      0,
      fullTextWidth - editableTextGutter,
    );

    var textHeight = paintedTextHeight(
      text: text,
      style: resolvedStyle,
      width: fullTextLayoutWidth,
      singleLine: singleLine,
      textDirection: textDirection,
      textScaler: textScaler,
      strutStyle: strutStyle,
    );

    var naturalHeight = math
        .max(minHeight, textHeight + resolvedPadding.vertical)
        .ceilToDouble();

    final hasVerticalOverflow = bounded && naturalHeight > effectiveMaxHeight;
    final textViewportWidth = math.max<double>(
      0,
      fullTextWidth - reservedScrollbarWidth,
    );
    final textLayoutWidth = math.max<double>(
      0,
      textViewportWidth - editableTextGutter,
    );

    if (reservedScrollbarWidth > 0) {
      textHeight = paintedTextHeight(
        text: text,
        style: resolvedStyle,
        width: textLayoutWidth,
        singleLine: singleLine,
        textDirection: textDirection,
        textScaler: textScaler,
        strutStyle: strutStyle,
      );
      naturalHeight = math
          .max(minHeight, textHeight + resolvedPadding.vertical)
          .ceilToDouble();
    }

    final height = effectiveMaxHeight != null && effectiveMaxHeight.isFinite
        ? math.min(naturalHeight, effectiveMaxHeight).ceilToDouble()
        : naturalHeight;

    return LazyTextFieldLayout(
      height: height,
      contentHeight: height,
      textViewportWidth: textViewportWidth,
      textLayoutWidth: textLayoutWidth,
      hasVerticalOverflow: hasVerticalOverflow,
      reservedScrollbarWidth: reservedScrollbarWidth,
    );
  }

  static LazyTextFieldLayout computeFromContext(
    BuildContext context, {
    required String text,
    required double width,
    required EdgeInsetsGeometry padding,
    required bool singleLine,
    TextStyle? style,
    StrutStyle? strutStyle,
    double minHeight = 0,
    double reservedLeadingWidth = 0,
    double reservedTrailingWidth = 0,
    double? maxHeight,
    double scrollbarGutter = 0,
    double editableTextGutter = 3,
  }) {
    return compute(
      text: text,
      width: width,
      padding: padding,
      singleLine: singleLine,
      style: DefaultTextStyle.of(context).style.merge(style),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      strutStyle: strutStyle,
      minHeight: minHeight,
      reservedLeadingWidth: reservedLeadingWidth,
      reservedTrailingWidth: reservedTrailingWidth,
      maxHeight: maxHeight,
      scrollbarGutter: scrollbarGutter,
      editableTextGutter: editableTextGutter,
    );
  }
}
