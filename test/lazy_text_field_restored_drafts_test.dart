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

LazyTextFieldDraftId _id(String id) =>
    LazyTextFieldDraftId(table: 'tasks', row: id, field: 'text');

void main() {
  late List<String> commits;
  late LazyTextFieldEditController controller;

  setUp(() => commits = []);

  /// An immediate-mode controller with a draft for 'a' restored from the
  /// store, as after an app restart.
  Future<void> restore() async {
    final store = LazyTextFieldMemoryDraftStore()
      ..put(
        LazyTextFieldStoredDraft(
          id: _id('a'),
          value: 'stale-a',
          baseText: 'old-a',
          baseVersion: 'v1',
        ),
      );
    controller = LazyTextFieldEditController(draftStore: store);
    addTearDown(controller.dispose);
    expect(await controller.loadDrafts(), 1);
  }

  Future<void> pumpCells(
    WidgetTester tester, {
    List<String> ids = const ['a', 'b'],
  }) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: LazyTextFieldScope(
            controller: controller,
            child: Column(
              children: [
                for (final id in ids)
                  SizedBox(
                    width: 200,
                    child: ScopedLazyTextField(
                      cellId: id,
                      draftKey: _id(id),
                      version: 'v1',
                      text: 'server-$id',
                      singleLine: true,
                      style: _style,
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        isCollapsed: true,
                        contentPadding: EdgeInsets.all(4),
                      ),
                      onCommit: (value) async => commits.add('$id=$value'),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  Future<void> open(WidgetTester tester, String id) async {
    await tester.tap(find.byKey(LazyTextFieldKeys.staticSurface(id)));
    await tester.pump();
    await tester.pump();
  }

  LazyTextFieldDraft? draftA() => controller.draftFor(_id('a'));

  testWidgets('loadDrafts marks drafts as restored', (tester) async {
    await restore();
    expect(draftA()!.restored, isTrue);
    expect(draftA()!.status, LazyTextFieldDraftStatus.unsaved);
  });

  testWidgets('a restored draft is not saved when another cell starts '
      'editing', (tester) async {
    await restore();
    await pumpCells(tester);
    await open(tester, 'b');
    await tester.pump();

    expect(commits, isEmpty);
    expect(draftA()!.restored, isTrue);
    expect(draftA()!.status, LazyTextFieldDraftStatus.unsaved);
  });

  testWidgets('saveDrafts saves a restored draft', (tester) async {
    await restore();
    await pumpCells(tester);

    final result = await controller.saveDrafts();
    expect(result.saved, 1);
    expect(commits, ['a=stale-a']);
  });

  testWidgets('committing a restored draft from its cell saves it', (
    tester,
  ) async {
    await restore();
    await pumpCells(tester);
    await open(tester, 'a');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    await tester.pump();

    expect(commits, ['a=stale-a']);
    expect(draftA()?.restored ?? false, isFalse);
  });

  testWidgets('a restored draft kept unchanged when its cell leaves the tree '
      'stays restored', (tester) async {
    await restore();
    await pumpCells(tester);
    await open(tester, 'a');
    await pumpCells(tester, ids: ['b']);
    expect(draftA()!.restored, isTrue);

    await open(tester, 'b');
    await tester.pump();
    expect(commits, isEmpty);
  });

  testWidgets('a restored draft changed before its cell left the tree is '
      'saved on the next switch', (tester) async {
    await restore();
    await pumpCells(tester);
    await open(tester, 'a');
    await tester.enterText(find.byType(EditableText), 'checked-a');
    await pumpCells(tester, ids: ['b']);
    expect(draftA()!.restored, isFalse);

    await open(tester, 'b');
    await tester.pump();
    expect(commits, ['a=checked-a']);
  });
}
