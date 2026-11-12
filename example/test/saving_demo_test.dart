import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lazy_text_field/lazy_text_field.dart';
import 'package:lazy_text_field_example/main_saving_demo.dart';

void main() {
  late MockApi api;

  setUp(() => api = MockApi(rowCount: 40, latency: Duration.zero));

  Future<void> pumpDemo(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(SavingDemoApp(api: api));
  }

  Finder cell(int row, Field field) =>
      find.byKey(LazyTextFieldKeys.root(cellKey(row, field)));

  Future<void> edit(
    WidgetTester tester,
    int row,
    Field field,
    String text,
  ) async {
    await tester.tap(cell(row, field));
    await tester.pump();
    await tester.pump();
    await tester.enterText(
      find.descendant(of: cell(row, field), matching: find.byType(TextField)),
      text,
    );
    await tester.pump();
  }

  LazyTextFieldEditController controllerOf(WidgetTester tester) =>
      LazyTextFieldControllerScope.of(
        tester.element(find.byType(ListView).at(1)),
      );

  LazyTextFieldDraft? draft(WidgetTester tester, int row, Field field) =>
      controllerOf(tester).draftFor(cellKey(row, field));

  /// Scrolls like a mouse wheel: unlike a drag, it is not a tap outside the
  /// editor, so it does not submit it.
  Future<void> scrollRowsTo(WidgetTester tester, {required bool end}) async {
    final list = find.ancestor(
      of: find.byType(ScopedLazyTextField).first,
      matching: find.byType(Scrollable),
    );
    final position = tester.state<ScrollableState>(list.first).position;
    position.jumpTo(end ? position.maxScrollExtent : 0);
    await tester.pump();
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 10));
    }
  }

  testWidgets('Enter saves a title through the mock API', (tester) async {
    await pumpDemo(tester);

    await edit(tester, 1, Field.title, 'Renamed');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await settle(tester);

    expect(api.fetchAll().first.title, 'Renamed');
    expect(find.text('v2'), findsOneWidget);
    expect(
      find.descendant(
        of: cell(1, Field.title),
        matching: find.byType(TextField),
      ),
      findsNothing,
    );
  });

  testWidgets('a failed save keeps the text as a failed draft', (tester) async {
    api.failure = ApiFailure.all;
    await pumpDemo(tester);

    await edit(tester, 1, Field.title, 'Rejected');
    // Switching cells commits the first one in the background.
    await tester.tap(cell(2, Field.title));
    await settle(tester);

    expect(api.fetchAll().first.title, 'Task 1');
    expect(find.byIcon(Icons.error_outline), findsOneWidget);
    final failed = draft(tester, 1, Field.title)!;
    expect(failed.status, LazyTextFieldDraftStatus.failed);
    expect(failed.value, 'Rejected');
  });

  testWidgets('an unmounted editor becomes an unsaved draft; Save all '
      'saves it', (tester) async {
    await pumpDemo(tester);

    await edit(tester, 1, Field.note, 'Typed, then scrolled away');
    await scrollRowsTo(tester, end: true);
    await settle(tester);
    expect(cell(1, Field.note), findsNothing);
    expect(
      draft(tester, 1, Field.note)?.status,
      LazyTextFieldDraftStatus.unsaved,
    );
    expect(find.textContaining('1 unsaved'), findsOneWidget);

    await tester.tap(find.text('Save all'));
    await settle(tester);

    expect(api.fetchAll().first.note, 'Typed, then scrolled away');
    expect(find.textContaining('0 unsaved'), findsOneWidget);
    expect(find.text('v2'), findsNothing); // row 1 is scrolled away
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('Restart keeps open text through the draft store', (
    tester,
  ) async {
    await pumpDemo(tester);

    await edit(tester, 3, Field.title, 'Survives restart');
    // Unmount the editor: tapping Restart while it is open would submit it.
    await scrollRowsTo(tester, end: true);
    await scrollRowsTo(tester, end: false);
    await tester.tap(find.text('Restart (new controller)'));
    await settle(tester);

    final restored = draft(tester, 3, Field.title)!;
    expect(restored.status, LazyTextFieldDraftStatus.unsaved);
    expect(restored.value, 'Survives restart');
    expect(find.byIcon(Icons.edit_note), findsOneWidget);
    expect(api.fetchAll()[2].title, 'Task 3');
  });
}
