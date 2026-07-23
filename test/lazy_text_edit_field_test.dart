import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lazy_text_field/lazy_text_field.dart';

void main() {
  const cellId = 'cell-1';

  const textStyle = TextStyle(
    fontFamily: 'Ahem',
    fontSize: 10,
    height: 1,
    letterSpacing: 0,
  );

  const padding = EdgeInsets.fromLTRB(3, 4, 5, 6);
  const cellWidth = 120.0;
  const scrollbarGutter = 12.0;

  setUpAll(() async {
    final loader = FontLoader('LazyTextFieldNotoSans')
      ..addFont(rootBundle.load('test/fonts/NotoSans-Regular.ttf'));

    await loader.load();
  });

  test('deprecated lazy text edit names forward to lazy text field names', () {
    final layout = LazyTextEditLayout.compute(
      text: 'one',
      width: cellWidth,
      padding: padding,
      singleLine: false,
      style: textStyle,
    );
    final renamedLayout = LazyTextFieldLayout.compute(
      text: 'one',
      width: cellWidth,
      padding: padding,
      singleLine: false,
      style: textStyle,
    );

    expect(layout.height, renamedLayout.height);
    expect(LazyTextEditField, LazyTextField);
    expect(LazyTextEditKeys.root(cellId), LazyTextFieldKeys.root(cellId));
  });

  test('compute reserves scrollbar gutter when height is bounded', () {
    final layout = LazyTextEditLayout.compute(
      text: 'line 1\nline 2\nline 3\nline 4\nline 5\nline 6',
      width: cellWidth,
      padding: padding,
      singleLine: false,
      style: textStyle,
      maxHeight: 40,
      scrollbarGutter: scrollbarGutter,
    );

    expect(
      layout.textViewportWidth,
      cellWidth - padding.horizontal - scrollbarGutter,
    );
    expect(layout.hasVerticalOverflow, isTrue);
    expect(layout.height, 40);
  });

  testWidgets('height calculation is exact for explicit lines', (tester) async {
    late BuildContext capturedContext;

    await tester.pumpWidget(
      _TestApp(
        child: Builder(
          builder: (context) {
            capturedContext = context;
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    final layout = LazyTextEditField.measure(
      capturedContext,
      text: 'one\ntwo\nthree',
      width: cellWidth,
      style: textStyle,
      padding: padding,
      singleLine: false,
    );

    expect(layout.height, 40);
    expect(layout.contentHeight, 40);
    expect(layout.hasVerticalOverflow, isFalse);
    expect(layout.reservedScrollbarWidth, 0);
    expect(layout.textViewportWidth, cellWidth - padding.horizontal);
  });

  testWidgets('height calculation matches TextPainter wrapping', (
    tester,
  ) async {
    late BuildContext capturedContext;

    await tester.pumpWidget(
      _TestApp(
        child: Builder(
          builder: (context) {
            capturedContext = context;
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    const text = 'aaaa aaaa aaaa aaaa aaaa aaaa';

    final layout = LazyTextEditField.measure(
      capturedContext,
      text: text,
      width: 80,
      style: textStyle,
      padding: padding,
      singleLine: false,
    );

    final expectedTextHeight = _paintedTextHeight(
      context: capturedContext,
      text: text,
      style: textStyle,
      width: 80 - padding.horizontal,
      singleLine: false,
    );

    expect(layout.height, expectedTextHeight + padding.vertical);
    expect(layout.hasVerticalOverflow, isFalse);
  });

  testWidgets('empty text still reserves one editable line', (tester) async {
    late BuildContext capturedContext;

    await tester.pumpWidget(
      _TestApp(
        child: Builder(
          builder: (context) {
            capturedContext = context;
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    final layout = LazyTextEditField.measure(
      capturedContext,
      text: '',
      width: cellWidth,
      style: textStyle,
      padding: padding,
      singleLine: false,
    );

    expect(layout.height, 20);
    expect(layout.contentHeight, 20);
  });

  testWidgets('trailing newline is measured as an extra line', (tester) async {
    late BuildContext capturedContext;

    await tester.pumpWidget(
      _TestApp(
        child: Builder(
          builder: (context) {
            capturedContext = context;
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    final layout = LazyTextEditField.measure(
      capturedContext,
      text: 'one\n',
      width: cellWidth,
      style: textStyle,
      padding: padding,
      singleLine: false,
    );

    expect(layout.height, 30);
  });

  testWidgets('unbounded height: no scrollbar in static or edit mode', (
    tester,
  ) async {
    final controller = TextEditingController(
      text: 'line 1\nline 2\nline 3\nline 4\nline 5\nline 6',
    );
    final focusNode = FocusNode();

    addTearDown(controller.dispose);
    addTearDown(focusNode.dispose);

    await tester.pumpWidget(
      _TestApp(
        child: Column(
          children: [
            SizedBox(
              width: cellWidth,
              child: _LazyCellHarness(
                cellId: cellId,
                controller: controller,
                focusNode: focusNode,
                text: controller.text,
                style: textStyle,
                padding: padding,
                maxHeight: null,
                scrollbarGutter: scrollbarGutter,
              ),
            ),
          ],
        ),
      ),
    );

    expect(find.byKey(LazyTextEditKeys.scrollbar(cellId)), findsNothing);

    final staticRootRect = tester.getRect(
      find.byKey(LazyTextEditKeys.root(cellId)),
    );

    await tester.tap(find.byKey(LazyTextEditKeys.staticSurface(cellId)));
    await tester.pump();

    expect(find.byKey(LazyTextEditKeys.scrollbar(cellId)), findsNothing);

    final editRootRect = tester.getRect(
      find.byKey(LazyTextEditKeys.root(cellId)),
    );

    _expectRectClose(editRootRect, staticRootRect);

    expect(editRootRect.height, greaterThan(40));
  });

  testWidgets('edit mode builds TextField with null TextField decoration', (
    tester,
  ) async {
    final controller = TextEditingController(text: 'editable');
    final focusNode = FocusNode();

    addTearDown(controller.dispose);
    addTearDown(focusNode.dispose);

    await tester.pumpWidget(
      _TestApp(
        child: SizedBox(
          width: cellWidth,
          child: LazyTextField(
            cellId: cellId,
            text: controller.text,
            controller: controller,
            focusNode: focusNode,
            isEditing: true,
            style: textStyle,
            padding: padding,
            onStartEditing: () {},
          ),
        ),
      ),
    );

    final field = tester.widget<TextField>(find.byType(TextField));

    expect(field.decoration, isNull);
    expect(find.byType(EditableText), findsOneWidget);
  });

  testWidgets('bounded height: static mode reserves scrollbar gutter', (
    tester,
  ) async {
    final controller = TextEditingController(
      text: 'line 1\nline 2\nline 3\nline 4\nline 5\nline 6',
    );
    final focusNode = FocusNode();

    addTearDown(controller.dispose);
    addTearDown(focusNode.dispose);

    await tester.pumpWidget(
      _TestApp(
        child: SizedBox(
          width: cellWidth,
          height: 40,
          child: _LazyCellHarness(
            cellId: cellId,
            controller: controller,
            focusNode: focusNode,
            text: controller.text,
            style: textStyle,
            padding: padding,
            maxHeight: 40,
            scrollbarGutter: scrollbarGutter,
          ),
        ),
      ),
    );

    final staticViewportSize = tester.getSize(
      find.byKey(LazyTextEditKeys.textViewport(cellId)),
    );

    expect(find.byKey(LazyTextEditKeys.scrollbar(cellId)), findsNothing);
    expect(
      staticViewportSize.width,
      cellWidth - padding.horizontal - scrollbarGutter,
    );

    await tester.tap(find.byKey(LazyTextEditKeys.staticSurface(cellId)));
    await tester.pump();

    final editViewportSize = tester.getSize(
      find.byKey(LazyTextEditKeys.textViewport(cellId)),
    );

    expect(find.byKey(LazyTextEditKeys.scrollbar(cellId)), findsOneWidget);
    expect(editViewportSize.width, staticViewportSize.width);
  });

  testWidgets('overflow marker is larger and handles read-only toggle', (
    tester,
  ) async {
    var startEditCount = 0;
    var toggleCount = 0;

    await tester.pumpWidget(
      _TestApp(
        child: SizedBox(
          width: 80,
          child: LazyTextField(
            cellId: cellId,
            text: 'line 1\nline 2\nline 3\nline 4',
            isEditing: false,
            style: textStyle,
            padding: padding,
            maxHeight: 30,
            decoration: null,
            decorationVisibility: LazyInputDecorationVisibility.never,
            onStartEditing: () => startEditCount++,
            onReadOnlyOverflowToggle: () => toggleCount++,
          ),
        ),
      ),
    );

    final marker = find.byKey(const ValueKey('cell-overflow-corner-marker'));
    expect(marker, findsOneWidget);
    expect(tester.getSize(marker), const Size.square(14));

    await tester.tap(marker);
    await tester.pump();

    expect(toggleCount, 1);
    expect(
      startEditCount,
      0,
      reason: 'Tapping the overflow marker should not also start editing.',
    );
  });

  testWidgets('custom overflow marker builder replaces marker visual', (
    tester,
  ) async {
    var startEditCount = 0;
    var toggleCount = 0;
    LazyTextFieldOverflowMarkerDetails? capturedDetails;

    await tester.pumpWidget(
      _TestApp(
        child: SizedBox(
          width: 80,
          child: LazyTextField(
            cellId: cellId,
            text: 'line 1\nline 2\nline 3\nline 4',
            isEditing: false,
            style: textStyle,
            padding: padding,
            maxHeight: 30,
            decoration: null,
            decorationVisibility: LazyInputDecorationVisibility.never,
            overflowMarkerSize: 18,
            overflowMarkerColor: Colors.purple,
            overflowMarkerBuilder: (context, details) {
              capturedDetails = details;
              return const ColoredBox(
                key: ValueKey('custom-overflow-marker'),
                color: Colors.orange,
              );
            },
            onStartEditing: () => startEditCount++,
            onReadOnlyOverflowToggle: () => toggleCount++,
          ),
        ),
      ),
    );

    final marker = find.byKey(const ValueKey('cell-overflow-corner-marker'));
    expect(marker, findsOneWidget);
    expect(
      find.byKey(const ValueKey('custom-overflow-marker')),
      findsOneWidget,
    );
    expect(tester.getSize(marker), const Size.square(18));
    expect(capturedDetails?.size, 18);
    expect(capturedDetails?.color, Colors.purple);
    expect(capturedDetails?.expanded, isFalse);
    expect(capturedDetails?.hasHiddenText, isTrue);
    expect(capturedDetails?.onToggle, isNotNull);

    await tester.tap(marker);
    await tester.pump();

    expect(toggleCount, 1);
    expect(
      startEditCount,
      0,
      reason: 'Tapping a custom overflow marker should not start editing.',
    );
  });

  testWidgets('null overflow marker builder hides marker but keeps tooltip', (
    tester,
  ) async {
    await tester.pumpWidget(
      _TestApp(
        child: SizedBox(
          width: 80,
          child: LazyTextField(
            cellId: cellId,
            text: 'line 1\nline 2\nline 3\nline 4',
            isEditing: false,
            style: textStyle,
            padding: padding,
            maxHeight: 30,
            decoration: null,
            decorationVisibility: LazyInputDecorationVisibility.never,
            overflowMarkerBuilder: null,
            onReadOnlyOverflowToggle: () {},
            onStartEditing: () {},
          ),
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey('cell-overflow-corner-marker')),
      findsNothing,
    );

    final tooltip = tester.widget<Tooltip>(find.byType(Tooltip));
    expect(tooltip.ignorePointer, isTrue);
  });

  testWidgets('expanded overflow marker remains visible without overflow', (
    tester,
  ) async {
    await tester.pumpWidget(
      _TestApp(
        child: SizedBox(
          width: 80,
          child: LazyTextField(
            cellId: cellId,
            text: 'short',
            isEditing: false,
            style: textStyle,
            padding: padding,
            maxHeight: 80,
            decoration: null,
            decorationVisibility: LazyInputDecorationVisibility.never,
            readOnlyOverflowExpanded: true,
            onReadOnlyOverflowToggle: () {},
            onStartEditing: () {},
          ),
        ),
      ),
    );

    final marker = find.byKey(const ValueKey('cell-overflow-corner-marker'));
    expect(marker, findsOneWidget);

    final markerPaint = tester.widget<CustomPaint>(
      find.descendant(of: marker, matching: find.byType(CustomPaint)),
    );
    final markerPainter = markerPaint.painter! as dynamic;
    expect(markerPainter.outlined, isTrue);
  });

  testWidgets('custom overflow marker builder receives expanded state', (
    tester,
  ) async {
    LazyTextFieldOverflowMarkerDetails? capturedDetails;

    await tester.pumpWidget(
      _TestApp(
        child: SizedBox(
          width: 80,
          child: LazyTextField(
            cellId: cellId,
            text: 'short',
            isEditing: false,
            style: textStyle,
            padding: padding,
            maxHeight: 80,
            decoration: null,
            decorationVisibility: LazyInputDecorationVisibility.never,
            readOnlyOverflowExpanded: true,
            expandedOverflowMarkerColor: Colors.teal,
            overflowMarkerBuilder: (context, details) {
              capturedDetails = details;
              return const SizedBox.expand(
                key: ValueKey('expanded-custom-overflow-marker'),
              );
            },
            onReadOnlyOverflowToggle: () {},
            onStartEditing: () {},
          ),
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey('expanded-custom-overflow-marker')),
      findsOneWidget,
    );
    expect(capturedDetails?.expanded, isTrue);
    expect(capturedDetails?.hasHiddenText, isFalse);
    expect(capturedDetails?.color, Colors.teal);
  });

  testWidgets('overflow tooltip is transparent for pointer events', (
    tester,
  ) async {
    await tester.pumpWidget(
      _TestApp(
        child: SizedBox(
          width: 80,
          child: LazyTextField(
            cellId: cellId,
            text: 'line 1\nline 2\nline 3\nline 4',
            isEditing: false,
            style: textStyle,
            padding: padding,
            maxHeight: 30,
            decoration: null,
            decorationVisibility: LazyInputDecorationVisibility.never,
            onReadOnlyOverflowToggle: () {},
            onStartEditing: () {},
          ),
        ),
      ),
    );

    final tooltip = tester.widget<Tooltip>(find.byType(Tooltip));
    expect(tooltip.ignorePointer, isTrue);
  });

  testWidgets('mode switch does not change root rect', (tester) async {
    final controller = TextEditingController(
      text: 'alpha beta gamma delta epsilon',
    );
    final focusNode = FocusNode();

    addTearDown(controller.dispose);
    addTearDown(focusNode.dispose);

    await tester.pumpWidget(
      _TestApp(
        child: Column(
          children: [
            SizedBox(
              width: cellWidth,
              child: _LazyCellHarness(
                cellId: cellId,
                controller: controller,
                focusNode: focusNode,
                text: controller.text,
                style: textStyle,
                padding: padding,
                maxHeight: null,
                scrollbarGutter: scrollbarGutter,
              ),
            ),
          ],
        ),
      ),
    );

    final before = tester.getRect(find.byKey(LazyTextEditKeys.root(cellId)));

    await tester.tap(find.byKey(LazyTextEditKeys.staticSurface(cellId)));
    await tester.pump();

    final after = tester.getRect(find.byKey(LazyTextEditKeys.root(cellId)));

    _expectRectClose(after, before);
  });

  testWidgets('text viewport does not drift on mode switch', (tester) async {
    final controller = TextEditingController(
      text: 'alpha beta gamma delta epsilon',
    );
    final focusNode = FocusNode();

    addTearDown(controller.dispose);
    addTearDown(focusNode.dispose);

    await tester.pumpWidget(
      _TestApp(
        child: Column(
          children: [
            SizedBox(
              width: cellWidth,
              child: _LazyCellHarness(
                cellId: cellId,
                controller: controller,
                focusNode: focusNode,
                text: controller.text,
                style: textStyle,
                padding: padding,
                maxHeight: null,
                scrollbarGutter: scrollbarGutter,
              ),
            ),
          ],
        ),
      ),
    );

    final staticViewportRect = tester.getRect(
      find.byKey(LazyTextEditKeys.textViewport(cellId)),
    );

    await tester.tap(find.byKey(LazyTextEditKeys.staticSurface(cellId)));
    await tester.pump();

    final editViewportRect = tester.getRect(
      find.byKey(LazyTextEditKeys.textViewport(cellId)),
    );

    _expectRectClose(editViewportRect, staticViewportRect);

    final renderEditable = tester.renderObject<RenderEditable>(
      _findRenderEditableInside(cellId),
    );

    final caretRect = renderEditable.getLocalRectForCaret(
      const TextPosition(offset: 0),
    );

    final caretTopLeft = renderEditable.localToGlobal(caretRect.topLeft);

    expect(caretTopLeft.dx, closeTo(editViewportRect.left, 1));
    expect(caretTopLeft.dy, closeTo(editViewportRect.top, 1));
  });

  testWidgets('wrapped plus text keeps exact static and edit line positions', (
    tester,
  ) async {
    const plusText = '+\n+++ +++ ++';
    const plusCellWidth = 76.0;
    final controller = TextEditingController(text: plusText);
    final focusNode = FocusNode();

    addTearDown(controller.dispose);
    addTearDown(focusNode.dispose);

    await tester.pumpWidget(
      _TestApp(
        child: SizedBox(
          width: plusCellWidth,
          child: _LazyCellHarness(
            cellId: cellId,
            controller: controller,
            focusNode: focusNode,
            text: controller.text,
            style: textStyle,
            padding: padding,
            maxHeight: null,
            scrollbarGutter: scrollbarGutter,
          ),
        ),
      ),
    );

    final layout = LazyTextFieldLayout.compute(
      text: plusText,
      width: plusCellWidth,
      padding: padding,
      singleLine: false,
      style: textStyle,
    );

    expect(layout.height, 40);
    expect(layout.textViewportWidth, 68);

    final staticRootRect = tester.getRect(
      find.byKey(LazyTextFieldKeys.root(cellId)),
    );
    final staticViewportRect = tester.getRect(
      find.byKey(LazyTextFieldKeys.textViewport(cellId)),
    );

    _expectPointClose(
      staticViewportRect.topLeft,
      staticRootRect.topLeft + Offset(padding.left, padding.top),
      label: 'static text origin',
      tolerance: 0.01,
    );

    final expectedLineMetrics = _lineMetricsFor(
      text: plusText,
      style: textStyle,
      width: staticViewportRect.width,
    );
    expect(expectedLineMetrics, hasLength(3));

    final expectedFirstLineGlyph = _staticSelectionBoxTopLeft(
      text: plusText,
      selection: const TextSelection(baseOffset: 0, extentOffset: 1),
      style: textStyle,
      maxWidth: staticViewportRect.width,
      origin: staticViewportRect.topLeft,
    );
    final expectedSecondLineGlyph = _staticSelectionBoxTopLeft(
      text: plusText,
      selection: const TextSelection(baseOffset: 2, extentOffset: 5),
      style: textStyle,
      maxWidth: staticViewportRect.width,
      origin: staticViewportRect.topLeft,
    );
    final expectedThirdLineGlyph = _staticSelectionBoxTopLeft(
      text: plusText,
      selection: const TextSelection(baseOffset: 10, extentOffset: 12),
      style: textStyle,
      maxWidth: staticViewportRect.width,
      origin: staticViewportRect.topLeft,
    );

    await tester.tap(find.byKey(LazyTextFieldKeys.staticSurface(cellId)));
    await tester.pump();

    final editRootRect = tester.getRect(
      find.byKey(LazyTextFieldKeys.root(cellId)),
    );
    final editViewportRect = tester.getRect(
      find.byKey(LazyTextFieldKeys.textViewport(cellId)),
    );

    _expectRectClose(
      editRootRect,
      staticRootRect,
      label: 'plus root',
      tolerance: 0.01,
    );
    _expectRectClose(
      editViewportRect,
      staticViewportRect,
      label: 'plus text viewport',
      tolerance: 0.01,
    );

    final renderEditable = tester.renderObject<RenderEditable>(
      _findRenderEditableInside(cellId),
    );

    _expectSelectionBoxTopLeft(
      renderEditable,
      const TextSelection(baseOffset: 0, extentOffset: 1),
      expectedFirstLineGlyph,
      label: 'edit first line glyph',
      tolerance: 1,
    );
    _expectSelectionBoxTopLeft(
      renderEditable,
      const TextSelection(baseOffset: 2, extentOffset: 5),
      expectedSecondLineGlyph,
      label: 'edit second line glyph',
      tolerance: 1,
    );
    _expectSelectionBoxTopLeft(
      renderEditable,
      const TextSelection(baseOffset: 10, extentOffset: 12),
      expectedThirdLineGlyph,
      label: 'edit wrapped third line glyph',
      tolerance: 1,
    );
  });

  testWidgets('external controller update recalculates height in edit mode', (
    tester,
  ) async {
    final controller = TextEditingController(text: 'one');
    final focusNode = FocusNode();

    addTearDown(controller.dispose);
    addTearDown(focusNode.dispose);

    await tester.pumpWidget(
      _TestApp(
        child: Column(
          children: [
            SizedBox(
              width: cellWidth,
              child: _LazyCellHarness(
                cellId: cellId,
                controller: controller,
                focusNode: focusNode,
                text: controller.text,
                style: textStyle,
                padding: padding,
                maxHeight: null,
                scrollbarGutter: scrollbarGutter,
                initiallyEditing: true,
              ),
            ),
          ],
        ),
      ),
    );

    final oneLineHeight = tester
        .getSize(find.byKey(LazyTextEditKeys.root(cellId)))
        .height;

    controller.text = 'one\ntwo\nthree';
    await tester.pump();

    final threeLineHeight = tester
        .getSize(find.byKey(LazyTextEditKeys.root(cellId)))
        .height;

    expect(threeLineHeight, greaterThan(oneLineHeight));
    expect(threeLineHeight, 40);
  });

  testWidgets('RTL resolves padding and keeps viewport stable', (tester) async {
    final controller = TextEditingController(text: 'abc def ghi');
    final focusNode = FocusNode();

    addTearDown(controller.dispose);
    addTearDown(focusNode.dispose);

    await tester.pumpWidget(
      _TestApp(
        textDirection: TextDirection.rtl,
        child: Column(
          children: [
            SizedBox(
              width: cellWidth,
              child: _LazyCellHarness(
                cellId: cellId,
                controller: controller,
                focusNode: focusNode,
                text: controller.text,
                style: textStyle,
                padding: const EdgeInsetsDirectional.only(
                  start: 7,
                  end: 11,
                  top: 5,
                  bottom: 13,
                ),
                maxHeight: null,
                scrollbarGutter: scrollbarGutter,
              ),
            ),
          ],
        ),
      ),
    );

    final staticViewportRect = tester.getRect(
      find.byKey(LazyTextEditKeys.textViewport(cellId)),
    );

    await tester.tap(find.byKey(LazyTextEditKeys.staticSurface(cellId)));
    await tester.pump();

    final editViewportRect = tester.getRect(
      find.byKey(LazyTextEditKeys.textViewport(cellId)),
    );

    _expectRectClose(editViewportRect, staticViewportRect);
  });

  testWidgets(
    'decoration visibility controls chrome but keeps layout reserved',
    (tester) async {
      final controller = TextEditingController(text: 'abc def ghi jkl mno');
      final focusNode = FocusNode();

      addTearDown(controller.dispose);
      addTearDown(focusNode.dispose);

      await tester.pumpWidget(
        _TestApp(
          child: SizedBox(
            width: cellWidth,
            child: _LazyCellHarness(
              cellId: cellId,
              controller: controller,
              focusNode: focusNode,
              text: controller.text,
              style: textStyle,
              padding: padding,
              maxHeight: null,
              scrollbarGutter: scrollbarGutter,
              decoration: const LazyInputDecoration(
                prefixIcon: Icon(Icons.search, size: 12),
                prefixIconConstraints: BoxConstraints(minWidth: 24),
                suffixIcon: Icon(Icons.clear, size: 12),
                suffixIconConstraints: BoxConstraints(minWidth: 20),
              ),
            ),
          ),
        ),
      );

      final staticViewportRect = tester.getRect(
        find.byKey(LazyTextFieldKeys.textViewport(cellId)),
      );

      expect(find.byIcon(Icons.search), findsNothing);
      expect(staticViewportRect.width, cellWidth - padding.horizontal - 44);

      await tester.tap(find.byKey(LazyTextFieldKeys.staticSurface(cellId)));
      await tester.pump();

      final editViewportRect = tester.getRect(
        find.byKey(LazyTextFieldKeys.textViewport(cellId)),
      );

      expect(find.byIcon(Icons.search), findsOneWidget);
      expect(find.byIcon(Icons.clear), findsOneWidget);
      _expectRectClose(editViewportRect, staticViewportRect);
    },
  );

  testWidgets('always visible decoration shows hint in static mode', (
    tester,
  ) async {
    final controller = TextEditingController();
    final focusNode = FocusNode();

    addTearDown(controller.dispose);
    addTearDown(focusNode.dispose);

    await tester.pumpWidget(
      _TestApp(
        child: SizedBox(
          width: cellWidth,
          child: LazyTextField(
            cellId: cellId,
            text: '',
            isEditing: false,
            style: textStyle,
            padding: padding,
            decoration: const LazyInputDecoration(hintText: 'hint'),
            decorationVisibility: LazyInputDecorationVisibility.always,
            onStartEditing: () {},
          ),
        ),
      ),
    );

    expect(find.text('hint'), findsNothing);
    expect(find.byKey(LazyTextFieldKeys.root(cellId)), findsOneWidget);
  });

  test('height calculation reserves prefix and suffix widths', () {
    const text = 'aaaa aaaa aaaa aaaa aaaa';
    final full = LazyTextField.computeHeightForWidth(
      text: text,
      width: 120,
      style: textStyle,
      padding: padding,
    );
    final reserved = LazyTextField.computeHeightForWidth(
      text: text,
      width: 120,
      style: textStyle,
      padding: padding,
      reservedLeadingWidth: 24,
      reservedTrailingWidth: 20,
    );

    expect(reserved, greaterThanOrEqualTo(full));
  });

  test('height calculation is fast for constrained widths', () {
    final samples = [
      '',
      'one',
      'one two three four five',
      'line 1\nline 2\nline 3',
      'abcdefghijklmnopqrstuvwxyz',
    ];
    final watch = Stopwatch()..start();

    for (var i = 0; i < 10000; i++) {
      LazyTextField.computeHeightForWidth(
        text: samples[i % samples.length],
        width: 120,
        style: textStyle,
        padding: padding,
        reservedLeadingWidth: i.isEven ? 24 : 0,
        reservedTrailingWidth: i.isOdd ? 20 : 0,
      );
    }
    watch.stop();

    expect(watch.elapsedMilliseconds, lessThan(500));
  });

  testWidgets(
    'long wrapped text keeps same visual line boxes after edit switch',
    (tester) async {
      const longText =
          'alpha beta gamma delta epsilon zeta eta theta iota kappa '
          'lambda mu nu xi omicron pi rho sigma tau upsilon phi chi psi omega '
          'alpha-beta/gamma.delta, epsilon: zeta; eta theta iota';

      const narrowCellWidth = 137.0;

      final controller = TextEditingController(text: longText);
      final focusNode = FocusNode();

      addTearDown(controller.dispose);
      addTearDown(focusNode.dispose);

      await tester.pumpWidget(
        _TestApp(
          child: SizedBox(
            width: narrowCellWidth,
            child: _LazyCellHarness(
              cellId: cellId,
              controller: controller,
              focusNode: focusNode,
              text: controller.text,
              style: textStyle,
              padding: padding,
              maxHeight: null,
              scrollbarGutter: scrollbarGutter,
            ),
          ),
        ),
      );

      final staticViewportRect = tester.getRect(
        find.byKey(LazyTextFieldKeys.textViewport(cellId)),
      );

      final expectedStaticBoxes = _staticSelectionLineRects(
        text: longText,
        style: textStyle,
        maxWidth: staticViewportRect.width,
        origin: staticViewportRect.topLeft,
      );

      expect(
        expectedStaticBoxes.length,
        greaterThan(3),
        reason: 'fixture must wrap into several visual lines',
      );

      await tester.tap(find.byKey(LazyTextFieldKeys.staticSurface(cellId)));
      await tester.pump();

      final editViewportRect = tester.getRect(
        find.byKey(LazyTextFieldKeys.textViewport(cellId)),
      );

      _expectRectClose(
        editViewportRect,
        staticViewportRect,
        label: 'long text viewport',
        tolerance: 0.01,
      );

      final renderEditable = tester.renderObject<RenderEditable>(
        _findRenderEditableInside(cellId),
      );

      final actualEditBoxes = _editSelectionLineRects(
        renderEditable,
        selection: TextSelection(baseOffset: 0, extentOffset: longText.length),
      );

      _expectLineBoxListsClose(
        actualEditBoxes,
        expectedStaticBoxes,
        label: 'long wrapped text',
        tolerance: 1,
      );
      _expectCaretOffsetsClose(
        renderEditable,
        text: longText,
        style: textStyle,
        maxWidth: staticViewportRect.width,
        origin: staticViewportRect.topLeft,
        label: 'long wrapped text caret positions',
        tolerance: 1,
      );
    },
  );

  testWidgets('edit mode right click shows text selection toolbar', (
    tester,
  ) async {
    final controller = TextEditingController(text: 'hello world');
    final focusNode = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(focusNode.dispose);

    await tester.pumpWidget(
      _TestApp(
        child: SizedBox(
          width: cellWidth,
          child: LazyTextField(
            cellId: cellId,
            text: controller.text,
            controller: controller,
            focusNode: focusNode,
            isEditing: true,
            style: textStyle,
            padding: padding,
            decoration: null,
            decorationVisibility: LazyInputDecorationVisibility.never,
            onStartEditing: () {},
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    final editable = tester.widget<EditableText>(find.byType(EditableText));
    expect(editable.focusNode.hasFocus, isTrue);
    expect(editable.enableInteractiveSelection, isTrue);

    await tester.tapAt(
      tester.getCenter(find.byType(EditableText)),
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();

    expect(
      [
        find.byType(AdaptiveTextSelectionToolbar),
        find.byType(TextSelectionToolbar),
        find.text('Copy'),
      ].any((f) => f.evaluate().isNotEmpty),
      isTrue,
    );
  });

  testWidgets(
    'right click keeps selection when parent rebuilds on pointer down',
    (tester) async {
      final controller = TextEditingController(text: 'hello world');
      final focusNode = FocusNode();
      addTearDown(controller.dispose);
      addTearDown(focusNode.dispose);

      await tester.pumpWidget(
        _TestApp(
          child: SizedBox(
            width: cellWidth,
            child: _RebuildOnPointerDown(
              child: LazyTextField(
                cellId: cellId,
                text: controller.text,
                controller: controller,
                focusNode: focusNode,
                isEditing: true,
                style: textStyle,
                padding: padding,
                decoration: const LazyInputDecoration(),
                decorationVisibility: LazyInputDecorationVisibility.always,
                onStartEditing: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      controller.selection = const TextSelection(
        baseOffset: 0,
        extentOffset: 5,
      );
      await tester.pump();

      await tester.tapAt(
        tester.getCenter(find.byType(EditableText)),
        buttons: kSecondaryMouseButton,
      );
      await tester.pump();

      expect(controller.selection.isCollapsed, isFalse);
      expect(
        [
          find.byType(AdaptiveTextSelectionToolbar),
          find.byType(TextSelectionToolbar),
          find.text('Copy'),
        ].any((f) => f.evaluate().isNotEmpty),
        isTrue,
      );
    },
  );

  testWidgets('proportional long text keeps wrap positions after edit switch', (
    tester,
  ) async {
    const proportionalStyle = TextStyle(
      fontFamily: 'LazyTextFieldNotoSans',
      fontSize: 13,
      height: 1.2,
      letterSpacing: 0,
    );

    const longText =
        'iiii illi little slim iii, WWWW mmmm wide words, '
        'minimum million illumination. '
        'A narrow line with i/i/i and a wide line with WWW-mmm-WWW. '
        'file://some/path/with/mixed-width-characters_and.words';

    const narrowCellWidth = 173.0;

    final controller = TextEditingController(text: longText);
    final focusNode = FocusNode();

    addTearDown(controller.dispose);
    addTearDown(focusNode.dispose);

    await tester.pumpWidget(
      _TestApp(
        child: SizedBox(
          width: narrowCellWidth,
          child: _LazyCellHarness(
            cellId: cellId,
            controller: controller,
            focusNode: focusNode,
            text: controller.text,
            style: proportionalStyle,
            padding: padding,
            maxHeight: null,
            scrollbarGutter: scrollbarGutter,
          ),
        ),
      ),
    );

    final staticViewportRect = tester.getRect(
      find.byKey(LazyTextFieldKeys.textViewport(cellId)),
    );

    final expectedStaticBoxes = _staticSelectionLineRects(
      text: longText,
      style: proportionalStyle,
      maxWidth: staticViewportRect.width,
      origin: staticViewportRect.topLeft,
    );

    expect(
      expectedStaticBoxes.length,
      greaterThan(4),
      reason: 'fixture must wrap into many visual lines',
    );

    await tester.tap(find.byKey(LazyTextFieldKeys.staticSurface(cellId)));
    await tester.pump();

    final editViewportRect = tester.getRect(
      find.byKey(LazyTextFieldKeys.textViewport(cellId)),
    );

    _expectRectClose(
      editViewportRect,
      staticViewportRect,
      label: 'proportional text viewport',
      tolerance: 0.01,
    );

    final renderEditable = tester.renderObject<RenderEditable>(
      _findRenderEditableInside(cellId),
    );

    final actualEditBoxes = _editSelectionLineRects(
      renderEditable,
      selection: const TextSelection(
        baseOffset: 0,
        extentOffset: longText.length,
      ),
    );

    _expectLineBoxListsClose(
      actualEditBoxes,
      expectedStaticBoxes,
      label: 'proportional wrapped text',
      tolerance: 1.25,
    );
    _expectCaretOffsetsClose(
      renderEditable,
      text: longText,
      style: proportionalStyle,
      maxWidth: staticViewportRect.width,
      origin: staticViewportRect.topLeft,
      label: 'proportional wrapped text caret positions',
      tolerance: 1.25,
    );
  });
}

List<Rect> _staticSelectionLineRects({
  required String text,
  required TextStyle style,
  required double maxWidth,
  required Offset origin,
}) {
  final painter = _layoutStaticPainter(
    text: text,
    style: style,
    width: maxWidth,
  );

  final boxes = painter.getBoxesForSelection(
    TextSelection(
      baseOffset: 0,
      extentOffset: LazyTextFieldLayout.measureText(text).length,
    ),
  );

  expect(
    boxes,
    isNotEmpty,
    reason: 'static full-text selection produced no boxes',
  );

  final rects = boxes
      .map(
        (box) => Rect.fromLTRB(
          origin.dx + box.left,
          origin.dy + box.top,
          origin.dx + box.right,
          origin.dy + box.bottom,
        ),
      )
      .toList(growable: false);

  return _mergeRectsByVisualLine(rects);
}

List<Rect> _editSelectionLineRects(
  RenderEditable renderEditable, {
  required TextSelection selection,
}) {
  final boxes = renderEditable.getBoxesForSelection(selection);

  expect(
    boxes,
    isNotEmpty,
    reason: 'edit full-text selection produced no boxes',
  );

  final rects = boxes
      .map((box) {
        final topLeft = renderEditable.localToGlobal(Offset(box.left, box.top));
        final bottomRight = renderEditable.localToGlobal(
          Offset(box.right, box.bottom),
        );
        return Rect.fromPoints(topLeft, bottomRight);
      })
      .toList(growable: false);

  return _mergeRectsByVisualLine(rects);
}

List<Rect> _mergeRectsByVisualLine(List<Rect> rects) {
  final sorted = rects.toList(growable: false)
    ..sort((a, b) {
      final topComparison = a.top.compareTo(b.top);
      if (topComparison != 0) return topComparison;
      return a.left.compareTo(b.left);
    });

  final lines = <Rect>[];
  for (final rect in sorted) {
    if (rect.isEmpty) continue;
    if (lines.isEmpty || (rect.center.dy - lines.last.center.dy).abs() > 1) {
      lines.add(rect);
    } else {
      lines[lines.length - 1] = lines.last.expandToInclude(rect);
    }
  }
  return lines;
}

void _expectLineBoxListsClose(
  List<Rect> actual,
  List<Rect> expected, {
  required String label,
  double tolerance = 0.5,
}) {
  expect(
    actual.length,
    expected.length,
    reason:
        '$label changed visual line count '
        '(expected ${expected.length}, actual ${actual.length})',
  );

  for (var i = 0; i < expected.length; i++) {
    _expectLinePositionClose(
      actual[i],
      expected[i],
      label: '$label line ${i + 1}',
      tolerance: tolerance,
    );
  }
}

void _expectLinePositionClose(
  Rect actual,
  Rect expected, {
  required String label,
  double tolerance = 0.5,
}) {
  _expectCoordinateClose(
    actual.left,
    expected.left,
    label: '$label.left',
    negativeDirection: 'left',
    positiveDirection: 'right',
    tolerance: tolerance,
  );
  _expectCoordinateClose(
    actual.top,
    expected.top,
    label: '$label.top',
    negativeDirection: 'up',
    positiveDirection: 'down',
    tolerance: tolerance,
  );
}

class _LazyCellHarness extends StatefulWidget {
  const _LazyCellHarness({
    required this.cellId,
    required this.controller,
    required this.focusNode,
    required this.text,
    required this.style,
    required this.padding,
    required this.maxHeight,
    required this.scrollbarGutter,
    this.initiallyEditing = false,
    this.decoration,
  });

  final String cellId;
  final TextEditingController controller;
  final FocusNode focusNode;
  final String text;
  final TextStyle style;
  final EdgeInsetsGeometry padding;
  final double? maxHeight;
  final double scrollbarGutter;
  final bool initiallyEditing;
  final LazyInputDecoration? decoration;

  @override
  State<_LazyCellHarness> createState() => _LazyCellHarnessState();
}

class _LazyCellHarnessState extends State<_LazyCellHarness> {
  late bool isEditing = widget.initiallyEditing;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    super.dispose();
  }

  void _onControllerChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return LazyTextEditField(
      cellId: widget.cellId,
      text: widget.controller.text,
      controller: isEditing ? widget.controller : null,
      focusNode: isEditing ? widget.focusNode : null,
      isEditing: isEditing,
      style: widget.style,
      padding: widget.padding,
      decoration: widget.decoration,
      maxHeight: widget.maxHeight,
      scrollbarGutter: widget.scrollbarGutter,
      onStartEditing: () {
        setState(() {
          isEditing = true;
        });
      },
      onStopEditing: () {
        setState(() {
          isEditing = false;
        });
      },
    );
  }
}

class _TestApp extends StatelessWidget {
  const _TestApp({required this.child, this.textDirection = TextDirection.ltr});

  final Widget child;
  final TextDirection textDirection;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Directionality(
        textDirection: textDirection,
        child: Scaffold(
          body: Align(alignment: Alignment.topLeft, child: child),
        ),
      ),
    );
  }
}

double _paintedTextHeight({
  required BuildContext context,
  required String text,
  required TextStyle style,
  required double width,
  required bool singleLine,
}) {
  final painter = TextPainter(
    text: TextSpan(text: text.isEmpty ? '\u200B' : text, style: style),
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
    maxLines: singleLine ? 1 : null,
    ellipsis: singleLine ? '\u2026' : null,
  )..layout(maxWidth: math.max(0, width));

  return painter.height;
}

List<LineMetrics> _lineMetricsFor({
  required String text,
  required TextStyle style,
  required double width,
}) {
  final painter = _layoutStaticPainter(text: text, style: style, width: width);

  return painter.computeLineMetrics();
}

Offset _staticSelectionBoxTopLeft({
  required String text,
  required TextSelection selection,
  required TextStyle style,
  required double maxWidth,
  required Offset origin,
}) {
  final painter = _layoutStaticPainter(
    text: text,
    style: style,
    width: maxWidth,
  );
  final boxes = painter.getBoxesForSelection(selection);
  expect(boxes, isNotEmpty, reason: 'static selection $selection has no boxes');

  final box = boxes.first;
  return origin + Offset(box.left, box.top);
}

TextPainter _layoutStaticPainter({
  required String text,
  required TextStyle style,
  required double width,
}) {
  return TextPainter(
    text: TextSpan(text: LazyTextFieldLayout.measureText(text), style: style),
    textDirection: TextDirection.ltr,
    textScaler: TextScaler.noScaling,
    strutStyle: StrutStyle.fromTextStyle(style),
  )..layout(maxWidth: math.max(0, width - 3));
}

Finder _findRenderEditableInside(String cellId) {
  return find.descendant(
    of: find.byKey(LazyTextEditKeys.editorSurface(cellId)),
    matching: find.byElementPredicate((element) {
      return element.renderObject is RenderEditable;
    }),
  );
}

void _expectSelectionBoxTopLeft(
  RenderEditable renderEditable,
  TextSelection selection,
  Offset expected, {
  required String label,
  double tolerance = 0.5,
}) {
  final boxes = renderEditable.getBoxesForSelection(selection);
  expect(boxes, isNotEmpty, reason: '$label has no selection boxes');

  final box = boxes.first;
  final actual = renderEditable.localToGlobal(Offset(box.left, box.top));

  _expectPointClose(actual, expected, label: label, tolerance: tolerance);
}

void _expectCaretOffsetsClose(
  RenderEditable renderEditable, {
  required String text,
  required TextStyle style,
  required double maxWidth,
  required Offset origin,
  required String label,
  double tolerance = 0.5,
}) {
  final painter = _layoutStaticPainter(
    text: text,
    style: style,
    width: maxWidth,
  );
  final offsets = _wordStartOffsets(text);
  expect(offsets, isNotEmpty, reason: '$label fixture has no word starts');

  for (final offset in offsets) {
    final position = TextPosition(offset: offset);
    final expected =
        origin +
        painter.getOffsetForCaret(
          position,
          Rect.fromLTWH(
            0,
            0,
            renderEditable.cursorWidth,
            painter.preferredLineHeight,
          ),
        );
    final actual = renderEditable.localToGlobal(
      renderEditable.getLocalRectForCaret(position).topLeft,
    );
    _expectCoordinateClose(
      actual.dy,
      expected.dy,
      label: '$label offset $offset.dy',
      negativeDirection: 'up',
      positiveDirection: 'down',
      tolerance: tolerance,
    );
  }
}

List<int> _wordStartOffsets(String text) {
  final offsets = <int>{0};
  for (var i = 1; i < text.length; i++) {
    if (text.codeUnitAt(i - 1) == 0x20 && text.codeUnitAt(i) != 0x20) {
      offsets.add(i);
    }
  }
  offsets.add(text.length);
  return offsets.toList(growable: false);
}

void _expectRectClose(
  Rect actual,
  Rect expected, {
  String label = 'rect',
  double tolerance = 0.5,
}) {
  _expectCoordinateClose(
    actual.left,
    expected.left,
    label: '$label.left',
    negativeDirection: 'left',
    positiveDirection: 'right',
    tolerance: tolerance,
  );
  _expectCoordinateClose(
    actual.top,
    expected.top,
    label: '$label.top',
    negativeDirection: 'up',
    positiveDirection: 'down',
    tolerance: tolerance,
  );
  _expectCoordinateClose(
    actual.width,
    expected.width,
    label: '$label.width',
    negativeDirection: 'narrower',
    positiveDirection: 'wider',
    tolerance: tolerance,
  );
  _expectCoordinateClose(
    actual.height,
    expected.height,
    label: '$label.height',
    negativeDirection: 'shorter',
    positiveDirection: 'taller',
    tolerance: tolerance,
  );
}

void _expectPointClose(
  Offset actual,
  Offset expected, {
  required String label,
  double tolerance = 0.5,
}) {
  _expectCoordinateClose(
    actual.dx,
    expected.dx,
    label: '$label.dx',
    negativeDirection: 'left',
    positiveDirection: 'right',
    tolerance: tolerance,
  );
  _expectCoordinateClose(
    actual.dy,
    expected.dy,
    label: '$label.dy',
    negativeDirection: 'up',
    positiveDirection: 'down',
    tolerance: tolerance,
  );
}

class _RebuildOnPointerDown extends StatefulWidget {
  const _RebuildOnPointerDown({required this.child});

  final Widget child;

  @override
  State<_RebuildOnPointerDown> createState() => _RebuildOnPointerDownState();
}

class _RebuildOnPointerDownState extends State<_RebuildOnPointerDown> {
  var _generation = 0;

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => setState(() => _generation++),
      child: ColoredBox(
        color: Color.fromARGB(_generation, 0, 0, 0),
        child: widget.child,
      ),
    );
  }
}

void _expectCoordinateClose(
  double actual,
  double expected, {
  required String label,
  required String negativeDirection,
  required String positiveDirection,
  required double tolerance,
}) {
  final delta = actual - expected;
  final direction = delta < 0 ? negativeDirection : positiveDirection;

  expect(
    actual,
    closeTo(expected, tolerance),
    reason:
        '$label jumped $direction by ${delta.abs()} '
        '(expected $expected, actual $actual)',
  );
}
