import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lazy_text_field/lazy_text_field.dart';

/// P0: unsupported error slots + layout-stable [LazyTextField.errorMessage].
void main() {
  const style = TextStyle(
    fontFamily: 'Ahem',
    fontSize: 14,
    height: 1,
    letterSpacing: 0,
  );

  group('isDecorationLayoutStable', () {
    test('accepts null and common supported slots', () {
      expect(LazyTextField.isDecorationLayoutStable(null), isTrue);
      expect(
        LazyTextField.isDecorationLayoutStable(const InputDecoration()),
        isTrue,
      );
      expect(
        LazyTextField.isDecorationLayoutStable(
          const InputDecoration(
            filled: true,
            border: OutlineInputBorder(),
            labelText: 'Label',
            hintText: 'Hint',
            helperText: 'Helper',
            counterText: '1/10',
            prefixIcon: Icon(Icons.search),
            suffixText: 'kg',
            contentPadding: EdgeInsets.all(8),
            isDense: true,
          ),
        ),
        isTrue,
      );
    });

    test('rejects any non-null errorText, including empty', () {
      expect(
        LazyTextField.isDecorationLayoutStable(
          const InputDecoration(errorText: 'Invalid'),
        ),
        isFalse,
      );
      expect(
        LazyTextField.isDecorationLayoutStable(
          const InputDecoration(errorText: ''),
        ),
        isFalse,
        reason: 'empty errorText must not bypass the unsupported-slot policy',
      );
    });

    test('rejects InputDecoration.error widget', () {
      expect(
        LazyTextField.isDecorationLayoutStable(
          InputDecoration(error: const Text('Invalid')),
        ),
        isFalse,
      );
    });
  });

  group('debug assert + strip', () {
    testWidgets('nonempty errorText asserts in debug', (tester) async {
      await tester.pumpWidget(
        _App(
          child: LazyTextField(
            cellId: 'err-text',
            text: 'value',
            isEditing: false,
            style: style,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              errorText: 'Invalid',
            ),
            onStartEditing: () {},
          ),
        ),
      );

      final exception = tester.takeException();
      expect(exception, isA<AssertionError>());
      expect('$exception', contains('layout-unstable'));
      expect('$exception', contains('errorText'));
    });

    testWidgets('empty errorText asserts in debug', (tester) async {
      await tester.pumpWidget(
        _App(
          child: LazyTextField(
            cellId: 'err-empty',
            text: 'value',
            isEditing: false,
            style: style,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              errorText: '',
            ),
            onStartEditing: () {},
          ),
        ),
      );

      final exception = tester.takeException();
      expect(exception, isA<AssertionError>());
      expect('$exception', contains('layout-unstable'));
    });

    testWidgets('InputDecoration.error asserts in debug', (tester) async {
      await tester.pumpWidget(
        _App(
          child: LazyTextField(
            cellId: 'err-widget',
            text: 'value',
            isEditing: false,
            style: style,
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              error: const Text('Invalid'),
            ),
            onStartEditing: () {},
          ),
        ),
      );

      final exception = tester.takeException();
      expect(exception, isA<AssertionError>());
      expect('$exception', contains('layout-unstable'));
    });
  });

  group('errorMessage overlay', () {
    testWidgets('show/clear does not change field geometry', (tester) async {
      String? error;

      Future<void> pump() {
        return tester.pumpWidget(
          _App(
            child: StatefulLazyTextField(
              cellId: 'overlay',
              text: '1',
              style: style,
              errorMessage: error,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                helperText: 'Units',
                contentPadding: EdgeInsets.all(8),
              ),
              onSave: (_) => true,
            ),
          ),
        );
      }

      await pump();
      final root = find.byKey(LazyTextFieldKeys.root('overlay'));
      final viewport = find.byKey(LazyTextFieldKeys.textViewport('overlay'));
      final rootBefore = tester.getRect(root);
      final viewportBefore = tester.getRect(viewport);

      error = 'Must be positive';
      await pump();
      await tester.pump();

      expect(find.byKey(LazyTextFieldKeys.errorPopup('overlay')), findsOneWidget);
      expect(tester.getRect(root), rootBefore);
      expect(tester.getRect(viewport), viewportBefore);

      final decorator = tester.widget<InputDecorator>(
        find.byType(InputDecorator),
      );
      expect(decorator.decoration.errorText, isNull);
      expect(decorator.decoration.error, isNull);

      error = null;
      await pump();
      await tester.pump();
      expect(find.byKey(LazyTextFieldKeys.errorPopup('overlay')), findsNothing);
      expect(tester.getRect(root), rootBefore);
      expect(tester.getRect(viewport), viewportBefore);
    });
  });

  group('maxLength must not inject errorText', () {
    testWidgets(
      'over-limit value with helper/counter keeps decorator error-free',
      (tester) async {
        final controller = TextEditingController(text: 'abcdef');
        final focusNode = FocusNode();
        addTearDown(controller.dispose);
        addTearDown(focusNode.dispose);

        await tester.pumpWidget(
          _App(
            child: SizedBox(
              width: 240,
              child: LazyTextField(
                cellId: 'maxlen',
                text: controller.text,
                isEditing: true,
                controller: controller,
                focusNode: focusNode,
                style: style,
                maxLength: 3,
                maxLengthEnforcement: MaxLengthEnforcement.none,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  helperText: 'Helper stays',
                  contentPadding: EdgeInsets.all(8),
                ),
                onStartEditing: () {},
              ),
            ),
          ),
        );
        await tester.pump();

        final decorator = tester.widget<InputDecorator>(
          find.byType(InputDecorator),
        );
        expect(
          decorator.decoration.errorText,
          isNull,
          reason:
              'over-maxLength must not inject errorText; that breaks the '
              'no-layout-jump promise',
        );
        expect(decorator.decoration.error, isNull);
        expect(decorator.decoration.helperText, 'Helper stays');
        expect(decorator.decoration.counterText, isNotNull);
      },
    );
  });
}

class _App extends StatelessWidget {
  const _App({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Center(child: SizedBox(width: 240, child: child)),
      ),
    );
  }
}
