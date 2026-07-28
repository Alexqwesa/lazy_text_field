import 'package:flutter/material.dart';
import 'package:lazy_text_field/lazy_text_field.dart';

void main() {
  runApp(const SmallLazyTextFieldExample());
}

class SmallLazyTextFieldExample extends StatefulWidget {
  const SmallLazyTextFieldExample({super.key});

  @override
  State<SmallLazyTextFieldExample> createState() =>
      _SmallLazyTextFieldExampleState();
}

class _SmallLazyTextFieldExampleState extends State<SmallLazyTextFieldExample> {
  String _value = 'Click to edit this lazy field.';

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true),
      home: Scaffold(
        appBar: AppBar(title: const Text('lazy_text_field')),
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: SizedBox(
            width: 320,
            child: StatefulLazyTextField(
              cellId: 'example-cell',
              text: _value,
              style: const TextStyle(fontSize: 16, height: 1.3),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: const LazyInputDecoration(
                border: OutlineInputBorder(),
                hintText: 'Add a note',
              ),
              decorationVisibility: LazyInputDecorationVisibility.always,
              onSave: (value) {
                setState(() {
                  _value = value;
                });
                return true;
              },
            ),
          ),
        ),
      ),
    );
  }
}
