// lazy_text_field example: ScopedLazyTextField cells in a ListView that
// unmounts them, saved through a LazyTextFieldEditController to a mock API
// that can be slow or fail. Switches cover the save options, the cell
// heights, and the text style.
//
//   flutter run -d chrome
//
// lib/main_simple.dart has a single StatefulLazyTextField.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:lazy_text_field/lazy_text_field.dart';

void main() {
  runApp(const SavingDemoApp());
}

class SavingDemoApp extends StatelessWidget {
  const SavingDemoApp({super.key, this.api});

  /// Mock API to use; tests pass one with no latency.
  final MockApi? api;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'lazy_text_field example',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff0f766e)),
        useMaterial3: true,
      ),
      home: SavingDemoScreen(api: api),
    );
  }
}

// ---------------------------------------------------------------------------
// Mock API
// ---------------------------------------------------------------------------

/// Which mock API calls fail.
enum ApiFailure {
  none('None'),
  all('All'),
  everySecond('Every 2nd');

  const ApiFailure(this.label);

  final String label;
}

enum Field { title, note }

class ApiException implements Exception {
  const ApiException(this.message);

  final String message;

  @override
  String toString() => message;
}

class ApiRow {
  ApiRow({
    required this.id,
    required this.title,
    required this.note,
    this.version = 1,
  });

  final int id;
  String title;
  String note;
  int version;

  ApiRow copy() => ApiRow(id: id, title: title, note: note, version: version);

  String valueOf(Field field) => switch (field) {
    Field.title => title,
    Field.note => note,
  };

  void set(Field field, String value) {
    switch (field) {
      case Field.title:
        title = value;
      case Field.note:
        note = value;
    }
  }
}

/// A fake server: every call waits [latency], then fails or applies the
/// change according to [failure].
class MockApi extends ChangeNotifier {
  MockApi({
    int rowCount = 100,
    this.latency = const Duration(milliseconds: 800),
  }) : _rows = [
         for (var id = 1; id <= rowCount; id++)
           ApiRow(id: id, title: _seedTitle(id), note: _seedNote(id)),
       ];

  final List<ApiRow> _rows;

  ApiFailure failure = ApiFailure.none;
  Duration latency;

  /// Receives one line per request and response.
  void Function(String line)? log;

  int calls = 0;
  int inFlight = 0;
  int maxInFlight = 0;

  static const _titles = [
    'Fix login',
    'Update the onboarding checklist for new hires',
    'Ship 3.0',
    'Review pull request about table virtualization and scrolling',
    'Call Mina',
    'Write release notes',
    '',
    'Migrate the data table to lazy cells so long reports stay fast',
    'Plan Q1',
    'Check invoice #',
  ];

  static String _seedTitle(int id) {
    final title = _titles[(id - 1) % _titles.length];
    return title.endsWith('#') ? '$title$id' : title;
  }

  static String _seedNote(int id) => switch (id % 9) {
    1 => 'Line one\nLine two\nLine three\nLine four',
    2 => 'Short note',
    3 => '',
    4 =>
      'A longer note that wraps in a narrow column and gets clipped after '
          'two lines with the overflow marker.',
    5 => 'Plan\nBuild\nVerify\nShip',
    6 => 'Waiting for the server',
    7 => 'Static view\nEdit view\nSame text origin\nStable height',
    8 => '',
    _ =>
      'Native decoration stays stable while the editor mounts, so the '
          'row does not jump when you click it. Try the height modes and '
          'font sizes above.',
  };

  /// GET: a copy of every row (instant).
  List<ApiRow> fetchAll() => [for (final row in _rows) row.copy()];

  /// GET: a copy of one row (instant).
  ApiRow fetchRow(int id) => _rows.firstWhere((row) => row.id == id).copy();

  /// PUT one field of one row.
  Future<void> update(int id, Field field, String value) async {
    final call = _begin('PUT row $id ${field.name} = "${_short(value)}"');
    try {
      await Future<void>.delayed(latency);
      _check(call);
      final row = _rows.firstWhere((row) => row.id == id);
      row
        ..set(field, value)
        ..version += 1;
      log?.call('#$call ok: row $id is v${row.version}');
    } finally {
      _end();
    }
  }

