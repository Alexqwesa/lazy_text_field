import 'package:flutter/material.dart';
import 'package:lazy_text_field/lazy_text_field.dart';

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
  static const _rowCount = 18;
  static const _rowNumberWidth = 56.0;
  static const _taskWidth = 280.0;
  static const _ownerWidth = 180.0;
  static const _statusWidth = 168.0;
  static const _notesWidth = 360.0;
  static const _rowGap = 10.0;
  static const _fieldHeight = 58.0;
  static const _rowPadding = 8.0;

  final _rows = List<_DemoRow>.generate(_rowCount, (index) {
    final owners = ['Ari', 'Mina', 'Noah', 'Kai', 'Lena', 'Sam'];
    final statuses = ['Draft', 'Ready', 'Blocked', 'Review', 'Shipped'];

    return _DemoRow(
      task: index % 6 == 0
          ? 'Long wrapped title for row $index'
          : 'Update cell $index',
      owner: owners[index % owners.length],
      status: statuses[index % statuses.length],
      notes: switch (index % 5) {
        0 => 'Two-line note\nkeeps the same position in edit mode.',
        1 => 'Click this lazy field to edit.',
        2 => '',
        3 => 'Narrow columns wrap without row-height surprises.',
        _ => 'Decoration stays outside the real TextField.',
      },
    );
  });

  String? _activeCellId;
  TextEditingController? _controller;
  FocusNode? _focusNode;
  final _horizontalScrollController = ScrollController();
  LazyInputDecorationVisibility _visibility =
      LazyInputDecorationVisibility.always;
  _HeightMode _heightMode = _HeightMode.fixed;
  bool _showIcons = true;

  @override
  void dispose() {
    _controller?.dispose();
    _focusNode?.dispose();
    _horizontalScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final activeLabel = _activeCellId == null
        ? 'No active controller'
        : 'Active controller: $_activeCellId';

    return Scaffold(
      appBar: AppBar(
        title: const Text('LazyTextField demo'),
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
            heightMode: _heightMode,
            showIcons: _showIcons,
            activeLabel: activeLabel,
            onVisibilityChanged: (value) {
              setState(() {
                _visibility = value;
              });
            },
            onHeightModeChanged: (value) {
              setState(() {
                _heightMode = value;
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
            child: Scrollbar(
              controller: _horizontalScrollController,
              thumbVisibility: true,
              child: SingleChildScrollView(
                controller: _horizontalScrollController,
                padding: const EdgeInsets.all(16),
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  width:
                      _rowNumberWidth +
                      _taskWidth +
                      _ownerWidth +
                      _statusWidth +
                      _notesWidth +
                      _rowGap * 4 +
                      _rowPadding * 2,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const _HeaderRow(),
                      const SizedBox(height: 8),
                      Expanded(
                        child: ListView.separated(
                          itemCount: _rows.length,
                          separatorBuilder: (context, index) =>
                              const SizedBox(height: 8),
                          itemBuilder: _buildRow,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRow(BuildContext context, int rowIndex) {
    final colorScheme = Theme.of(context).colorScheme;
    final row = _rows[rowIndex];

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border.all(color: colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Padding(
        padding: const EdgeInsets.all(_rowPadding),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: _rowNumberWidth,
              height: _fieldHeight,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '#${rowIndex + 1}',
                  style: Theme.of(context).textTheme.labelMedium,
                ),
              ),
            ),
            const SizedBox(width: _rowGap),
            _FieldCell(
              width: _taskWidth,
              value: row.task,
              child: _lazyField(rowIndex, _DemoColumn.task, row.task),
            ),
            const SizedBox(width: _rowGap),
            _FieldCell(
              width: _ownerWidth,
              value: row.owner,
              child: _lazyField(rowIndex, _DemoColumn.owner, row.owner),
            ),
            const SizedBox(width: _rowGap),
            _FieldCell(
              width: _statusWidth,
              value: row.status,
              child: _lazyField(rowIndex, _DemoColumn.status, row.status),
            ),
            const SizedBox(width: _rowGap),
            _FieldCell(
              width: _notesWidth,
              value: row.notes,
              child: _lazyField(rowIndex, _DemoColumn.notes, row.notes),
            ),
          ],
        ),
      ),
    );
  }

  Widget _lazyField(int rowIndex, _DemoColumn column, String value) {
    final cellId = 'r${rowIndex + 1}-${column.name}';
    final isEditing = _activeCellId == cellId;
    final isFixedHeight =
        _heightMode == _HeightMode.fixed ||
        (_heightMode == _HeightMode.onEditFull && !isEditing);
    final field = LazyTextField(
      cellId: cellId,
      text: value,
      isEditing: isEditing,
      controller: isEditing ? _controller : null,
      focusNode: isEditing ? _focusNode : null,
      style: const TextStyle(fontSize: 14, height: 1.25),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: _decoration(context, column),
      decorationVisibility: _visibility,
      maxHeight: isFixedHeight ? _fieldHeight : null,
      onStartEditing: () => _startEditing(cellId, value),
      onChanged: (nextValue) {
        setState(() {
          _setCellValue(rowIndex, column, nextValue);
        });
      },
      onSubmitted: (_) => _stopEditing(),
      onTapOutside: (_) => _stopEditing(),
    );

    if (!isFixedHeight) {
      return field;
    }

    return SizedBox(height: _fieldHeight, child: field);
  }

  LazyInputDecoration _decoration(BuildContext context, _DemoColumn column) {
    final colorScheme = Theme.of(context).colorScheme;
    final borderRadius = BorderRadius.circular(4);
    final normalBorder = OutlineInputBorder(
      borderRadius: borderRadius,
      borderSide: BorderSide(color: colorScheme.outline, width: 1.2),
    );
    final focusedBorder = OutlineInputBorder(
      borderRadius: borderRadius,
      borderSide: BorderSide(color: colorScheme.primary, width: 2),
    );

    return LazyInputDecoration(
      filled: true,
      fillColor: colorScheme.surfaceContainerLowest,
      hoverColor: colorScheme.secondaryContainer.withValues(alpha: 0.35),
      focusColor: colorScheme.primaryContainer.withValues(alpha: 0.35),
      border: normalBorder,
      enabledBorder: normalBorder,
      focusedBorder: focusedBorder,
      hintText: 'Click to edit',
      hintStyle: TextStyle(color: colorScheme.onSurfaceVariant),
      prefixIcon: _showIcons ? Icon(column.icon, size: 16) : null,
      prefixIconConstraints: const BoxConstraints(minWidth: 30),
    );
  }

  void _startEditing(String cellId, String value) {
    if (_activeCellId == cellId) return;
    _controller?.dispose();
    _focusNode?.dispose();
    setState(() {
      _activeCellId = cellId;
      _controller = TextEditingController(text: value);
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

  void _setCellValue(int rowIndex, _DemoColumn column, String value) {
    final row = _rows[rowIndex];
    switch (column) {
      case _DemoColumn.task:
        row.task = value;
      case _DemoColumn.owner:
        row.owner = value;
      case _DemoColumn.status:
        row.status = value;
      case _DemoColumn.notes:
        row.notes = value;
    }
  }
}

class _Toolbar extends StatelessWidget {
  const _Toolbar({
    required this.visibility,
    required this.heightMode,
    required this.showIcons,
    required this.activeLabel,
    required this.onVisibilityChanged,
    required this.onHeightModeChanged,
    required this.onShowIconsChanged,
  });

  final LazyInputDecorationVisibility visibility;
  final _HeightMode heightMode;
  final bool showIcons;
  final String activeLabel;
  final ValueChanged<LazyInputDecorationVisibility> onVisibilityChanged;
  final ValueChanged<_HeightMode> onHeightModeChanged;
  final ValueChanged<bool> onShowIconsChanged;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Wrap(
          spacing: 12,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 320,
              child: SegmentedButton<LazyInputDecorationVisibility>(
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
            ),
            SizedBox(
              width: 392,
              child: SegmentedButton<_HeightMode>(
                segments: const [
                  ButtonSegment(
                    value: _HeightMode.fixed,
                    icon: Icon(Icons.height),
                    label: Text('Fixed'),
                  ),
                  ButtonSegment(
                    value: _HeightMode.full,
                    icon: Icon(Icons.open_in_full),
                    label: Text('Full'),
                  ),
                  ButtonSegment(
                    value: _HeightMode.onEditFull,
                    icon: Icon(Icons.edit_note),
                    label: Text('Edit full'),
                  ),
                ],
                selected: {heightMode},
                onSelectionChanged: (selection) {
                  onHeightModeChanged(selection.single);
                },
              ),
            ),
            SizedBox(
              width: 112,
              child: FilterChip(
                avatar: const Icon(Icons.dashboard_customize, size: 18),
                label: const Text('Icons'),
                selected: showIcons,
                onSelected: onShowIconsChanged,
              ),
            ),
            SizedBox(
              width: 260,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  activeLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeaderRow extends StatelessWidget {
  const _HeaderRow();

  @override
  Widget build(BuildContext context) {
    final textStyle = Theme.of(context).textTheme.labelLarge;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: _LazyWidths.rowPadding),
      child: Row(
        children: [
          _HeaderCell(
            width: _LazyWidths.rowNumber,
            label: 'Row',
            style: textStyle,
          ),
          const SizedBox(width: _LazyWidths.gap),
          _HeaderCell(width: _LazyWidths.task, label: 'Task', style: textStyle),
          const SizedBox(width: _LazyWidths.gap),
          _HeaderCell(
            width: _LazyWidths.owner,
            label: 'Owner',
            style: textStyle,
          ),
          const SizedBox(width: _LazyWidths.gap),
          _HeaderCell(
            width: _LazyWidths.status,
            label: 'Status',
            style: textStyle,
          ),
          const SizedBox(width: _LazyWidths.gap),
          _HeaderCell(
            width: _LazyWidths.notes,
            label: 'Notes',
            style: textStyle,
          ),
        ],
      ),
    );
  }
}

class _HeaderCell extends StatelessWidget {
  const _HeaderCell({
    required this.width,
    required this.label,
    required this.style,
  });

  final double width;
  final String label;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(label, style: style),
      ),
    );
  }
}

class _FieldCell extends StatelessWidget {
  const _FieldCell({
    required this.width,
    required this.child,
    required this.value,
  });

  final double width;
  final Widget child;
  final String value;

  @override
  Widget build(BuildContext context) {
    final tooltipValue = value.isEmpty ? '(empty)' : value;

    return SizedBox(
      width: width,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: child),
          const SizedBox(width: 4),
          SizedBox(
            width: 28,
            height: _LazyWidths.fieldHeight,
            child: Tooltip(
              message: 'LazyTextField value:\n$tooltipValue',
              waitDuration: const Duration(milliseconds: 250),
              child: Icon(
                Icons.info_outline,
                size: 18,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DemoRow {
  _DemoRow({
    required this.task,
    required this.owner,
    required this.status,
    required this.notes,
  });

  String task;
  String owner;
  String status;
  String notes;
}

enum _DemoColumn {
  task(Icons.subject),
  owner(Icons.person_outline),
  status(Icons.flag_outlined),
  notes(Icons.notes);

  const _DemoColumn(this.icon);

  final IconData icon;
}

enum _HeightMode { fixed, full, onEditFull }

abstract final class _LazyWidths {
  static const rowNumber = _LazyTextFieldExampleScreenState._rowNumberWidth;
  static const task = _LazyTextFieldExampleScreenState._taskWidth;
  static const owner = _LazyTextFieldExampleScreenState._ownerWidth;
  static const status = _LazyTextFieldExampleScreenState._statusWidth;
  static const notes = _LazyTextFieldExampleScreenState._notesWidth;
  static const gap = _LazyTextFieldExampleScreenState._rowGap;
  static const fieldHeight = _LazyTextFieldExampleScreenState._fieldHeight;
  static const rowPadding = _LazyTextFieldExampleScreenState._rowPadding;
}
