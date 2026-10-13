import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lazy_text_field/lazy_text_field.dart';

/// Combinatorial layout invariants for [LazyTextFieldLayout].
///
/// Kept separate from pixel-geometry tests in `lazy_text_edit_field_test.dart`,
/// which assert exact placements rather than broad overflow/dimension rules.
void main() {
  const fontFamily = 'Ahem';

  final widths = <double>[40, 80, 120, 200];
  final paddings = <EdgeInsets>[
    EdgeInsets.zero,
    const EdgeInsets.all(4),
    const EdgeInsets.fromLTRB(3, 4, 5, 6),
  ];
  final fontSizes = <double>[8, 10, 14];
  final lineCounts = <int>[1, 3, 6];
  final gutters = <double>[0, 8, 12];
  final minHeights = <double>[0, 20, 40];
  final maxHeights = <double?>[null, 20, 40, 80];

  String textForLines(int lineCount) {
    // Hard newlines keep line count stable across widths; wrapping words still
    // exercise gutter remasurement when maxHeight is bounded.
    final lines = List<String>.generate(
      lineCount,
      (i) => 'line$i word word word',
    );
    return lines.join('\n');
  }

  TextStyle styleFor(double fontSize) {
    return TextStyle(
      fontFamily: fontFamily,
      fontSize: fontSize,
      height: 1,
      letterSpacing: 0,
    );
  }

  double naturalHeightAt({
    required String text,
    required TextStyle style,
    required double textLayoutWidth,
    required EdgeInsets padding,
    required double minHeight,
    required bool singleLine,
    TextDirection textDirection = TextDirection.ltr,
    TextScaler textScaler = TextScaler.noScaling,
  }) {
    final textHeight = LazyTextFieldLayout.paintedTextHeight(
      text: text,
      style: style,
      width: textLayoutWidth,
      singleLine: singleLine,
      textDirection: textDirection,
      textScaler: textScaler,
    );
    return math.max(minHeight, textHeight + padding.vertical).ceilToDouble();
  }

  test('overflow matches natural height at the final reserved text width', () {
    var cases = 0;
    for (final width in widths) {
      for (final padding in paddings) {
        for (final fontSize in fontSizes) {
          for (final lineCount in lineCounts) {
            for (final gutter in gutters) {
              for (final minHeight in minHeights) {
                for (final maxHeight in maxHeights) {
                  final text = textForLines(lineCount);
                  final style = styleFor(fontSize);
                  final layout = LazyTextFieldLayout.compute(
                    text: text,
                    width: width,
                    padding: padding,
                    singleLine: false,
                    style: style,
                    minHeight: minHeight,
                    maxHeight: maxHeight,
                    scrollbarGutter: gutter,
                  );

                  final expectedNatural = naturalHeightAt(
                    text: text,
                    style: style,
                    textLayoutWidth: layout.textLayoutWidth,
                    padding: padding,
                    minHeight: minHeight,
                    singleLine: false,
                  );
                  final bounded = maxHeight != null && maxHeight.isFinite;
                  final expectedOverflow =
                      bounded && expectedNatural > maxHeight;

                  expect(
                    layout.hasVerticalOverflow,
                    expectedOverflow,
                    reason:
                        'width=$width padding=$padding fontSize=$fontSize '
                        'lines=$lineCount gutter=$gutter min=$minHeight '
                        'max=$maxHeight natural=$expectedNatural '
                        'layoutW=${layout.textLayoutWidth} '
                        'reserved=${layout.reservedScrollbarWidth}',
                  );
                  if (bounded) {
                    expect(layout.height, lessThanOrEqualTo(maxHeight));
                    expect(layout.reservedScrollbarWidth, gutter);
                  } else {
                    expect(layout.reservedScrollbarWidth, 0);
                    expect(layout.height, expectedNatural);
                  }
                  cases++;
                }
              }
            }
          }
        }
      }
    }
    expect(cases, greaterThan(1000));
  });

  test('viewport and layout widths are never negative', () {
    for (final width in <double>[0, 1, 8, 40, 120]) {
      for (final padding in paddings) {
        for (final gutter in gutters) {
          for (final leading in <double>[0, 16, 32]) {
            for (final trailing in <double>[0, 16, 32]) {
              final layout = LazyTextFieldLayout.compute(
                text: textForLines(3),
                width: width,
                padding: padding,
                singleLine: false,
                style: styleFor(10),
                maxHeight: 40,
                scrollbarGutter: gutter,
                reservedLeadingWidth: leading,
                reservedTrailingWidth: trailing,
              );
              expect(layout.textViewportWidth, greaterThanOrEqualTo(0));
              expect(layout.textLayoutWidth, greaterThanOrEqualTo(0));
              expect(layout.height, greaterThanOrEqualTo(0));
              expect(layout.reservedScrollbarWidth, greaterThanOrEqualTo(0));
              expect(
                layout.textLayoutWidth,
                lessThanOrEqualTo(layout.textViewportWidth),
              );
            }
          }
        }
      }
    }
  });

  test(
    'layout-equivalent reserved decoration slots match a narrowed width',
    () {
      for (final width in <double>[100, 160, 220]) {
        for (final padding in paddings) {
          for (final gutter in gutters) {
            for (final slot in <double>[12, 24, 32]) {
              for (final maxHeight in <double?>[null, 48]) {
                final style = styleFor(10);
                final text = textForLines(4);

                final withLeading = LazyTextFieldLayout.compute(
                  text: text,
                  width: width,
                  padding: padding,
                  singleLine: false,
                  style: style,
                  maxHeight: maxHeight,
                  scrollbarGutter: gutter,
                  reservedLeadingWidth: slot,
                );
                final narrowedForLeading = LazyTextFieldLayout.compute(
                  text: text,
                  width: width - slot,
                  padding: padding,
                  singleLine: false,
                  style: style,
                  maxHeight: maxHeight,
                  scrollbarGutter: gutter,
                );
                expect(
                  withLeading.textViewportWidth,
                  narrowedForLeading.textViewportWidth,
                  reason: 'leading slot $slot at width $width',
                );
                expect(
                  withLeading.textLayoutWidth,
                  narrowedForLeading.textLayoutWidth,
                );
                expect(
                  withLeading.hasVerticalOverflow,
                  narrowedForLeading.hasVerticalOverflow,
                );

                final withTrailing = LazyTextFieldLayout.compute(
                  text: text,
                  width: width,
                  padding: padding,
                  singleLine: false,
                  style: style,
                  maxHeight: maxHeight,
                  scrollbarGutter: gutter,
                  reservedTrailingWidth: slot,
                );
                final narrowedForTrailing = LazyTextFieldLayout.compute(
                  text: text,
                  width: width - slot,
                  padding: padding,
                  singleLine: false,
                  style: style,
                  maxHeight: maxHeight,
                  scrollbarGutter: gutter,
                );
                expect(
                  withTrailing.textViewportWidth,
                  narrowedForTrailing.textViewportWidth,
                  reason: 'trailing slot $slot at width $width',
                );
                expect(
                  withTrailing.hasVerticalOverflow,
                  narrowedForTrailing.hasVerticalOverflow,
                );
              }
            }
          }
        }
      }
    },
  );

  test('natural text height is monotonic as available width decreases', () {
    const padding = EdgeInsets.fromLTRB(3, 4, 5, 6);
    final style = styleFor(10);
    const text = 'word word word word word word word word word word word word';
    final sampleWidths = <double>[200, 160, 120, 90, 60, 40, 20];

    var previousHeight = -1.0;
    for (final width in sampleWidths) {
      final layout = LazyTextFieldLayout.compute(
        text: text,
        width: width,
        padding: padding,
        singleLine: false,
        style: style,
        maxHeight: null,
        scrollbarGutter: 12,
      );
      expect(layout.reservedScrollbarWidth, 0);
      final height = naturalHeightAt(
        text: text,
        style: style,
        textLayoutWidth: layout.textLayoutWidth,
        padding: padding,
        minHeight: 0,
        singleLine: false,
      );
      expect(layout.height, height);
      expect(
        height,
        greaterThanOrEqualTo(previousHeight),
        reason: 'width=$width height=$height previous=$previousHeight',
      );
      previousHeight = height;
    }
  });

  test('overflow agreement is stable under text scaling', () {
    for (final scale in <double>[0.85, 1.0, 1.25, 1.5, 2.0]) {
      for (final width in <double>[80, 120]) {
        for (final gutter in gutters) {
          for (final maxHeight in <double?>[null, 30, 60]) {
            final scaler = TextScaler.linear(scale);
            final style = styleFor(10);
            final text = textForLines(4);
            const padding = EdgeInsets.all(4);

            final layout = LazyTextFieldLayout.compute(
              text: text,
              width: width,
              padding: padding,
              singleLine: false,
              style: style,
              textScaler: scaler,
              maxHeight: maxHeight,
              scrollbarGutter: gutter,
            );
            final expectedNatural = naturalHeightAt(
              text: text,
              style: style,
              textLayoutWidth: layout.textLayoutWidth,
              padding: padding,
              minHeight: 0,
              singleLine: false,
              textScaler: scaler,
            );
            final bounded = maxHeight != null && maxHeight.isFinite;
            expect(
              layout.hasVerticalOverflow,
              bounded && expectedNatural > maxHeight,
              reason: 'scale=$scale width=$width gutter=$gutter max=$maxHeight',
            );
          }
        }
      }
    }
  });

  test('overflow agreement is stable under RTL padding resolution', () {
    const asymmetric = EdgeInsets.fromLTRB(2, 4, 18, 6);
    for (final direction in TextDirection.values) {
      for (final width in <double>[70, 110, 180]) {
        for (final gutter in gutters) {
          for (final maxHeight in <double?>[null, 36, 72]) {
            final style = styleFor(10);
            final text = textForLines(5);

            final layout = LazyTextFieldLayout.compute(
              text: text,
              width: width,
              padding: asymmetric,
              singleLine: false,
              style: style,
              textDirection: direction,
              maxHeight: maxHeight,
              scrollbarGutter: gutter,
            );
            final resolved = asymmetric.resolve(direction);
            final expectedNatural = naturalHeightAt(
              text: text,
              style: style,
              textLayoutWidth: layout.textLayoutWidth,
              padding: resolved,
              minHeight: 0,
              singleLine: false,
              textDirection: direction,
            );
            final bounded = maxHeight != null && maxHeight.isFinite;
            expect(
              layout.hasVerticalOverflow,
              bounded && expectedNatural > maxHeight,
              reason:
                  'dir=$direction width=$width gutter=$gutter max=$maxHeight',
            );
            expect(layout.textViewportWidth, greaterThanOrEqualTo(0));
            expect(layout.textLayoutWidth, greaterThanOrEqualTo(0));
          }
        }
      }
    }
  });

  test(
    'equal min/max height still reports overflow from reserved gutter wrap',
    () {
      // Fixed-row sizing still reserves the gutter when bounded; overflow must
      // reflect the remasured natural height, not the unguttered one.
      const text = 'aaaaa aaaaa aaaaa';
      const width = 64.0;
      const gutter = 20.0;
      final style = styleFor(10);
      const padding = EdgeInsets.fromLTRB(3, 4, 5, 6);

      final unguttered = LazyTextFieldLayout.compute(
        text: text,
        width: width,
        padding: padding,
        singleLine: false,
        style: style,
        maxHeight: null,
        scrollbarGutter: 0,
      );
      final fixed = unguttered.height;

      final layout = LazyTextFieldLayout.compute(
        text: text,
        width: width,
        padding: padding,
        singleLine: false,
        style: style,
        minHeight: fixed,
        maxHeight: fixed,
        scrollbarGutter: gutter,
      );

      final expectedNatural = naturalHeightAt(
        text: text,
        style: style,
        textLayoutWidth: layout.textLayoutWidth,
        padding: padding,
        minHeight: fixed,
        singleLine: false,
      );

      expect(layout.height, fixed);
      expect(layout.reservedScrollbarWidth, gutter);
      expect(layout.hasVerticalOverflow, expectedNatural > fixed);
    },
  );
}