  /// One request that saves many fields; [values] are keyed by
  /// [cellKey]. Returns errors by key (none: the whole batch fails or
  /// succeeds).
  Future<Map<Object, Object?>> updateBatch(Map<Object, String> values) async {
    final call = _begin('PATCH batch of ${values.length} fields');
    try {
      await Future<void>.delayed(latency);
      _check(call);
      for (final MapEntry(:key, :value) in values.entries) {
        final (id, field) = parseCellKey(key as String);
        _rows.firstWhere((row) => row.id == id)
          ..set(field, value)
          ..version += 1;
      }
      log?.call('#$call ok: ${values.length} fields saved');
      return const {};
    } finally {
      _end();
    }
  }

  int _begin(String request) {
    final call = ++calls;
    inFlight++;
    if (inFlight > maxInFlight) maxInFlight = inFlight;
    log?.call('#$call → $request  (in flight: $inFlight)');
    notifyListeners();
    return call;
  }

  void _check(int call) {
    final fail = switch (failure) {
      ApiFailure.none => false,
      ApiFailure.all => true,
      ApiFailure.everySecond => call.isEven,
    };
    if (fail) {
      log?.call('#$call failed');
      throw ApiException('Server rejected request #$call');
    }
  }

  void _end() {
    inFlight--;
    notifyListeners();
  }

  void resetCounters() {
    maxInFlight = inFlight;
    notifyListeners();
  }

  static String _short(String value) {
    final line = value.replaceAll('\n', '⏎');
    return line.length <= 24 ? line : '${line.substring(0, 24)}…';
  }
}

/// Draft key, cell id, and store key of a cell: unique and stable, as a
/// [LazyTextFieldDraftStore] requires.
String cellKey(int rowId, Field field) => 'row$rowId.${field.name}';

(int, Field) parseCellKey(String key) {
  final [row, field] = key.split('.');
  return (int.parse(row.substring(3)), Field.values.byName(field));
}

// ---------------------------------------------------------------------------
// Demo settings
// ---------------------------------------------------------------------------

/// Which ScopedLazyTextField save callback the cells use.
enum SaveCallback { onCommit, onSave }

class DemoLog extends ChangeNotifier {
  final _clock = Stopwatch()..start();
  final List<String> lines = [];

  void add(String line) {
    final seconds = (_clock.elapsedMilliseconds / 1000).toStringAsFixed(1);
    lines.insert(0, '${seconds.padLeft(6)}s  $line');
    if (lines.length > 300) lines.removeLast();
    notifyListeners();
  }

  void clear() {
    lines.clear();
    notifyListeners();
  }
}

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

class SavingDemoScreen extends StatefulWidget {
  const SavingDemoScreen({super.key, this.api});

  final MockApi? api;

  @override
  State<SavingDemoScreen> createState() => _SavingDemoScreenState();
}

class _SavingDemoScreenState extends State<SavingDemoScreen> {
  static const _labelStyle = TextStyle(fontSize: 14, height: 1.3);
  static const _noteLines = 2;

  final _log = DemoLog();
  late final MockApi _api = (widget.api ?? MockApi())..log = _log.add;

  /// Survives "Restart": stands in for a Hive box or a file.
  final _draftStore = LazyTextFieldMemoryDraftStore();

  late List<ApiRow> _rows = _api.fetchAll();
  late Map<int, int> _indexById = _indexRows(_rows);

  // Controller settings: changing one creates a new controller.
  LazyTextFieldSwitchPolicy _switchPolicy = LazyTextFieldSwitchPolicy.commit;
  LazyTextFieldSaveMode _saveMode = LazyTextFieldSaveMode.immediate;
  LazyTextFieldSaveOrder _saveOrder = LazyTextFieldSaveOrder.sequential;
  bool _persistDrafts = true;

  // Cell settings.
  SaveCallback _saveCallback = SaveCallback.onCommit;
  LazyTextFieldSubmitClose _closeOnSubmit = LazyTextFieldSubmitClose.afterSave;

  // View settings.
  NoteHeight _noteHeight = NoteHeight.editFull;
  LazyTextFieldStartEditSelection _startEditSelection =
      LazyTextFieldStartEditSelection.tapPosition;
  bool _showIcons = true;
  double _fontSize = 14;
  bool _bold = false;
  bool _italic = false;

  /// ListView's default keeps a focused TextField alive after it scrolls
  /// away. Grids that recycle cells do not; off here, so cells unmount.
  bool _keepFocusedEditorAlive = false;

