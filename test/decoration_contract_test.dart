import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lazy_text_field/lazy_text_field.dart';

/// Geometry + decoration compatibility for the no-layout-jump promise.
///
/// Complements the deeper glyph/animation suites in
/// `lazy_text_edit_field_test.dart` without rewriting them.
void main() {
  const cellId = 'contract';
  const style = TextStyle(
    fontFamily: 'Ahem',
    fontSize: 14,
    height: 1,
    letterSpacing: 0,
  );

  group('P0 mode switch contract', () {
    testWidgets(
      'InputDecorator State persists; root/viewport/baseline stay put',
      (tester) async {
        // Pixel glyph/wrap fidelity across the switch is covered in
        // lazy_text_edit_field_test.dart; this suite owns decorator identity
        // + geometry for the decoration-contract promise.
        final harness = GlobalKey<_ContractHarnessState>();
        await tester.pumpWidget(
          _App(
            child: _BaselineProbe(
              key: const ValueKey('baseline-probe'),
              child: _ContractHarness(
                key: harness,
                cellId: cellId,
                text: 'alpha beta gamma delta epsilon',
                style: style,
                width: 160,
                decoration: const InputDecoration(
                  filled: true,
                  border: OutlineInputBorder(),
                  labelText: 'Title',
                  hintText: 'Hint',
                  helperText: 'Helper',
                  prefixIcon: Icon(Icons.notes, size: 18),
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();

        final decoratorFinder = find.byType(InputDecorator);
        expect(decoratorFinder, findsOneWidget);
        final decoratorState = tester.state(decoratorFinder);
        final before = _snapshot(tester, cellId);

        expect(find.byType(TextField), findsNothing);
        expect(
          find.byKey(LazyTextFieldKeys.staticSurface(cellId)),
          findsOneWidget,
        );

        harness.currentState!.startEditing();
        // Intermediate frames must not jump either.
        await tester.pump(const Duration(milliseconds: 16));
        final mid = _snapshot(tester, cellId);
        _expectGeometryStable(mid, before, label: 'mid-animation');

        await tester.pump(const Duration(milliseconds: 50));
        await tester.pump();

        expect(identical(tester.state(decoratorFinder), decoratorState), isTrue);
        expect(find.byType(TextField), findsOneWidget);
        expect(
          find.byKey(LazyTextFieldKeys.editorSurface(cellId)),
          findsOneWidget,
        );
        expect(
          find.byKey(LazyTextFieldKeys.staticSurface(cellId)),
          findsNothing,
        );

        final after = _snapshot(tester, cellId);
        _expectGeometryStable(after, before, label: 'display→edit');

        harness.currentState!.stopEditing();
        await tester.pump(const Duration(milliseconds: 16));
        await tester.pump();

        expect(identical(tester.state(decoratorFinder), decoratorState), isTrue);
        expect(find.byType(TextField), findsNothing);
        final back = _snapshot(tester, cellId);
        _expectGeometryStable(back, before, label: 'edit→display');
      },
    );

    testWidgets('empty and nonempty text keep stable geometry', (tester) async {
      for (final text in ['', 'hello world', 'line1\nline2\nline3']) {
        final harness = GlobalKey<_ContractHarnessState>();
        await tester.pumpWidget(
          _App(
            child: _BaselineProbe(
              key: const ValueKey('baseline-probe'),
              child: _ContractHarness(
                key: harness,
                cellId: cellId,
                text: text,
                style: style,
                width: 180,
                decoration: const InputDecoration(
                  border: UnderlineInputBorder(),
                  labelText: 'Notes',
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 6,
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        final before = _snapshot(tester, cellId);

        harness.currentState!.startEditing();
        await tester.pump();
        _expectGeometryStable(
          _snapshot(tester, cellId),
          before,
          label: 'text=${text.isEmpty ? "<empty>" : text}',
        );

        harness.currentState!.stopEditing();
        await tester.pump();
      }
    });
  });

  group('P1 decoration feature matrix', () {
    final cases = <(String, InputDecoration)>[
      ('border.none', const InputDecoration(border: InputBorder.none)),
      ('outline', const InputDecoration(border: OutlineInputBorder())),
      ('underline', const InputDecoration(border: UnderlineInputBorder())),
      (
        'filled',
        const InputDecoration(
          filled: true,
          fillColor: Color(0xFFE8EEF7),
          border: OutlineInputBorder(),
        ),
      ),
      (
        'label+floating.always',
        const InputDecoration(
          labelText: 'Label',
          floatingLabelBehavior: FloatingLabelBehavior.always,
          border: OutlineInputBorder(),
        ),
      ),
      (
        'hint',
        const InputDecoration(
          hintText: 'Hint',
          hintMaxLines: 1,
          border: OutlineInputBorder(),
        ),
      ),
      (
        'helper+counter',
        const InputDecoration(
          helperText: 'Helper',
          counterText: '0/10',
          border: OutlineInputBorder(),
        ),
      ),
      (
        'icons+affixes',
        const InputDecoration(
          icon: Icon(Icons.star, size: 18),
          prefixIcon: Icon(Icons.search, size: 18),
          suffixIcon: Icon(Icons.clear, size: 18),
          prefixText: '\$',
          suffixText: 'kg',
          prefixIconConstraints: BoxConstraints.tightFor(width: 32, height: 32),
          suffixIconConstraints: BoxConstraints.tightFor(width: 32, height: 32),
          border: OutlineInputBorder(),
        ),
      ),
      (
        'padding+dense',
        const InputDecoration(
          isDense: true,
          contentPadding: EdgeInsets.fromLTRB(10, 8, 10, 8),
          border: OutlineInputBorder(),
        ),
      ),
      (
        'collapsed',
        const InputDecoration(
          isCollapsed: true,
          border: InputBorder.none,
          contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        ),
      ),
      (
        'constraints',
        const InputDecoration(
          constraints: BoxConstraints(minHeight: 40),
          border: OutlineInputBorder(),
          contentPadding: EdgeInsets.all(8),
        ),
      ),
    ];

    for (final entry in cases) {
      final name = entry.$1;
      final decoration = entry.$2;

      testWidgets('matrix: $name survives display↔edit stably', (tester) async {
        final harness = GlobalKey<_ContractHarnessState>();
        await tester.pumpWidget(
          _App(
            child: _BaselineProbe(
              key: const ValueKey('baseline-probe'),
              child: _ContractHarness(
                key: harness,
                cellId: cellId,
                text: 'matrix sample text',
                style: style,
                width: 220,
                decoration: decoration,
              ),
            ),
          ),
        );
        await tester.pump();

        expect(find.byType(InputDecorator), findsOneWidget);
        final before = _snapshot(tester, cellId);

        harness.currentState!.startEditing();
        await tester.pump();
        _expectGeometryStable(
          _snapshot(tester, cellId),
          before,
          label: '$name edit',
        );

        harness.currentState!.stopEditing();
        await tester.pump();
        _expectGeometryStable(
          _snapshot(tester, cellId),
          before,
          label: '$name back',
        );
      });
    }

    testWidgets('Material 2 and Material 3 themes stay stable', (tester) async {
      for (final useMaterial3 in [false, true]) {
        final harness = GlobalKey<_ContractHarnessState>();
        await tester.pumpWidget(
          _App(
            theme: ThemeData(
              useMaterial3: useMaterial3,
              inputDecorationTheme: const InputDecorationTheme(
                filled: true,
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
              ),
            ),
            child: _BaselineProbe(
              key: const ValueKey('baseline-probe'),
              child: _ContractHarness(
                key: harness,
                cellId: cellId,
                text: 'themed',
                style: style,
                width: 200,
                decoration: const InputDecoration(labelText: 'Themed'),
              ),
            ),
          ),
        );
        await tester.pump();
        final before = _snapshot(tester, cellId);
        harness.currentState!.startEditing();
        await tester.pump();
        _expectGeometryStable(
          _snapshot(tester, cellId),
          before,
          label: 'M3=$useMaterial3',
        );
      }
    });
  });

  group('P1 dynamic decorations', () {
    testWidgets('focus border/fill animation keeps geometry', (tester) async {
      final harness = GlobalKey<_ContractHarnessState>();
      await tester.pumpWidget(
        _App(
          child: _BaselineProbe(
            key: const ValueKey('baseline-probe'),
            child: _ContractHarness(
              key: harness,
              cellId: cellId,
              text: 'focus me',
              style: style,
              width: 200,
              decoration: const InputDecoration(
                filled: true,
                fillColor: Color(0xFFF5F5F5),
                focusColor: Color(0xFFE3F2FD),
                border: OutlineInputBorder(),
                focusedBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.blue, width: 2),
                ),
                contentPadding: EdgeInsets.all(10),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      final before = _snapshot(tester, cellId);

      harness.currentState!.startEditing();
      await tester.pump();
      harness.currentState!.focusNode.requestFocus();
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(const Duration(milliseconds: 100));
      _expectGeometryStable(
        _snapshot(tester, cellId),
        before,
        label: 'focused animation',
      );
    });

    testWidgets('fixed icon slot AnimatedOpacity keeps viewport', (tester) async {
      final harness = GlobalKey<_ContractHarnessState>();
      await tester.pumpWidget(
        _App(
          child: _BaselineProbe(
            key: const ValueKey('baseline-probe'),
            child: _ContractHarness(
              key: harness,
              cellId: cellId,
              text: 'opacity slot',
              style: style,
              width: 200,
              decorationBuilder: (editing) {
                return InputDecoration(
                  border: const OutlineInputBorder(),
                  contentPadding: const EdgeInsets.all(8),
                  suffixIconConstraints: const BoxConstraints.tightFor(
                    width: 40,
                    height: 40,
                  ),
                  suffixIcon: IgnorePointer(
                    ignoring: !editing,
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 120),
                      opacity: editing ? 1 : 0,
                      child: const Icon(Icons.check),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      );
      await tester.pump();
      final before = _snapshot(tester, cellId);

      harness.currentState!.startEditing();
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(const Duration(milliseconds: 150));
      _expectGeometryStable(
        _snapshot(tester, cellId),
        before,
        label: 'AnimatedOpacity suffix',
      );
    });

    testWidgets(
      'resizing suffix constraints is outside the guarantee (documents change)',
      (tester) async {
        // Not a failure of LazyTextField — proves the promise does not cover
        // changing decoration intrinsics between modes.
        final harness = GlobalKey<_ContractHarnessState>();
        await tester.pumpWidget(
          _App(
            child: _BaselineProbe(
              key: const ValueKey('baseline-probe'),
              child: _ContractHarness(
                key: harness,
                cellId: cellId,
                text: 'resize',
                style: style,
                width: 200,
                decorationBuilder: (editing) {
                  return InputDecoration(
                    border: const OutlineInputBorder(),
                    contentPadding: const EdgeInsets.all(8),
                    suffixIcon: const Icon(Icons.check),
                    suffixIconConstraints: BoxConstraints.tightFor(
                      width: editing ? 56 : 24,
                      height: editing ? 56 : 24,
                    ),
                  );
                },
              ),
            ),
          ),
        );
        await tester.pump();
        final before = _snapshot(tester, cellId);

        harness.currentState!.startEditing();
        await tester.pump();
        final after = _snapshot(tester, cellId);

        expect(
          after.viewport,
          isNot(before.viewport),
          reason:
              'changing suffixIconConstraints between modes is unsupported '
              'usage; geometry may change',
        );
      },
    );
  });

  group('P2 cross-config smoke', () {
    testWidgets('RTL + larger textScaler stays stable', (tester) async {
      final harness = GlobalKey<_ContractHarnessState>();
      await tester.pumpWidget(
        _App(
          textDirection: TextDirection.rtl,
          textScaler: const TextScaler.linear(1.5),
          child: _BaselineProbe(
            key: const ValueKey('baseline-probe'),
            child: _ContractHarness(
              key: harness,
              cellId: cellId,
              text: 'مرحبا world wrap please',
              style: style,
              width: 140,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'RTL',
                prefixIcon: Icon(Icons.language, size: 18),
                contentPadding: EdgeInsets.all(8),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      final before = _snapshot(tester, cellId);
      harness.currentState!.startEditing();
      await tester.pump();
      _expectGeometryStable(
        _snapshot(tester, cellId),
        before,
        label: 'rtl+scaler',
      );
    });
  });
}

class _GeometrySnapshot {
  const _GeometrySnapshot({
    required this.root,
    required this.viewport,
    required this.baseline,
  });

  final Rect root;
  final Rect viewport;
  final double baseline;
}

_GeometrySnapshot _snapshot(WidgetTester tester, String cellId) {
  final root = tester.getRect(find.byKey(LazyTextFieldKeys.root(cellId)));
  final viewport = tester.getRect(
    find.byKey(LazyTextFieldKeys.textViewport(cellId)),
  );
  final probe = tester.renderObject<_RenderBaselineProbe>(
    find.byKey(const ValueKey('baseline-probe')),
  );
  expect(probe.baseline, isNotNull);
  final baseline = probe.localToGlobal(Offset(0, probe.baseline!)).dy;
  return _GeometrySnapshot(root: root, viewport: viewport, baseline: baseline);
}

class _BaselineProbe extends SingleChildRenderObjectWidget {
  const _BaselineProbe({required super.child, super.key});

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderBaselineProbe();
}

class _RenderBaselineProbe extends RenderProxyBox {
  double? baseline;

  @override
  void performLayout() {
    super.performLayout();
    baseline = child?.getDistanceToBaseline(TextBaseline.alphabetic);
  }
}

void _expectGeometryStable(
  _GeometrySnapshot actual,
  _GeometrySnapshot expected, {
  required String label,
  double tolerance = 0.5,
}) {
  _expectRectClose(actual.root, expected.root, '$label.root', tolerance);
  _expectRectClose(
    actual.viewport,
    expected.viewport,
    '$label.viewport',
    tolerance,
  );
  expect(
    actual.baseline,
    closeTo(expected.baseline, tolerance),
    reason: '$label.baseline actual=${actual.baseline} '
        'expected=${expected.baseline}',
  );
}

void _expectRectClose(
  Rect actual,
  Rect expected,
  String label,
  double tolerance,
) {
  expect(actual.left, closeTo(expected.left, tolerance), reason: '$label.left');
  expect(actual.top, closeTo(expected.top, tolerance), reason: '$label.top');
  expect(
    actual.right,
    closeTo(expected.right, tolerance),
    reason: '$label.right',
  );
  expect(
    actual.bottom,
    closeTo(expected.bottom, tolerance),
    reason: '$label.bottom',
  );
}

class _App extends StatelessWidget {
  const _App({
    required this.child,
    this.theme,
    this.textDirection = TextDirection.ltr,
    this.textScaler = TextScaler.noScaling,
  });

  final Widget child;
  final ThemeData? theme;
  final TextDirection textDirection;
  final TextScaler textScaler;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: theme ?? ThemeData(useMaterial3: true),
      home: MediaQuery(
        data: MediaQueryData(textScaler: textScaler),
        child: Directionality(
          textDirection: textDirection,
          child: Scaffold(body: Center(child: child)),
        ),
      ),
    );
  }
}

class _ContractHarness extends StatefulWidget {
  const _ContractHarness({
    super.key,
    required this.cellId,
    required this.text,
    required this.style,
    required this.width,
    this.decoration,
    this.decorationBuilder,
  }) : assert(decoration == null || decorationBuilder == null);

  final String cellId;
  final String text;
  final TextStyle style;
  final double width;
  final InputDecoration? decoration;
  final InputDecoration Function(bool isEditing)? decorationBuilder;

  @override
  State<_ContractHarness> createState() => _ContractHarnessState();
}

class _ContractHarnessState extends State<_ContractHarness> {
  late final TextEditingController controller = TextEditingController(
    text: widget.text,
  );
  final FocusNode focusNode = FocusNode();
  var isEditing = false;

  @override
  void dispose() {
    controller.dispose();
    focusNode.dispose();
    super.dispose();
  }

  void startEditing() {
    setState(() => isEditing = true);
  }

  void stopEditing() {
    setState(() => isEditing = false);
  }

  @override
  Widget build(BuildContext context) {
    final decoration =
        widget.decorationBuilder?.call(isEditing) ?? widget.decoration;
    return SizedBox(
      width: widget.width,
      child: LazyTextField(
        cellId: widget.cellId,
        text: controller.text,
        style: widget.style,
        isEditing: isEditing,
        controller: isEditing ? controller : null,
        focusNode: isEditing ? focusNode : null,
        // Pass decoration through unchanged (do not override contentPadding).
        decoration: decoration,
        onStartEditing: startEditing,
        onStopEditing: stopEditing,
      ),
    );
  }
}
