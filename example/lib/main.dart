import 'package:lazy_text_field/lazy_text_field.dart';
import 'package:flutter/material.dart';

void main() {
  runApp(const LazyTextFieldExampleApp());
}

class LazyTextFieldExampleApp extends StatelessWidget {
  const LazyTextFieldExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff0f766e)),
        useMaterial3: true,
      ),
      home: const LazyTextFieldExampleScreen(),
    );
  }
}

class LazyTextFieldExampleScreen extends StatefulWidget {
  const LazyTextFieldExampleScreen({super.key});

  @override
  State<LazyTextFieldExampleScreen> createState() =>
      _LazyTextFieldExampleScreenState();
}

class _LazyTextFieldExampleScreenState
    extends State<LazyTextFieldExampleScreen> {
  static const _rowCount = 1000;

  final _values = List<String>.generate(_rowCount, (index) {
    if (index % 17 == 0) {
      return 'Needs review\nSecond line wraps at constrained widths\nRow $index';
    }
    if (index % 9 == 0) {
      return 'A longer value that should wrap when the column is narrow. Row $index';
    }
    if (index % 5 == 0) {
      return '';
    }
    return 'Value $index';
  });

  String? _activeCellId;
  TextEditingController? _controller;
  FocusNode? _focusNode;
  LazyInputDecorationVisibility _visibility =
      LazyInputDecorationVisibility.editing;
  bool _boundedHeight = false;
  bool _showIcons = true;

  @override
  void dispose() {
    _controller?.dispose();
    _focusNode?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final activeIndex = _activeCellId == null
        ? null
        : int.tryParse(_activeCellId!.split('-').last);

    return Scaffold(
      appBar: AppBar(
        title: const Text('LazyTextField visual test'),
        actions: [
          IconButton(
            tooltip: 'Clear active editor',
            icon: const Icon(Icons.close),
            onPressed: _stopEditing,
          ),
        ],
      ),
      body: Column(
        children: [
          _Toolbar(
            visibility: _visibility,
            boundedHeight: _boundedHeight,
            showIcons: _showIcons,
            activeIndex: activeIndex,
            onVisibilityChanged: (value) {
              setState(() {
                _visibility = value;
              });
            },
            onBoundedHeightChanged: (value) {
              setState(() {
                _boundedHeight = value;
              });
            },
            onShowIconsChanged: (value) {
              setState(() {
                _showIcons = value;
              });
            },
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _values.length,
              itemBuilder: (context, index) {
                final cellId = 'row-$index';
                final isEditing = _activeCellId == cellId;
                final field = LazyTextField(
                  cellId: cellId,
                  text: _values[index],
                  isEditing: isEditing,
                  controller: isEditing ? _controller : null,
                  focusNode: isEditing ? _focusNode : null,
                  style: const TextStyle(fontSize: 14, height: 1.25),
                  decoration: _decoration(context, index),
                  decorationVisibility: _visibility,
                  maxHeight: _boundedHeight ? 64 : null,
                  onStartEditing: () => _startEditing(cellId, index),
                  onChanged: (value) {
                    _values[index] = value;
                  },
                  onSubmitted: (_) => _stopEditing(),
                  onTapOutside: (_) => _stopEditing(),
                );

                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 72,
                        child: Text(
                          '#$index',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                      SizedBox(
                        width: 280,
                        child: _boundedHeight
                            ? SizedBox(height: 64, child: field)
                            : field,
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Text(
                          _values[index].isEmpty
                              ? 'empty value'
                              : _values[index],
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  LazyInputDecoration _decoration(BuildContext context, int index) {
    final colorScheme = Theme.of(context).colorScheme;
    final borderRadius = BorderRadius.circular(4);
    final normalBorder = OutlineInputBorder(
      borderRadius: borderRadius,
      borderSide: BorderSide(color: colorScheme.outlineVariant),
    );
    final focusedBorder = OutlineInputBorder(
      borderRadius: borderRadius,
      borderSide: BorderSide(color: colorScheme.primary, width: 2),
    );
    final errorBorder = OutlineInputBorder(
      borderRadius: borderRadius,
      borderSide: BorderSide(color: colorScheme.error),
    );

    return LazyInputDecoration(
      filled: true,
      fillColor: colorScheme.surface,
      hoverColor: colorScheme.secondaryContainer.withValues(alpha: 0.35),
      focusColor: colorScheme.primaryContainer.withValues(alpha: 0.35),
      border: normalBorder,
      enabledBorder: normalBorder,
      focusedBorder: focusedBorder,
      errorBorder: errorBorder,
      focusedErrorBorder: errorBorder,
      errorText: index % 23 == 0 ? 'visual error' : null,
      hintText: 'Click to edit',
      hintStyle: TextStyle(color: colorScheme.onSurfaceVariant),
      prefixIcon: _showIcons ? const Icon(Icons.notes, size: 16) : null,
      prefixIconConstraints: const BoxConstraints(minWidth: 28),
      suffixIcon: !_showIcons ? const Icon(Icons.edit, size: 16) : null,
      suffixIconConstraints: const BoxConstraints(minWidth: 28),
    );
  }

  void _startEditing(String cellId, int index) {
    if (_activeCellId == cellId) return;
    _controller?.dispose();
    _focusNode?.dispose();
    setState(() {
      _activeCellId = cellId;
      _controller = TextEditingController(text: _values[index]);
      _focusNode = FocusNode();
      _controller!.selection = TextSelection.collapsed(
        offset: _controller!.text.length,
      );
    });
  }

  void _stopEditing() {
    if (_activeCellId == null) return;
    setState(() {
      _activeCellId = null;
      _controller?.dispose();
      _focusNode?.dispose();
      _controller = null;
      _focusNode = null;
    });
  }
}

class _Toolbar extends StatelessWidget {
  const _Toolbar({
    required this.visibility,
    required this.boundedHeight,
    required this.showIcons,
    required this.activeIndex,
    required this.onVisibilityChanged,
    required this.onBoundedHeightChanged,
    required this.onShowIconsChanged,
  });

  final LazyInputDecorationVisibility visibility;
  final bool boundedHeight;
  final bool showIcons;
  final int? activeIndex;
  final ValueChanged<LazyInputDecorationVisibility> onVisibilityChanged;
  final ValueChanged<bool> onBoundedHeightChanged;
  final ValueChanged<bool> onShowIconsChanged;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Wrap(
          spacing: 16,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SegmentedButton<LazyInputDecorationVisibility>(
              segments: const [
                ButtonSegment(
                  value: LazyInputDecorationVisibility.editing,
                  icon: Icon(Icons.edit),
                  label: Text('Edit'),
                ),
                ButtonSegment(
                  value: LazyInputDecorationVisibility.always,
                  icon: Icon(Icons.visibility),
                  label: Text('Always'),
                ),
                ButtonSegment(
                  value: LazyInputDecorationVisibility.never,
                  icon: Icon(Icons.visibility_off),
                  label: Text('None'),
                ),
              ],
              selected: {visibility},
              onSelectionChanged: (selection) {
                onVisibilityChanged(selection.single);
              },
            ),
            FilterChip(
              avatar: const Icon(Icons.height, size: 18),
              label: const Text('Bounded height'),
              selected: boundedHeight,
              onSelected: onBoundedHeightChanged,
            ),
            FilterChip(
              avatar: const Icon(Icons.dashboard_customize, size: 18),
              label: const Text('Icons'),
              selected: showIcons,
              onSelected: onShowIconsChanged,
            ),
            Text(
              activeIndex == null
                  ? 'No active controller'
                  : 'Active controller: row $activeIndex',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