  late LazyTextFieldEditController _controller = _createController();

  /// Bumped on restart, so every cell is disposed with the old controller.
  int _generation = 0;
  bool _restarting = false;
  bool _reloadScheduled = false;

  /// `onSave` returns false on failure, which carries no error; the demo
  /// keeps the message itself.
  final Map<String, String> _onSaveErrors = {};

  @override
  void initState() {
    super.initState();
    _log.add('Click a cell to edit. Scroll an edited row away to unmount it.');
  }

  @override
  void dispose() {
    _controller.dispose();
    _api.log = null;
    if (widget.api == null) _api.dispose();
    _log.dispose();
    super.dispose();
  }

  static Map<int, int> _indexRows(List<ApiRow> rows) => {
    for (var i = 0; i < rows.length; i++) rows[i].id: i,
  };

  LazyTextFieldEditController _createController() {
    return LazyTextFieldEditController(
      switchPolicy: _switchPolicy,
      saveMode: _saveMode,
      saveOrder: _saveOrder,
      draftStore: _persistDrafts ? _draftStore : null,
      onSavesSettled: _onSavesSettled,
    );
  }

  // --- Saving ---------------------------------------------------------------

  Future<void> _commit(int rowId, Field field, String value) {
    // Throws ApiException: the draft becomes failed and keeps the text.
    return _api.update(rowId, field, value);
  }

  Future<bool> _save(int rowId, Field field, String value) async {
    final key = cellKey(rowId, field);
    try {
      await _api.update(rowId, field, value);
      _setOnSaveError(key, null);
      return true;
    } on ApiException catch (error) {
      // false keeps the editor open (or the draft failed after a switch).
      _setOnSaveError(key, error.message);
      return false;
    }
  }

  void _setOnSaveError(String key, String? message) {
    if (_onSaveErrors[key] == message || !mounted) return;
    setState(() {
      if (message == null) {
        _onSaveErrors.remove(key);
      } else {
        _onSaveErrors[key] = message;
      }
    });
  }

  /// Runs after every successful save of a cell, also after it scrolled
  /// away, so it updates the model instead of using the cell's context.
  void _onSaved(int rowId, Field field, String value) {
    _log.add('onSaved ${cellKey(rowId, field)}');
    final index = _indexById[rowId];
    if (index == null || !mounted) return;
    setState(() => _rows[index] = _api.fetchRow(rowId));
  }

  void _onSavesSettled(int saved, int failed) {
    _log.add('Save queue settled: $saved saved, $failed failed');
    unawaited(_reloadWhenIdle());
  }

  /// Fetches fresh rows once nobody edits, so the data under an open editor
  /// is not replaced.
  Future<void> _reloadWhenIdle() async {
    if (_reloadScheduled) return;
    _reloadScheduled = true;
    try {
      final controller = _controller;
      if (controller.activeIds.isNotEmpty) {
        _log.add('Reload waits until editing ends');
      }
      while (controller.activeIds.isNotEmpty) {
        await controller.whenEditingDone();
        if (!mounted || !identical(controller, _controller)) return;
      }
    } finally {
      _reloadScheduled = false;
    }
    if (!mounted) return;
    setState(() {
      _rows = _api.fetchAll();
      _indexById = _indexRows(_rows);
    });
    _log.add('Reloaded ${_rows.length} rows from the server');
  }

