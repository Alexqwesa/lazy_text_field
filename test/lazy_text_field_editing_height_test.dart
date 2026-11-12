import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lazy_text_field/lazy_text_field.dart';

// Ahem with height 1: every line is exactly 10 px tall.
const _style = TextStyle(
  fontFamily: 'Ahem',
  fontSize: 10,
  height: 1,
  letterSpacing: 0,
);
const _twoLines = 20.0;
const _editingMax = 60.0;

void main() {
  late List<double> reports;

  setUp(() => reports = []);

  Future<void> pumpField(
    WidgetTester tester, {
    String text = 'one',
    double? editingMaxHeight = _editingMax,
    bool show = true,
    bool attach = true,
    ValueChanged<double>? onExtra,
  }) {
    return tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 200,
              child: show
                  ? StatefulLazyTextField(
                      cellId: 'c',
                      text: text,
                      style: _style,
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        isCollapsed: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                      minHeight: _twoLines,
                      maxHeight: _twoLines,
                      editingMaxHeight: editingMaxHeight,
                      onEditingExtraHeightChanged: attach
                          ? (onExtra ?? reports.add)
                          : null,
                      onSave: (_) => true,
                    )
                  : const SizedBox(),
            ),
          ),
        ),
      ),
    );
  }

  double viewportHeight(WidgetTester tester) =>
      tester.getSize(find.byKey(LazyTextFieldKeys.textViewport('c'))).height;

  double viewportWidth(WidgetTester tester) =>
      tester.getSize(find.byKey(LazyTextFieldKeys.textViewport('c'))).width;

  Future<void> startEditing(WidgetTester tester) async {
    await tester.tap(find.byKey(LazyTextFieldKeys.staticSurface('c')));
    await tester.pump();
    await tester.pump();
  }

  Future<void> type(WidgetTester tester, String text) async {
    await tester.enterText(find.byType(EditableText), text);
    await tester.pump();
    await tester.pump();
  }

  testWidgets('read-only text never reports, even when it overflows', (
    tester,
  ) async {
    await pumpField(tester, text: '1\n2\n3\n4\n5');
    await tester.pump();
    expect(viewportHeight(tester), _twoLines);
    expect(reports, isEmpty);
  });

  testWidgets('the editor grows with its text and reports the extra height', (
    tester,
  ) async {
    await pumpField(tester);
    await startEditing(tester);
    expect(reports, isEmpty);

    await type(tester, '1\n2\n3\n4');
    expect(viewportHeight(tester), 40);
    expect(reports, [20]);

    // Same height: no new report.
    await type(tester, '1\n2\n3\nfour');
    expect(reports, [20]);

    // Capped by editingMaxHeight.
    await type(tester, List.generate(12, (i) => '$i').join('\n'));
    expect(viewportHeight(tester), _editingMax);
    expect(reports, [20, 40]);

    await type(tester, 'short');
    expect(viewportHeight(tester), _twoLines);
    expect(reports, [20, 40, 0]);
  });

  testWidgets('stopping editing reports 0 and restores the read-only clip', (
    tester,
  ) async {
    await pumpField(tester);
    await startEditing(tester);
    await type(tester, '1\n2\n3\n4');
    expect(reports, [20]);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    await tester.pump();
    expect(find.byType(EditableText), findsNothing);
    expect(viewportHeight(tester), _twoLines);
    expect(reports, [20, 0]);
  });

  testWidgets('disposing a grown editor reports 0', (tester) async {
    await pumpField(tester);
    await startEditing(tester);
    await type(tester, '1\n2\n3\n4');
    expect(reports, [20]);

    await pumpField(tester, show: false);
    await tester.pump();
    expect(reports, [20, 0]);
  });

  testWidgets('detaching the callback shrinks the old consumer; a new one '
      'gets the current height', (tester) async {
    await pumpField(tester);
    await startEditing(tester);
    await type(tester, '1\n2\n3\n4');
    expect(reports, [20]);

    await pumpField(tester, attach: false);
    await tester.pump();
    expect(reports, [20, 0]);

    // Growing while detached reports nothing.
    await type(tester, '1\n2\n3\n4\n5');
    expect(reports, [20, 0]);

    final second = <double>[];
    await pumpField(tester, onExtra: second.add);
    await tester.pump();
    expect(second, [30]);
    expect(reports, [20, 0]);
  });

  testWidgets('a replaced callback keeps the consumer: the new one gets the '
      'next change, and nothing is re-sent', (tester) async {
    await pumpField(tester);
    await startEditing(tester);
    await type(tester, '1\n2\n3\n4');
    expect(reports, [20]);

    final replacement = <double>[];
    await pumpField(tester, onExtra: replacement.add);
    await tester.pump();
    expect(replacement, isEmpty);
    expect(reports, [20]);

    await type(tester, '1\n2\n3\n4\n5');
    expect(replacement, [30]);
    expect(reports, [20]);
  });

  testWidgets('an inline callback that rebuilds its parent does not loop', (
    tester,
  ) async {
    var extra = 0.0;
    var builds = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: StatefulBuilder(
              builder: (context, setState) {
                builds++;
                return SizedBox(
                  width: 200,
                  height: _twoLines + extra,
                  child: StatefulLazyTextField(
                    cellId: 'c',
                    text: 'one',
                    style: _style,
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      isCollapsed: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                    minHeight: _twoLines,
                    maxHeight: _twoLines,
                    editingMaxHeight: _editingMax,
                    // A new closure every build. The last report (0) can
                    // arrive after this parent was disposed too.
                    onEditingExtraHeightChanged: (value) {
                      if (context.mounted) setState(() => extra = value);
                    },
                    onSave: (_) => true,
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
    await startEditing(tester);
    await type(tester, '1\n2\n3\n4');
    expect(extra, 20);
    final settledBuilds = builds;
    await tester.pump();
    await tester.pump();
    expect(builds, settledBuilds);
  });

  testWidgets('growing and disposing in one frame reports 0 exactly once', (
    tester,
  ) async {
    await pumpField(tester);
    await startEditing(tester);
    await type(tester, '1\n2\n3\n4');
    expect(reports, [20]);

    // New text and removal land in the same frame: the larger height is
    // never laid out, and the consumer gets a single 0.
    await tester.enterText(find.byType(EditableText), '1\n2\n3\n4\n5\n6');
    await pumpField(tester, show: false);
    await tester.pump();
    await tester.pump();
    expect(reports, [20, 0]);
  });

  testWidgets('without editingMaxHeight the editor keeps the read-only cap', (
    tester,
  ) async {
    await pumpField(tester, editingMaxHeight: null);
    await startEditing(tester);
    await type(tester, '1\n2\n3\n4');
    expect(viewportHeight(tester), _twoLines);
    expect(reports, isEmpty);
  });

  testWidgets('growing keeps the text width, so wrapping does not change', (
    tester,
  ) async {
    await pumpField(tester, text: 'x');
    final readOnlyWidth = viewportWidth(tester);
    await startEditing(tester);
    await type(tester, '1\n2\n3\n4');
    expect(viewportWidth(tester), readOnlyWidth);
  });

  testWidgets('ScopedLazyTextField passes the options through', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: LazyTextFieldControllerScope(
              child: SizedBox(
                width: 200,
                child: ScopedLazyTextField(
                  cellId: 'c',
                  text: 'one',
                  style: _style,
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    isCollapsed: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                  minHeight: _twoLines,
                  maxHeight: _twoLines,
                  editingMaxHeight: _editingMax,
                  onEditingExtraHeightChanged: reports.add,
                  onSave: (_) => true,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await startEditing(tester);
    await type(tester, '1\n2\n3\n4');
    expect(viewportHeight(tester), 40);
    expect(reports, [20]);
  });

  testWidgets('infinite editingMaxHeight grows with all text, same wrapping', (
    tester,
  ) async {
    await pumpField(tester, text: 'x', editingMaxHeight: double.infinity);
    final readOnlyWidth = viewportWidth(tester);
    await startEditing(tester);
    await type(tester, List.generate(12, (i) => '$i').join('\n'));

    expect(viewportHeight(tester), 120);
    expect(viewportWidth(tester), readOnlyWidth);
    expect(reports, [100]);
    expect(tester.takeException(), isNull);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    await tester.pump();
    expect(viewportHeight(tester), _twoLines);
    expect(reports, [100, 0]);
  });

  test('editingMaxHeight must not be negative', () {
    expect(
      () => LazyTextField(
        cellId: 'c',
        text: '',
        isEditing: false,
        onStartEditing: () {},
        maxHeight: 20,
        editingMaxHeight: -1,
      ),
      throwsAssertionError,
    );
  });
}
