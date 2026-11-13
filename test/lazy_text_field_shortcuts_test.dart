import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lazy_text_field/lazy_text_field.dart';

const _style = TextStyle(
  fontFamily: 'Ahem',
  fontSize: 10,
  height: 1,
  letterSpacing: 0,
);

const _decoration = InputDecoration(
  border: InputBorder.none,
  isCollapsed: true,
  contentPadding: EdgeInsets.all(4),
);

void main() {
  late List<String> saves;
  late int cancels;

  setUp(() {
    saves = [];
    cancels = 0;
  });

  bool save(String value) {
    saves.add(value);
    return true;
  }

  Widget app(
    Widget child, {
    Map<ShortcutActivator, LazyTextFieldAction>? scope,
  }) {
    final field = SizedBox(width: 200, child: child);
    return MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: scope == null
              ? field
              : LazyTextFieldScope(shortcuts: scope, child: field),
        ),
      ),
    );
  }

  Widget stateful({
    bool singleLine = false,
    Map<ShortcutActivator, LazyTextFieldAction>? shortcuts,
  }) => StatefulLazyTextField(
    cellId: 'cell',
    text: 'old',
    singleLine: singleLine,
    style: _style,
    decoration: _decoration,
    shortcuts: shortcuts,
    onSave: save,
    onCancel: () => cancels++,
  );

  Future<void> open(WidgetTester tester, Widget widget) async {
    await tester.pumpWidget(widget);
    await tester.tap(find.byKey(LazyTextFieldKeys.staticSurface('cell')));
    await tester.pump();
    await tester.pump();
    await tester.enterText(find.byType(EditableText), 'new');
    await tester.pump();
  }

  Future<void> press(
    WidgetTester tester,
    LogicalKeyboardKey key, {
    LogicalKeyboardKey? modifier,
  }) async {
    if (modifier != null) await tester.sendKeyDownEvent(modifier);
    await tester.sendKeyEvent(key);
    if (modifier != null) await tester.sendKeyUpEvent(modifier);
    await tester.pump();
  }

  bool isEditing() => find.byType(EditableText).evaluate().isNotEmpty;

  group('default shortcuts', () {
    testWidgets('Cmd+S saves', (tester) async {
      await open(tester, app(stateful()));
      await press(
        tester,
        LogicalKeyboardKey.keyS,
        modifier: LogicalKeyboardKey.metaLeft,
      );
      expect(saves, ['new']);
    });

    testWidgets('Cmd+Enter saves', (tester) async {
      await open(tester, app(stateful()));
      await press(
        tester,
        LogicalKeyboardKey.enter,
        modifier: LogicalKeyboardKey.metaLeft,
      );
      expect(saves, ['new']);
    });

    testWidgets('Escape cancels', (tester) async {
      await open(tester, app(stateful()));
      await press(tester, LogicalKeyboardKey.escape);
      expect(cancels, 1);
      expect(isEditing(), isFalse);
      expect(saves, isEmpty);
    });
  });

  group('LazyTextFieldScope shortcuts', () {
    testWidgets('a key left out of the map does nothing', (tester) async {
      // A const activator is the same object as the default's key.
      final withoutEscape = Map.of(LazyTextFieldScope.defaultShortcuts)
        ..remove(const SingleActivator(LogicalKeyboardKey.escape));
      expect(withoutEscape, hasLength(6));
      await open(tester, app(stateful(), scope: withoutEscape));

      await press(tester, LogicalKeyboardKey.escape);
      expect(cancels, 0);
      expect(isEditing(), isTrue);

      await press(
        tester,
        LogicalKeyboardKey.keyS,
        modifier: LogicalKeyboardKey.controlLeft,
      );
      expect(saves, ['new']);
    });

    testWidgets('a remapped key replaces the defaults', (tester) async {
      await open(
        tester,
        app(
          stateful(),
          scope: const {
            SingleActivator(LogicalKeyboardKey.f2): LazyTextFieldAction.save,
            SingleActivator(LogicalKeyboardKey.f3): LazyTextFieldAction.cancel,
          },
        ),
      );

      await press(
        tester,
        LogicalKeyboardKey.keyS,
        modifier: LogicalKeyboardKey.controlLeft,
      );
      expect(saves, isEmpty);

      await press(tester, LogicalKeyboardKey.f2);
      expect(saves, ['new']);
    });

    testWidgets('a field shortcuts parameter overrides the scope', (
      tester,
    ) async {
      await open(
        tester,
        app(
          stateful(
            shortcuts: const {
              SingleActivator(LogicalKeyboardKey.f2): LazyTextFieldAction.save,
            },
          ),
          scope: LazyTextFieldScope.defaultShortcuts,
        ),
      );

      await press(tester, LogicalKeyboardKey.escape);
      expect(cancels, 0);
      await press(tester, LogicalKeyboardKey.f2);
      expect(saves, ['new']);
    });

    testWidgets('Enter still saves a single-line field with an empty map', (
      tester,
    ) async {
      await open(tester, app(stateful(singleLine: true), scope: const {}));
      await press(tester, LogicalKeyboardKey.enter);
      expect(saves, ['new']);
    });

    testWidgets('applies to ScopedLazyTextField', (tester) async {
      final controller = LazyTextFieldEditController();
      addTearDown(controller.dispose);
      await open(
        tester,
        app(
          LazyTextFieldScope(
            controller: controller,
            child: ScopedLazyTextField(
              cellId: 'cell',
              text: 'old',
              style: _style,
              decoration: _decoration,
              onSave: save,
              onCancel: () => cancels++,
            ),
          ),
          scope: const {
            SingleActivator(LogicalKeyboardKey.f2): LazyTextFieldAction.save,
            SingleActivator(LogicalKeyboardKey.f3): LazyTextFieldAction.cancel,
          },
        ),
      );

      await press(tester, LogicalKeyboardKey.escape);
      await press(
        tester,
        LogicalKeyboardKey.keyS,
        modifier: LogicalKeyboardKey.controlLeft,
      );
      expect(cancels, 0);
      expect(saves, isEmpty);

      await press(tester, LogicalKeyboardKey.f2);
      await tester.pump();
      expect(saves, ['new']);

      await tester.tap(find.byKey(LazyTextFieldKeys.staticSurface('cell')));
      await tester.pump();
      await tester.pump();
      await press(tester, LogicalKeyboardKey.f3);
      expect(cancels, 1);
      expect(isEditing(), isFalse);
    });
  });
}