  Future<void> _saveAll({required bool batch}) async {
    _log.add(batch ? 'Save all in one request…' : 'Save all…');
    final result = await _controller.saveDrafts(
      batch: batch ? _api.updateBatch : null,
    );
    _log.add('saveDrafts: $result');
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            result.allSaved
                ? 'Everything is saved (${result.saved} drafts).'
                : '${result.saved} saved, ${result.failed} failed, '
                      '${result.remaining} left to save.',
          ),
        ),
      );
  }

  /// Replaces the controller, as an app restart or a settings change would.
  ///
  /// Open editors close when their cells are disposed and keep their text
  /// as unsaved drafts. With the draft store, the new controller loads them
  /// back; without it they are lost.
  Future<void> _restart(String reason, VoidCallback applySettings) async {
    if (_restarting) return;
    setState(() => _restarting = true);
    final old = _controller;
    if (old.pendingSaves > 0) {
      _log.add('$reason: waiting for ${old.pendingSaves} running saves');
      await old.whenSavesSettled();
      if (!mounted) return;
    }
    setState(() {
      applySettings();
      _controller = _createController();
      _generation++;
      _onSaveErrors.clear();
    });
    // The old cells are disposed in this frame and keep their open text in
    // the old controller, which writes it to the store.
    await SchedulerBinding.instance.endOfFrame;
    final kept = old.drafts.values
        .where((draft) => draft.status != LazyTextFieldDraftStatus.saved)
        .length;
    await old.whenDraftsStored();
    old.dispose();
    final restored = await _controller.loadDrafts();
    if (!mounted) return;
    setState(() => _restarting = false);
    _log.add(
      _persistDrafts
          ? '$reason: new controller, $restored drafts loaded from the store'
          : '$reason: new controller, $kept drafts were only in memory and '
                'are lost',
    );
  }

  void _update(VoidCallback apply) => setState(apply);

  void _changeController(String what, VoidCallback apply) {
    unawaited(_restart('Changed $what', apply));
  }

  // --- UI -------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 1100;
    final settings = _SettingsPanel(state: this);
    final log = _LogPanel(log: _log);

    return Scaffold(
      appBar: AppBar(
        title: const Text('lazy_text_field'),
        actions: [
          if (!wide)
            Builder(
              builder: (context) => IconButton(
                tooltip: 'Event log',
                icon: const Icon(Icons.receipt_long),
                onPressed: () => Scaffold.of(context).openEndDrawer(),
              ),
            ),
        ],
      ),
      drawer: wide ? null : Drawer(width: 360, child: settings),
      endDrawer: wide ? null : Drawer(width: 360, child: log),
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (wide) ...[
            SizedBox(width: 340, child: settings),
            const VerticalDivider(width: 1),
          ],
          Expanded(child: _buildMain(context)),
          if (wide) ...[
            const VerticalDivider(width: 1),
            SizedBox(width: 360, child: log),
          ],
        ],
      ),
    );
  }

  Widget _buildMain(BuildContext context) {
    return LazyTextFieldControllerScope(
      controller: _controller,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Toolbar(state: this),
          _ViewControls(state: this),
          _StatusBar(controller: _controller, api: _api, store: _draftStore),
          if (_restarting) const LinearProgressIndicator(minHeight: 2),
          const Divider(height: 1),
          const _Header(),
          const Divider(height: 1),
          Expanded(
            child: ListView.builder(
              // A new generation disposes every cell, as a restart would.
              key: ValueKey(_generation),
              addAutomaticKeepAlives: _keepFocusedEditorAlive,
              itemCount: _rows.length,
              itemBuilder: (context, index) => _buildRow(_rows[index]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRow(ApiRow row) {
    return Padding(
      key: ValueKey(row.id),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 56,
            child: Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text('#${row.id}', style: _labelStyle),
            ),
          ),
          Expanded(flex: 2, child: _buildCell(row, Field.title)),
          const SizedBox(width: 8),
          Expanded(flex: 3, child: _buildCell(row, Field.note)),
          SizedBox(
            width: 48,
            child: Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                'v${row.version}',
                style: _labelStyle,
                textAlign: TextAlign.end,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// The same decoration in both modes: only paint (colors, border width)
  /// may change when editing starts, never the layout.
  InputDecoration _decoration(BuildContext context, Field field) {
    final colors = Theme.of(context).colorScheme;
    final radius = BorderRadius.circular(4);
    final border = OutlineInputBorder(
      borderRadius: radius,
      borderSide: BorderSide(color: colors.outline, width: 1.2),
    );
    return InputDecoration(
      filled: true,
      fillColor: colors.surfaceContainerLowest,
      hoverColor: colors.secondaryContainer.withValues(alpha: 0.35),
      border: border,
      enabledBorder: border,
      focusedBorder: OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide(color: colors.primary, width: 2),
      ),
      hintText: field == Field.note ? 'Add a note' : 'Title',
      hintStyle: TextStyle(color: colors.onSurfaceVariant),
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      prefixIcon: _showIcons
          ? Icon(
              field == Field.note ? Icons.notes : Icons.task_alt,
              size: (_fontSize + 2).clamp(14, 22),
            )
          : null,
      prefixIconConstraints: const BoxConstraints(minWidth: 30),
    );
  }

  Widget _buildCell(ApiRow row, Field field) {
    final key = cellKey(row.id, field);
    final isNote = field == Field.note;
    final style = TextStyle(
      fontSize: _fontSize,
      height: 1.3,
      fontWeight: _bold ? FontWeight.w700 : FontWeight.w400,
      fontStyle: _italic ? FontStyle.italic : FontStyle.normal,
    );
    final twoLines = _fontSize * 1.3 * _noteLines;
    final useCommit = _saveCallback == SaveCallback.onCommit;

    // Depends on the scope, so the onSave error shows only while editing.
    return Builder(
      builder: (context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ScopedLazyTextField(
              cellId: key,
              draftKey: key,
              rowKey: row.id,
              text: row.valueOf(field),
              singleLine: !isNote,
              style: style,
              // Fixed: always two lines, the editor scrolls. Full: the text
              // decides. Edit full: two lines to read, all of it to edit.
              minHeight: isNote && _noteHeight == NoteHeight.fixed
                  ? twoLines
                  : 0,
              maxHeight: isNote && _noteHeight != NoteHeight.full
                  ? twoLines
                  : null,
              editingMaxHeight: isNote && _noteHeight == NoteHeight.editFull
                  ? double.infinity
                  : null,
              startEditSelection: _startEditSelection,
              decoration: _decoration(context, field),
              onCommit: useCommit
                  ? (value) => _commit(row.id, field, value)
                  : null,
              onSave: useCommit ? null : (value) => _save(row.id, field, value),
              closeOnSubmit: _closeOnSubmit,
              errorMessage:
                  !useCommit &&
                      LazyTextFieldControllerScope.of(context).isEditing(key)
                  ? _onSaveErrors[key]
                  : null,
              errorMessageOf: (error) =>
                  error is ApiException ? error.message : 'Save failed: $error',
              onSaved: (value) => _onSaved(row.id, field, value),
              onChanged: (_) {
                if (_onSaveErrors.containsKey(key)) _setOnSaveError(key, null);
              },
              onCancel: () {
                _log.add('Escape in $key');
                _setOnSaveError(key, null);
              },
            ),
          ),
          _DraftBadge(draftKey: key),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelLarge;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          SizedBox(width: 56, child: Text('Row', style: style)),
          Expanded(flex: 2, child: Text('Title (Enter saves)', style: style)),
          const SizedBox(width: 8),
          Expanded(
            flex: 3,
            child: Text('Note (Ctrl+Enter or Ctrl+S saves)', style: style),
          ),
          SizedBox(
            width: 48,
            child: Text('Ver.', style: style, textAlign: TextAlign.end),
          ),
        ],
      ),
    );
  }
}

/// Shows the save state of one cell's draft.
class _DraftBadge extends StatelessWidget {
  const _DraftBadge({required this.draftKey});

  final String draftKey;

  @override
  Widget build(BuildContext context) {
    final draft = LazyTextFieldControllerScope.maybeOf(
      context,
    )?.draftFor(draftKey);
    final colors = Theme.of(context).colorScheme;
    final (icon, color, tooltip) = switch (draft?.status) {
      null => (null, null, ''),
      LazyTextFieldDraftStatus.unsaved => (
        Icons.edit_note,
        colors.tertiary,
        'Unsaved: not sent yet. "Save all" saves it, and so does editing '
            'another cell in immediate mode.',
      ),
      LazyTextFieldDraftStatus.pending => (
        Icons.cloud_upload_outlined,
        colors.primary,
        'Saving…',
      ),
      LazyTextFieldDraftStatus.saved => (
        Icons.cloud_done_outlined,
        Colors.green.shade700,
        'Saved; shown until the data reloads',
      ),
      LazyTextFieldDraftStatus.failed => (
        Icons.error_outline,
        colors.error,
        'Failed: ${draft?.error ?? 'onSave returned false'}. '
            'Reopen to retry, Escape to discard.',
      ),
    };
    return SizedBox(
      width: 28,
      height: 36,
      child: icon == null
          ? null
          : Tooltip(
              message: tooltip,
              child: Icon(icon, size: 18, color: color),
            ),
    );
  }
}

class _Toolbar extends StatelessWidget {
  const _Toolbar({required this.state});

  final _SavingDemoScreenState state;

  @override
  Widget build(BuildContext context) {
    final busy = state._restarting;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          FilledButton.icon(
            onPressed: busy ? null : () => state._saveAll(batch: false),
            icon: const Icon(Icons.save_outlined),
            label: const Text('Save all'),
          ),
          OutlinedButton.icon(
            onPressed: busy ? null : () => state._saveAll(batch: true),
            icon: const Icon(Icons.dynamic_feed_outlined),
            label: const Text('Save all in one request'),
          ),
          OutlinedButton.icon(
            onPressed: busy ? null : () => state._reloadWhenIdle(),
            icon: const Icon(Icons.refresh),
            label: const Text('Reload from server'),
          ),
          OutlinedButton.icon(
            onPressed: busy
                ? null
                : () => unawaited(state._restart('Restart', () {})),
            icon: const Icon(Icons.restart_alt),
            label: const Text('Restart (new controller)'),
          ),
        ],
      ),
    );
  }
}

/// How tall note cells are.
enum NoteHeight { fixed, full, editFull }

enum _TextStyleAction { bold, italic }

/// Layout and text style of the cells.
class _ViewControls extends StatelessWidget {
  const _ViewControls({required this.state});

  static const _fontSizes = <double>[10, 11, 12, 13, 14, 15, 16];

  final _SavingDemoScreenState state;

  @override
  Widget build(BuildContext context) {
    final set = state._update;
    final bold = state._bold;
    final italic = state._italic;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      child: Wrap(
        spacing: 12,
        runSpacing: 12,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Tooltip(
            message: 'Note height: minHeight, maxHeight, editingMaxHeight',
            child: SegmentedButton<NoteHeight>(
              segments: const [
                ButtonSegment(
                  value: NoteHeight.fixed,
                  icon: Icon(Icons.height),
                  label: Text('Fixed'),
                ),
                ButtonSegment(
                  value: NoteHeight.full,
                  icon: Icon(Icons.open_in_full),
                  label: Text('Full'),
                ),
                ButtonSegment(
                  value: NoteHeight.editFull,
                  icon: Icon(Icons.edit_note),
                  label: Text('Edit full'),
                ),
              ],
              selected: {state._noteHeight},
              onSelectionChanged: (selection) =>
                  set(() => state._noteHeight = selection.single),
            ),
          ),
          Tooltip(
            message: 'startEditSelection: where the cursor goes on click',
            child: SegmentedButton<LazyTextFieldStartEditSelection>(
              segments: const [
                ButtonSegment(
                  value: LazyTextFieldStartEditSelection.beginning,
                  icon: Icon(Icons.first_page),
                  label: Text('Begin'),
                ),
                ButtonSegment(
                  value: LazyTextFieldStartEditSelection.end,
                  icon: Icon(Icons.last_page),
                  label: Text('End'),
                ),
                ButtonSegment(
                  value: LazyTextFieldStartEditSelection.tapPosition,
                  icon: Icon(Icons.ads_click),
                  label: Text('Click'),
                ),
                ButtonSegment(
                  value: LazyTextFieldStartEditSelection.fullSelection,
                  icon: Icon(Icons.select_all),
                  label: Text('Select'),
                ),
              ],
              selected: {state._startEditSelection},
              onSelectionChanged: (selection) =>
                  set(() => state._startEditSelection = selection.single),
            ),
          ),
          FilterChip(
            avatar: const Icon(Icons.dashboard_customize, size: 18),
            label: const Text('Icons'),
            selected: state._showIcons,
            onSelected: (value) => set(() => state._showIcons = value),
          ),
          SizedBox(
            width: 148,
            child: DropdownMenu<double>(
              key: ValueKey(state._fontSize),
              initialSelection: state._fontSize,
              label: const Text('Font size'),
              leadingIcon: const Icon(Icons.format_size),
              inputDecorationTheme: const InputDecorationTheme(
                isDense: true,
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(horizontal: 8),
              ),
              dropdownMenuEntries: [
                for (final size in _fontSizes)
                  DropdownMenuEntry<double>(
                    value: size,
                    label: '${size.toInt()}',
                  ),
              ],
              onSelected: (value) {
                if (value != null) set(() => state._fontSize = value);
              },
            ),
          ),
          PopupMenuButton<_TextStyleAction>(
            tooltip: 'Text styles',
            icon: Icon(
              Icons.text_fields,
              color: bold || italic
                  ? Theme.of(context).colorScheme.primary
                  : null,
            ),
            itemBuilder: (context) => [
              CheckedPopupMenuItem(
                value: _TextStyleAction.bold,
                checked: bold,
                child: const Text('Bold'),
              ),
              CheckedPopupMenuItem(
                value: _TextStyleAction.italic,
                checked: italic,
                child: const Text('Italic'),
              ),
            ],
            onSelected: (action) => set(() {
              switch (action) {
                case _TextStyleAction.bold:
                  state._bold = !bold;
                case _TextStyleAction.italic:
                  state._italic = !italic;
              }
            }),
          ),
        ],
      ),
    );
  }
}

class _StatusBar extends StatelessWidget {
  const _StatusBar({
    required this.controller,
    required this.api,
    required this.store,
  });

  final LazyTextFieldEditController controller;
  final MockApi api;
  final LazyTextFieldMemoryDraftStore store;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([controller, api]),
      builder: (context, _) {
        final counts = <LazyTextFieldDraftStatus, int>{};
        for (final draft in controller.drafts.values) {
          counts.update(draft.status, (n) => n + 1, ifAbsent: () => 1);
        }
        int count(LazyTextFieldDraftStatus status) => counts[status] ?? 0;
        final style = Theme.of(context).textTheme.bodySmall;
        return Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
          child: Wrap(
            spacing: 16,
            runSpacing: 4,
            children: [
              Text(
                controller.activeIds.isEmpty
                    ? 'Editing: none'
                    : 'Editing: ${controller.activeIds.join(', ')}',
                style: style,
              ),
              Text('Save queue: ${controller.pendingSaves}', style: style),
              Text(
                'Drafts: ${count(LazyTextFieldDraftStatus.unsaved)} unsaved, '
                '${count(LazyTextFieldDraftStatus.pending)} saving, '
                '${count(LazyTextFieldDraftStatus.failed)} failed',
                style: style,
              ),
              Text('In draft store: ${store.drafts.length}', style: style),
              Text(
                'API: ${api.calls} calls, ${api.inFlight} in flight '
                '(max ${api.maxInFlight})',
                style: style,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SettingsPanel extends StatelessWidget {
  const _SettingsPanel({required this.state});

  final _SavingDemoScreenState state;

  @override
  Widget build(BuildContext context) {
    final api = state._api;
    final useCommit = state._saveCallback == SaveCallback.onCommit;
    final enabled = !state._restarting;
    final set = state._update;

    return ListenableBuilder(
      listenable: api,
      builder: (context, _) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const _SectionTitle('Mock API'),
          _Option<ApiFailure>(
            label: 'Failing calls',
            help: '"Every 2nd" fails calls #2, #4, …',
            value: api.failure,
            values: ApiFailure.values,
            labelOf: (value) => value.label,
            onChanged: (value) {
              api.failure = value;
              state._log.add('API failures: ${value.label}');
              set(() {});
            },
          ),
          Text(
            'Latency: ${api.latency.inMilliseconds} ms',
            style: Theme.of(context).textTheme.labelLarge,
          ),
          Slider(
            value: api.latency.inMilliseconds.toDouble(),
            max: 3000,
            divisions: 30,
            label: '${api.latency.inMilliseconds} ms',
            onChanged: (value) =>
                set(() => api.latency = Duration(milliseconds: value.round())),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: api.resetCounters,
              child: const Text('Reset "max in flight"'),
            ),
          ),
          const Divider(height: 32),
          const _SectionTitle('Cells'),
          _Option<SaveCallback>(
            label: 'Save callback',
            help: useCommit
                ? 'onCommit: the cell shows its draft while it saves; a '
                      'throw marks it failed.'
                : 'onSave: return true to close, false to keep editing.',
            value: state._saveCallback,
            values: SaveCallback.values,
            labelOf: (value) => value.name,
            onChanged: (value) => set(() => state._saveCallback = value),
          ),
          _Option<LazyTextFieldSubmitClose>(
            label: 'closeOnSubmit (onCommit)',
            help: 'afterSave keeps the editor open until the save succeeds.',
            value: state._closeOnSubmit,
            values: LazyTextFieldSubmitClose.values,
            labelOf: (value) => value.name,
            onChanged: useCommit
                ? (value) => set(() => state._closeOnSubmit = value)
                : null,
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Keep the open editor alive'),
            subtitle: const Text(
              'ListView addAutomaticKeepAlives. Off: an editor scrolled out '
              'of view is unmounted, as in grids that recycle cells.',
            ),
            value: state._keepFocusedEditorAlive,
            onChanged: (value) =>
                set(() => state._keepFocusedEditorAlive = value),
          ),
          const Divider(height: 32),
          const _SectionTitle('Edit controller'),
          Text(
            'Changing these creates a new controller, like an app restart.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          _Option<LazyTextFieldSwitchPolicy>(
            label: 'switchPolicy',
            help:
                'What happens to an open editor when another cell starts '
                'editing.',
            value: state._switchPolicy,
            values: LazyTextFieldSwitchPolicy.values,
            labelOf: (value) => value.name,
            onChanged: enabled
                ? (value) => state._changeController(
                    'switchPolicy',
                    () => state._switchPolicy = value,
                  )
                : null,
          ),
          _Option<LazyTextFieldSaveMode>(
            label: 'saveMode (onCommit)',
            help:
                'deferred keeps every edit as an unsaved draft until '
                '"Save all".',
            value: state._saveMode,
            values: LazyTextFieldSaveMode.values,
            labelOf: (value) => value.name,
            onChanged: enabled
                ? (value) => state._changeController(
                    'saveMode',
                    () => state._saveMode = value,
                  )
                : null,
          ),
          _Option<LazyTextFieldSaveOrder>(
            label: 'saveOrder',
            help:
                'perRow saves different rows in parallel (watch "max in '
                'flight").',
            value: state._saveOrder,
            values: LazyTextFieldSaveOrder.values,
            labelOf: (value) => value.name,
            onChanged: enabled
                ? (value) => state._changeController(
                    'saveOrder',
                    () => state._saveOrder = value,
                  )
                : null,
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Draft store'),
            subtitle: const Text(
              'Keeps unsaved and failed drafts across a restart.',
            ),
            value: state._persistDrafts,
            onChanged: enabled
                ? (value) => state._changeController(
                    'draft store',
                    () => state._persistDrafts = value,
                  )
                : null,
          ),
          const Divider(height: 32),
          const _SectionTitle('Try'),
          const _Tips(),
        ],
      ),
    );
  }
}

class _Tips extends StatelessWidget {
  const _Tips();

  static const _tips = [
    'Edit a cell, then click another one: the first saves in the '
        'background while you type in the second.',
    'Set failures to "All" and switch cells: the draft fails and keeps '
        'your text. Reopen it to see the error; Escape discards it.',
    'Edit a cell and scroll it far away with the mouse wheel: the cell is '
        'unmounted and its text becomes an unsaved draft, saved when you '
        'edit another cell or press "Save all". (Clicking elsewhere, '
        'including a button, submits the open editor instead.)',
    'With saveMode deferred, edit a few cells, then "Save all in one '
        'request".',
    'Leave unsaved drafts (scrolled away, failed, or with saveMode '
        'deferred) and press "Restart" with and without the draft store.',
    'Set latency to 3 s, saveOrder perRow, and edit cells of different '
        'rows quickly.',
  ];

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodySmall;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final tip in _tips)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text('• $tip', style: style),
          ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(text, style: Theme.of(context).textTheme.titleMedium),
    );
  }
}

class _Option<T extends Object> extends StatelessWidget {
  const _Option({
    required this.label,
    required this.help,
    required this.value,
    required this.values,
    required this.labelOf,
    required this.onChanged,
  });

  final String label;
  final String help;
  final T value;
  final List<T> values;
  final String Function(T value) labelOf;
  final ValueChanged<T>? onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final onChanged = this.onChanged;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: theme.textTheme.labelLarge),
          const SizedBox(height: 6),
          SegmentedButton<T>(
            showSelectedIcon: false,
            segments: [
              for (final value in values)
                ButtonSegment(value: value, label: Text(labelOf(value))),
            ],
            selected: {value},
            onSelectionChanged: onChanged == null
                ? null
                : (selected) => onChanged(selected.single),
          ),
          const SizedBox(height: 4),
          Text(help, style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _LogPanel extends StatelessWidget {
  const _LogPanel({required this.log});

  final DemoLog log;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Event log',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              TextButton(onPressed: log.clear, child: const Text('Clear')),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListenableBuilder(
            listenable: log,
            builder: (context, _) => ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: log.lines.length,
              itemBuilder: (context, index) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  log.lines[index],
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
