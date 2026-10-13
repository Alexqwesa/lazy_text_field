import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:lazy_text_field/src/lazy_text_field_keys.dart';
import 'package:lazy_text_field/src/lazy_text_field_layout.dart';
import 'package:lazy_text_field/src/lazy_text_field_metrics.dart';

/// Builds the read-only overflow marker shown when static text is clipped.
typedef LazyTextFieldOverflowMarkerBuilder =
    Widget Function(
      BuildContext context,
      LazyTextFieldOverflowMarkerDetails details,
    );

/// Selection applied when a lazy field enters edit mode.
enum LazyTextFieldStartEditSelection {
  /// Place the caret at the beginning of the text.
  beginning,

  /// Place the caret at the end of the text.
  end,

  /// Place the caret closest to the tap position that started editing.
  tapPosition,

  /// Select the full text value.
  fullSelection,
}

/// Details for a pointer-driven edit start.
class LazyTextFieldStartEditDetails {
  /// Creates edit-start details.
  const LazyTextFieldStartEditDetails({
    required this.localPosition,
    required this.textOffset,
  });

  /// Local tap position inside the text viewport.
  final Offset localPosition;

  /// Text offset nearest to [localPosition].
  final int textOffset;
}

/// State passed to [LazyTextFieldOverflowMarkerBuilder].
class LazyTextFieldOverflowMarkerDetails {
  /// Creates overflow marker builder details.
  const LazyTextFieldOverflowMarkerDetails({
    required this.size,
    required this.color,
    required this.expanded,
    required this.hasHiddenText,
    required this.onToggle,
  });

  /// Suggested square marker size.
  final double size;

  /// Marker color selected for the current state.
  final Color color;

  /// Whether read-only overflow is currently expanded.
  final bool expanded;

  /// Whether text is hidden by the current read-only height.
  final bool hasHiddenText;

  /// Callback that toggles read-only overflow expansion, if available.
  final VoidCallback? onToggle;
}

/// A table/grid cell that stays lazy in read-only mode and mounts a real
/// [TextField] only while editing.
///
/// Pass `controller` and `focusNode` when [isEditing] is true; pass `null` for
/// both otherwise so read-only cells avoid edit allocations.
class LazyTextField extends StatefulWidget {
  /// Creates a lazy text field.
  ///
  /// When [isEditing] is true, both [controller] and [focusNode] must be
  /// non-null. When [isEditing] is false, pass null for both to avoid mounting
  /// edit resources.
  const LazyTextField({
    required this.cellId,
    required this.text,
    required this.isEditing,
    required this.onStartEditing,
    this.onStartEditingWithDetails,
    this.controller,
    this.focusNode,
    super.key,
    this.singleLine = false,
    this.style,
    this.strutStyle,
    this.textAlign = TextAlign.start,
    this.textAlignVertical,
    this.textDirection,
    this.decoration = const InputDecoration(),
    this.minHeight = 0,
    this.maxHeight,
    this.scrollbarGutter = 12,
    this.scrollbarThickness = 6,
    this.scrollbarAlignment = LazyTextField.defaultScrollbarAlignment,
    this.readOnlyAsLink = false,
    this.reservedTrailingWidth = 0,
    this.readOnlyOverflowExpanded = false,
    this.onReadOnlyOverflowToggle,
    this.overflowMarkerSize = 14,
    this.overflowMarkerColor,
    this.expandedOverflowMarkerColor,
    this.overflowMarkerBuilder = LazyTextField.defaultOverflowMarkerBuilder,
    this.errorMessage,
    this.onChanged,
    this.onSubmitted,
    this.onEditingComplete,
    this.onTapOutside,
    this.onSecondaryTapDown,
    this.onLongPressStart,
    this.onStopEditing,
    this.textInputAction,
    this.keyboardType,
    this.inputFormatters,
    this.minLines,
    this.maxLines,
    this.expands,
    this.scrollController,
    this.scrollPhysics,
    this.enabled,
    this.readOnly = false,
    this.autofocus = true,
    this.showCursor,
    this.enableInteractiveSelection,
    this.selectionControls,
    this.cursorColor,
    this.cursorWidth = 2,
    this.cursorHeight,
    this.cursorRadius,
    this.maxLength,
    this.maxLengthEnforcement,
    this.buildCounter,
    this.undoController,
    this.statesController,
    this.autofillHints = const <String>[],
    this.contextMenuBuilder,
    this.mouseCursor,
  }) : assert(!isEditing || controller != null),
       assert(!isEditing || focusNode != null);

  /// Stable id used for keys and test hooks.
  final String cellId;

  /// Text shown in read-only mode and used for measurement.
  final String text;

  /// Whether the field is currently mounting the real editor.
  final bool isEditing;

  /// Active edit controller, required only while [isEditing] is true.
  final TextEditingController? controller;

  /// Active edit focus node, required only while [isEditing] is true.
  final FocusNode? focusNode;

  /// Called when the read-only surface should enter edit mode.
  final VoidCallback onStartEditing;

  /// Called with tap-derived text position details when editing starts.
  final ValueChanged<LazyTextFieldStartEditDetails>? onStartEditingWithDetails;

  /// Called when editing should stop without a submitted value.
  ///
  /// This callback is currently used by internal surfaces that need to ask the
  /// parent to leave edit mode.
  final VoidCallback? onStopEditing;

  /// Whether the field should lay out and edit as one line.
  ///
  /// When true, read-only text is ellipsized to a single line and the editor
  /// uses `maxLines: 1` with newline characters rejected (including paste).
  final bool singleLine;

  /// Text style used in both read-only and edit modes.
  final TextStyle? style;

  /// Strut style used for edit-mode and measurement text layout.
  final StrutStyle? strutStyle;

  /// Horizontal text alignment.
  final TextAlign textAlign;

  /// Vertical text alignment used by the native [InputDecorator].
  final TextAlignVertical? textAlignVertical;

  /// Explicit text direction, or null to inherit it.
  final TextDirection? textDirection;

  /// Native Material decoration shared by read-only and editing modes.
  ///
  /// Keep layout-affecting properties equivalent across the mode switch.
  /// Use [InputDecoration.contentPadding] to control text padding.
  final InputDecoration? decoration;

  /// Minimum text viewport height.
  ///
  /// Set this to the same finite value as [maxHeight] to activate the
  /// fixed-height fast path, which skips text measurement during sizing.
  final double minHeight;

  /// Maximum text viewport height before vertical overflow is clipped.
  ///
  /// Set this to the same finite value as [minHeight] for uniform table rows.
  final double? maxHeight;

  /// Width reserved for the package scrollbar in bounded edit mode.
  final double scrollbarGutter;

  /// Thickness of the package scrollbar thumb.
  final double scrollbarThickness;

  /// Alignment of the package scrollbar thumb inside its gutter.
  final AlignmentGeometry scrollbarAlignment;

  /// Whether read-only text should use link-like cursor/gesture behavior.
  final bool readOnlyAsLink;

  /// Extra trailing width reserved from the text layout.
  ///
  /// Use this for app-owned overlay controls. Prefer
  /// [InputDecoration.suffixIcon] for controls that are part of the field.
  final double reservedTrailingWidth;

  /// Whether read-only overflow is currently expanded.
  final bool readOnlyOverflowExpanded;

  /// Called when the read-only overflow marker is tapped.
  final VoidCallback? onReadOnlyOverflowToggle;

  /// Square size used for the read-only overflow marker.
  final double overflowMarkerSize;

  /// Marker color while overflow is collapsed.
  final Color? overflowMarkerColor;

  /// Marker color while overflow is expanded.
  final Color? expandedOverflowMarkerColor;

  /// Builder for the read-only overflow marker, or null to hide it.
  final LazyTextFieldOverflowMarkerBuilder? overflowMarkerBuilder;

  /// Validation message shown in a popup below the field (no layout impact).
  ///
  /// Do not use [InputDecoration.errorText] — that slot changes field height
  /// and is unsupported here. Keep [decoration] layout-stable and put commit
  /// failures in [errorMessage] instead (typically when a wrapper [onSave]
  /// returns false).
  final String? errorMessage;

  /// Passed through to the internal [TextField.onChanged].
  final ValueChanged<String>? onChanged;

  /// Passed through to the internal [TextField.onSubmitted].
  final ValueChanged<String>? onSubmitted;

  /// Passed through to the internal [TextField.onEditingComplete].
  final VoidCallback? onEditingComplete;

  /// Passed through to the internal [TextField.onTapOutside].
  final TapRegionCallback? onTapOutside;

  /// Called when secondary tap starts on the read-only surface.
  final ValueChanged<TapDownDetails>? onSecondaryTapDown;

  /// Called when long press starts on the read-only surface.
  final ValueChanged<LongPressStartDetails>? onLongPressStart;

  /// Passed through to the internal [TextField.textInputAction].
  final TextInputAction? textInputAction;

  /// Passed through to the internal [TextField.keyboardType].
  final TextInputType? keyboardType;

  /// Passed through to the internal [TextField.inputFormatters].
  final List<TextInputFormatter>? inputFormatters;

  /// Passed through to the internal [TextField.minLines].
  final int? minLines;

  /// Passed through to the internal [TextField.maxLines].
  final int? maxLines;

  /// Passed through to the internal [TextField.expands].
  final bool? expands;

  /// Scroll controller for the internal editor.
  final ScrollController? scrollController;

  /// Scroll physics for the internal editor.
  final ScrollPhysics? scrollPhysics;

  /// Passed through to the internal [TextField.enabled].
  final bool? enabled;

  /// Passed through to the internal [TextField.readOnly].
  final bool readOnly;

  /// Passed through to the internal [TextField.autofocus].
  final bool autofocus;

  /// Passed through to the internal [TextField.showCursor].
  final bool? showCursor;

  /// Passed through to the internal [TextField.enableInteractiveSelection].
  final bool? enableInteractiveSelection;

  /// Passed through to the internal [TextField.selectionControls].
  final TextSelectionControls? selectionControls;

  /// Passed through to the internal [TextField.cursorColor].
  final Color? cursorColor;

  /// Passed through to the internal [TextField.cursorWidth].
  final double cursorWidth;

  /// Passed through to the internal [TextField.cursorHeight].
  final double? cursorHeight;

  /// Passed through to the internal [TextField.cursorRadius].
  final Radius? cursorRadius;

  /// Passed through to the internal [TextField.maxLength].
  final int? maxLength;

  /// Passed through to the internal [TextField.maxLengthEnforcement].
  final MaxLengthEnforcement? maxLengthEnforcement;

  /// Builds the counter shown by the outer native [InputDecorator].
  final InputCounterWidgetBuilder? buildCounter;

  /// Passed through to the internal [TextField.undoController].
  final UndoHistoryController? undoController;

  /// Passed through to the internal [TextField.statesController].
  final WidgetStatesController? statesController;

  /// Passed through to the internal [TextField.autofillHints].
  final Iterable<String>? autofillHints;

  /// Passed through to the internal [TextField.contextMenuBuilder].
  final EditableTextContextMenuBuilder? contextMenuBuilder;

  /// Passed through to the internal [TextField.mouseCursor].
  final MouseCursor? mouseCursor;

  /// Default alignment for the package scrollbar inside its gutter.
  static const Alignment defaultScrollbarAlignment = Alignment(
    -0.3333333333333333,
    0,
  );

  /// Measures a full lazy text field layout using inherited context values.
  static LazyTextFieldLayout measure(
    BuildContext context, {
    required String text,
    required double width,
    required TextStyle style,
    required EdgeInsetsGeometry padding,
    required bool singleLine,
    StrutStyle? strutStyle,
    double minHeight = 0,
    double reservedLeadingWidth = 0,
    double reservedTrailingWidth = 0,
    double? maxHeight,
    double scrollbarGutter = 12,
    double cursorWidth = 2,
  }) {
    return LazyTextFieldLayout.computeFromContext(
      context,
      text: text,
      width: width,
      padding: padding,
      singleLine: singleLine,
      style: style,
      strutStyle: strutStyle,
      minHeight: minHeight,
      reservedLeadingWidth: reservedLeadingWidth,
      reservedTrailingWidth: reservedTrailingWidth,
      maxHeight: maxHeight,
      scrollbarGutter: scrollbarGutter,
      editableTextGutter: _editableTextGutter(cursorWidth),
    );
  }

  /// Builds the default read-only overflow corner marker.
  static Widget defaultOverflowMarkerBuilder(
    BuildContext context,
    LazyTextFieldOverflowMarkerDetails details,
  ) {
    return _DefaultOverflowCornerMarker(
      color: details.color,
      outlined: details.expanded,
    );
  }

  /// Returns the [LazyTextField] surface height for a given [width].
  ///
  /// Pass [context] to inherit [DefaultTextStyle], text direction, and text
  /// scaler from the widget tree. Omit [context] when measuring outside build,
  /// for example while sizing data-table rows.
  static double computeHeightForWidth({
    BuildContext? context,
    required String text,
    required double width,
    TextStyle? style,
    StrutStyle? strutStyle,
    EdgeInsetsGeometry padding = kDefaultLazyTextFieldPadding,
    bool singleLine = false,
    TextDirection? textDirection,
    TextScaler? textScaler,
    double minHeight = 0,
    double reservedLeadingWidth = 0,
    double reservedTrailingWidth = 0,
    double? maxHeight,
    double scrollbarGutter = 12,
    double cursorWidth = 2,
  }) {
    return LazyTextFieldMetrics.computeHeightForWidth(
      context: context,
      text: text,
      width: width,
      style: style,
      strutStyle: strutStyle,
      padding: padding,
      singleLine: singleLine,
      textDirection: textDirection,
      textScaler: textScaler,
      minHeight: minHeight,
      reservedLeadingWidth: reservedLeadingWidth,
      reservedTrailingWidth: reservedTrailingWidth,
      maxHeight: maxHeight,
      scrollbarGutter: scrollbarGutter,
      cursorWidth: cursorWidth,
    );
  }

  @override
  State<LazyTextField> createState() => _LazyTextFieldState();
}

class _LazyTextFieldState extends State<LazyTextField> {
  TextEditingController? _listenedController;
  FocusNode? _listenedFocusNode;
  ScrollController? _scrollController;
  final GlobalKey _textViewportRenderKey = GlobalKey();
  final LayerLink _errorLink = LayerLink();
  final OverlayPortalController _errorPortalController =
      OverlayPortalController();
  bool _isHovering = false;
  String? _lastLayoutText;
  LazyTextFieldStartEditDetails? _lastStartEditDetails;

  @override
  void initState() {
    super.initState();
    _syncControllerListener();
    _syncFocusNodeListener();
    _debugAssertNoDecorationErrorText();
    _scheduleSyncErrorPopup();
  }

  @override
  void didUpdateWidget(covariant LazyTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncControllerListener();
    _syncFocusNodeListener();
    _debugAssertNoDecorationErrorText();
    _scheduleSyncErrorPopup();

    final focusNode = widget.focusNode;
    if (!widget.isEditing || focusNode == null) {
      return;
    }

    final enteredEditMode = widget.isEditing && !oldWidget.isEditing;
    final focusNodeChanged = focusNode != oldWidget.focusNode;
    if (!enteredEditMode && !focusNodeChanged) {
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _listenedController?.removeListener(_onControllerChanged);
    _listenedFocusNode?.removeListener(_onFocusChanged);
    if (widget.scrollController == null) {
      _scrollController?.dispose();
    }
    super.dispose();
  }

  String? get _resolvedErrorMessage {
    final explicit = widget.errorMessage;
    if (explicit == null || explicit.isEmpty) return null;
    return explicit;
  }

  void _debugAssertNoDecorationErrorText() {
    final decoration = widget.decoration;
    assert(
      decoration == null ||
          ((decoration.errorText == null || decoration.errorText!.isEmpty) &&
              decoration.error == null),
      'LazyTextField does not support InputDecoration.errorText / error '
      'because they change field height. Use errorMessage for validation '
      'feedback, and keep onSave as the commit gate.',
    );
  }

  void _scheduleSyncErrorPopup() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final message = _resolvedErrorMessage;
      if (message != null) {
        if (!_errorPortalController.isShowing) {
          _errorPortalController.show();
        }
      } else if (_errorPortalController.isShowing) {
        _errorPortalController.hide();
      }
    });
  }

  void _syncControllerListener() {
    if (_listenedController == widget.controller) return;

    _listenedController?.removeListener(_onControllerChanged);
    _listenedController = widget.controller;
    _lastLayoutText = widget.controller?.text;
    _listenedController?.addListener(_onControllerChanged);
  }

  void _syncFocusNodeListener() {
    if (_listenedFocusNode == widget.focusNode) return;

    _listenedFocusNode?.removeListener(_onFocusChanged);
    _listenedFocusNode = widget.focusNode;
    _listenedFocusNode?.addListener(_onFocusChanged);
  }

  void _onControllerChanged() {
    if (!widget.isEditing || !mounted) return;
    final nextText = widget.controller?.text;
    if (nextText == _lastLayoutText) return;
    _lastLayoutText = nextText;
    setState(() {});
  }

  void _onFocusChanged() {
    if (widget.decoration == null || !mounted) return;
    setState(() {});
  }

  TextStyle _resolvedStyle(BuildContext context) {
    final base = DefaultTextStyle.of(context).style.merge(widget.style);
    if (!widget.readOnlyAsLink || widget.isEditing) {
      return base;
    }
    return base.copyWith(
      color: Colors.blue.shade700,
      decoration: TextDecoration.underline,
      decorationColor: Colors.blue.shade700,
    );
  }

  @override
  Widget build(BuildContext context) {
    final direction = widget.textDirection ?? Directionality.of(context);
    final resolvedStyle = _resolvedStyle(context);
    final value = widget.isEditing
        ? widget.controller?.text ?? widget.text
        : widget.text;
    final effectiveEnabled =
        widget.enabled ?? widget.decoration?.enabled ?? true;

    Widget content = _LazyTextFieldContent(
      cellId: widget.cellId,
      viewportRenderKey: _textViewportRenderKey,
      text: value,
      isEditing: widget.isEditing,
      controller: widget.controller,
      focusNode: widget.focusNode,
      style: resolvedStyle,
      strutStyle: widget.strutStyle,
      singleLine: widget.singleLine,
      textAlign: widget.textAlign,
      textAlignVertical: widget.textAlignVertical,
      textDirection: widget.textDirection,
      minHeight: widget.minHeight,
      maxHeight: widget.maxHeight,
      scrollbarGutter: widget.scrollbarGutter,
      scrollbarThickness: widget.scrollbarThickness,
      scrollbarAlignment: widget.scrollbarAlignment,
      reservedTrailingWidth: widget.reservedTrailingWidth,
      readOnlyAsLink: widget.readOnlyAsLink,
      readOnlyOverflowExpanded: widget.readOnlyOverflowExpanded,
      onReadOnlyOverflowToggle: widget.onReadOnlyOverflowToggle,
      overflowMarkerSize: widget.overflowMarkerSize,
      overflowMarkerColor: widget.overflowMarkerColor,
      expandedOverflowMarkerColor: widget.expandedOverflowMarkerColor,
      overflowMarkerBuilder: widget.overflowMarkerBuilder,
      scrollController: widget.isEditing ? _scrollControllerFor() : null,
      onChanged: widget.onChanged,
      onSubmitted: widget.onSubmitted,
      onEditingComplete: widget.onEditingComplete,
      onTapOutside: widget.onTapOutside,
      textInputAction: widget.textInputAction,
      keyboardType: widget.keyboardType,
      inputFormatters: widget.inputFormatters,
      minLines: widget.minLines,
      maxLines: widget.maxLines,
      expands: widget.expands,
      scrollPhysics: widget.scrollPhysics,
      enabled: effectiveEnabled,
      readOnly: widget.readOnly,
      autofocus: widget.autofocus,
      showCursor: widget.showCursor,
      enableInteractiveSelection: widget.enableInteractiveSelection,
      selectionControls: widget.selectionControls,
      cursorColor: widget.cursorColor,
      cursorWidth: widget.cursorWidth,
      cursorHeight: widget.cursorHeight,
      cursorRadius: widget.cursorRadius,
      maxLength: widget.maxLength,
      maxLengthEnforcement: widget.maxLengthEnforcement,
      undoController: widget.undoController,
      statesController: widget.statesController,
      autofillHints: widget.autofillHints,
      contextMenuBuilder: widget.contextMenuBuilder,
      mouseCursor: widget.mouseCursor,
    );

    final decoration = widget.decoration;
    if (decoration != null) {
      content = InputDecorator(
        decoration: _effectiveDecoration(context, decoration, value),
        baseStyle: widget.style,
        textAlign: widget.textAlign,
        textAlignVertical: widget.textAlignVertical,
        isHovering: _isHovering,
        isFocused: widget.focusNode?.hasFocus ?? false,
        isEmpty: value.isEmpty,
        expands: widget.expands ?? false,
        child: content,
      );
    }

    // Prefix/suffix icons live on the outer InputDecorator, outside the inner
    // TextField's default tap region. Always wrap so mode switches keep a
    // stable InputDecorator Element and edit-mode icon taps stay "inside".
    content = TextFieldTapRegion(child: content);

    final staticMode = !widget.isEditing && effectiveEnabled;
    final field = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: staticMode
          ? (details) {
              _lastStartEditDetails = _startEditDetailsFor(
                context: context,
                globalPosition: details.globalPosition,
                localPosition: details.localPosition,
                style: resolvedStyle,
                direction: direction,
              );
            }
          : null,
      onTap: staticMode ? _startEditing : null,
      onSecondaryTapDown: staticMode ? widget.onSecondaryTapDown : null,
      onLongPressStart: staticMode ? widget.onLongPressStart : null,
      child: MouseRegion(
        cursor: widget.mouseCursor ?? MouseCursor.defer,
        onEnter: (_) => _setHovering(true),
        onExit: (_) => _setHovering(false),
        child: SizedBox(
          key: LazyTextFieldKeys.root(widget.cellId),
          width: double.infinity,
          child: content,
        ),
      ),
    );

    return OverlayPortal(
      controller: _errorPortalController,
      overlayChildBuilder: (context) {
        final message = _resolvedErrorMessage;
        if (message == null) return const SizedBox.shrink();
        return CompositedTransformFollower(
          link: _errorLink,
          showWhenUnlinked: false,
          targetAnchor: Alignment.bottomLeft,
          followerAnchor: Alignment.topLeft,
          offset: const Offset(0, 4),
          child: _ValidationErrorPopup(
            cellId: widget.cellId,
            message: message,
          ),
        );
      },
      child: CompositedTransformTarget(
        link: _errorLink,
        child: field,
      ),
    );
  }

  void _startEditing() {
    final onStartEditingWithDetails = widget.onStartEditingWithDetails;
    if (onStartEditingWithDetails == null) {
      widget.onStartEditing();
      return;
    }
    onStartEditingWithDetails(
      _lastStartEditDetails ??
          LazyTextFieldStartEditDetails(
            localPosition: Offset.zero,
            textOffset: widget.text.length,
          ),
    );
  }

  InputDecoration _effectiveDecoration(
    BuildContext context,
    InputDecoration decoration,
    String value,
  ) {
    final theme = Theme.of(context);
    // InputDecoration.copyWith(errorText: null) does NOT clear errorText
    // (null means "keep"). Rebuild without the error slot instead.
    var effective = _withoutErrorSlot(
      decoration
          .applyDefaults(theme.inputDecorationTheme)
          .copyWith(
            enabled: widget.enabled ?? decoration.enabled,
            hintMaxLines:
                decoration.hintMaxLines ??
                theme.inputDecorationTheme.hintMaxLines ??
                widget.maxLines,
          ),
    );

    if (effective.counter != null || effective.counterText != null) {
      return effective;
    }

    final currentLength = value.characters.length;
    if (widget.buildCounter != null) {
      final counter = widget.buildCounter!(
        context,
        currentLength: currentLength,
        maxLength: widget.maxLength,
        isFocused: widget.focusNode?.hasFocus ?? false,
      );
      return effective.copyWith(
        counter: counter == null
            ? null
            : Semantics(
                container: true,
                liveRegion: widget.focusNode?.hasFocus ?? false,
                child: counter,
              ),
      );
    }

    final maxLength = widget.maxLength;
    if (maxLength == null) {
      return effective;
    }

    var counterText = '$currentLength';
    var semanticCounterText = '';
    if (maxLength > 0) {
      counterText += '/$maxLength';
      final remaining = (maxLength - currentLength).clamp(0, maxLength);
      semanticCounterText = MaterialLocalizations.of(
        context,
      ).remainingTextFieldCharacterCount(remaining);
    }

    if (maxLength > 0 && currentLength > maxLength) {
      effective = effective.copyWith(
        errorText: effective.errorText ?? '',
        counterStyle:
            effective.errorStyle ??
            theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
      );
    }
    return effective.copyWith(
      counterText: counterText,
      semanticCounterText: semanticCounterText,
    );
  }

  void _setHovering(bool value) {
    if (_isHovering == value) return;
    _isHovering = value;
    if (widget.decoration != null && mounted) {
      setState(() {});
    }
  }

  ScrollController _scrollControllerFor() {
    final supplied = widget.scrollController;
    if (supplied != null) {
      if (_scrollController != null) {
        _scrollController!.dispose();
        _scrollController = null;
      }
      return supplied;
    }
    return _scrollController ??= ScrollController();
  }

  LazyTextFieldStartEditDetails _startEditDetailsFor({
    required BuildContext context,
    required Offset globalPosition,
    required Offset localPosition,
    required TextStyle style,
    required TextDirection direction,
  }) {
    final renderBox =
        _textViewportRenderKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null || !renderBox.hasSize) {
      return LazyTextFieldStartEditDetails(
        localPosition: localPosition,
        textOffset: widget.text.length,
      );
    }
    final textLocalPosition = renderBox.globalToLocal(globalPosition);
    final textLayoutWidth = math.max<double>(
      0,
      renderBox.size.width - _editableTextGutter(widget.cursorWidth),
    );
    final painter = TextPainter(
      text: TextSpan(
        text: LazyTextFieldLayout.measureText(widget.text),
        style: style,
      ),
      textAlign: widget.textAlign,
      textDirection: direction,
      textScaler: MediaQuery.textScalerOf(context),
      strutStyle: widget.strutStyle ?? StrutStyle.fromTextStyle(style),
      maxLines: widget.singleLine ? 1 : null,
      ellipsis: widget.singleLine ? '\u2026' : null,
    )..layout(maxWidth: textLayoutWidth);
    final textPosition = painter.getPositionForOffset(textLocalPosition);
    return LazyTextFieldStartEditDetails(
      localPosition: localPosition,
      textOffset: textPosition.offset.clamp(0, widget.text.length),
    );
  }
}

class _LazyTextFieldContent extends StatelessWidget {
  const _LazyTextFieldContent({
    required this.cellId,
    required this.viewportRenderKey,
    required this.text,
    required this.isEditing,
    required this.style,
    required this.singleLine,
    required this.textAlign,
    required this.minHeight,
    required this.scrollbarGutter,
    required this.scrollbarThickness,
    required this.scrollbarAlignment,
    required this.reservedTrailingWidth,
    required this.readOnlyAsLink,
    required this.readOnlyOverflowExpanded,
    required this.overflowMarkerSize,
    required this.cursorWidth,
    required this.enabled,
    required this.readOnly,
    required this.autofocus,
    this.controller,
    this.focusNode,
    this.strutStyle,
    this.textAlignVertical,
    this.textDirection,
    this.maxHeight,
    this.onReadOnlyOverflowToggle,
    this.overflowMarkerColor,
    this.expandedOverflowMarkerColor,
    this.overflowMarkerBuilder,
    this.scrollController,
    this.onChanged,
    this.onSubmitted,
    this.onEditingComplete,
    this.onTapOutside,
    this.textInputAction,
    this.keyboardType,
    this.inputFormatters,
    this.minLines,
    this.maxLines,
    this.expands,
    this.scrollPhysics,
    this.showCursor,
    this.enableInteractiveSelection,
    this.selectionControls,
    this.cursorColor,
    this.cursorHeight,
    this.cursorRadius,
    this.maxLength,
    this.maxLengthEnforcement,
    this.undoController,
    this.statesController,
    this.autofillHints,
    this.contextMenuBuilder,
    this.mouseCursor,
  });

  final String cellId;
  final GlobalKey viewportRenderKey;
  final String text;
  final bool isEditing;
  final TextEditingController? controller;
  final FocusNode? focusNode;
  final TextStyle style;
  final StrutStyle? strutStyle;
  final bool singleLine;
  final TextAlign textAlign;
  final TextAlignVertical? textAlignVertical;
  final TextDirection? textDirection;
  final double minHeight;
  final double? maxHeight;
  final double scrollbarGutter;
  final double scrollbarThickness;
  final AlignmentGeometry scrollbarAlignment;
  final double reservedTrailingWidth;
  final bool readOnlyAsLink;
  final bool readOnlyOverflowExpanded;
  final VoidCallback? onReadOnlyOverflowToggle;
  final double overflowMarkerSize;
  final Color? overflowMarkerColor;
  final Color? expandedOverflowMarkerColor;
  final LazyTextFieldOverflowMarkerBuilder? overflowMarkerBuilder;
  final ScrollController? scrollController;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final VoidCallback? onEditingComplete;
  final TapRegionCallback? onTapOutside;
  final TextInputAction? textInputAction;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final int? minLines;
  final int? maxLines;
  final bool? expands;
  final ScrollPhysics? scrollPhysics;
  final bool enabled;
  final bool readOnly;
  final bool autofocus;
  final bool? showCursor;
  final bool? enableInteractiveSelection;
  final TextSelectionControls? selectionControls;
  final Color? cursorColor;
  final double cursorWidth;
  final double? cursorHeight;
  final Radius? cursorRadius;
  final int? maxLength;
  final MaxLengthEnforcement? maxLengthEnforcement;
  final UndoHistoryController? undoController;
  final WidgetStatesController? statesController;
  final Iterable<String>? autofillHints;
  final EditableTextContextMenuBuilder? contextMenuBuilder;
  final MouseCursor? mouseCursor;

  @override
  Widget build(BuildContext context) {
    final direction = textDirection ?? Directionality.of(context);
    final textScaler = MediaQuery.textScalerOf(context);
    final isHeightBounded = maxHeight != null && maxHeight!.isFinite;
    final gutter = isHeightBounded ? scrollbarGutter : 0.0;
    final fixedHeight = _fixedViewportHeight(minHeight, maxHeight);

    return _TextViewportSizer(
      text: text,
      style: style,
      strutStyle: strutStyle,
      singleLine: singleLine,
      textDirection: direction,
      textScaler: textScaler,
      minHeight: minHeight,
      maxHeight: maxHeight,
      reservedScrollbarWidth: gutter,
      reservedTrailingWidth: reservedTrailingWidth,
      editableTextGutter: _editableTextGutter(cursorWidth),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final layout = fixedHeight == null
              ? LazyTextFieldLayout.compute(
                  text: text,
                  width: constraints.maxWidth,
                  padding: EdgeInsets.zero,
                  singleLine: singleLine,
                  style: style,
                  textDirection: direction,
                  textScaler: textScaler,
                  strutStyle: strutStyle,
                  minHeight: minHeight,
                  reservedTrailingWidth: reservedTrailingWidth,
                  maxHeight: maxHeight,
                  scrollbarGutter: gutter,
                  editableTextGutter: _editableTextGutter(cursorWidth),
                )
              : _fixedViewportLayout(
                  width: constraints.maxWidth,
                  height: fixedHeight,
                  reservedScrollbarWidth: gutter,
                  reservedTrailingWidth: reservedTrailingWidth,
                  editableTextGutter: _editableTextGutter(cursorWidth),
                );
          final viewport = SizedBox(
            key: LazyTextFieldKeys.textViewport(cellId),
            width: layout.textViewportWidth,
            height: layout.height,
            child: SizedBox(
              key: viewportRenderKey,
              child: ClipRect(
                child: isEditing
                    ? KeyedSubtree(
                        key: LazyTextFieldKeys.editorSurface(cellId),
                        child: KeyedSubtree(
                          key: LazyTextFieldKeys.legacyEditorFrame(cellId),
                          child: _EditorBody(
                            cellId: cellId,
                            controller: controller!,
                            focusNode: focusNode!,
                            style: style,
                            strutStyle: strutStyle,
                            singleLine: singleLine,
                            scrollController: scrollController!,
                            textAlign: textAlign,
                            textAlignVertical: textAlignVertical,
                            textDirection: textDirection,
                            onChanged: onChanged,
                            onSubmitted: onSubmitted,
                            onEditingComplete: onEditingComplete,
                            onTapOutside: onTapOutside,
                            textInputAction: textInputAction,
                            keyboardType: keyboardType,
                            inputFormatters: inputFormatters,
                            minLines: minLines,
                            maxLines: maxLines,
                            expands: expands,
                            scrollPhysics: scrollPhysics,
                            enabled: enabled,
                            readOnly: readOnly,
                            autofocus: autofocus,
                            showCursor: showCursor,
                            enableInteractiveSelection:
                                enableInteractiveSelection,
                            selectionControls: selectionControls,
                            cursorColor: cursorColor,
                            cursorWidth: cursorWidth,
                            cursorHeight: cursorHeight,
                            cursorRadius: cursorRadius,
                            maxLength: maxLength,
                            maxLengthEnforcement: maxLengthEnforcement,
                            undoController: undoController,
                            statesController: statesController,
                            autofillHints: autofillHints,
                            contextMenuBuilder: contextMenuBuilder,
                            mouseCursor: mouseCursor,
                          ),
                        ),
                      )
                    : KeyedSubtree(
                        key: LazyTextFieldKeys.staticSurface(cellId),
                        child: KeyedSubtree(
                          key: LazyTextFieldKeys.legacyReadOnlySurface(cellId),
                          child: _StaticTextBody(
                            text: text,
                            style: style,
                            strutStyle: strutStyle,
                            singleLine: singleLine,
                            textAlign: textAlign,
                            textDirection: direction,
                            editableTextGutter: _editableTextGutter(
                              cursorWidth,
                            ),
                            readOnlyAsLink: readOnlyAsLink,
                            hasVerticalOverflow: fixedHeight == null
                                ? layout.hasVerticalOverflow
                                : null,
                            overflowExpanded: readOnlyOverflowExpanded,
                            onOverflowToggle: onReadOnlyOverflowToggle,
                            overflowMarkerSize: overflowMarkerSize,
                            overflowMarkerColor: overflowMarkerColor,
                            expandedOverflowMarkerColor:
                                expandedOverflowMarkerColor,
                            overflowMarkerBuilder: overflowMarkerBuilder,
                          ),
                        ),
                      ),
              ),
            ),
          );

          return Row(
            mainAxisSize: MainAxisSize.max,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              viewport,
              if (layout.reservedScrollbarWidth > 0)
                SizedBox(
                  width: layout.reservedScrollbarWidth,
                  height: layout.height,
                  child:
                      isEditing &&
                          (fixedHeight != null || layout.hasVerticalOverflow) &&
                          scrollController != null
                      ? TextFieldTapRegion(
                          child: _GutterScrollbar(
                            key: LazyTextFieldKeys.scrollbar(cellId),
                            controller: scrollController!,
                            viewportHeight: layout.height,
                            thickness: scrollbarThickness,
                            alignment: scrollbarAlignment,
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
              if (reservedTrailingWidth > 0)
                SizedBox(width: reservedTrailingWidth, height: layout.height),
            ],
          );
        },
      ),
    );
  }
}

double? _fixedViewportHeight(double minHeight, double? maxHeight) {
  if (maxHeight == null || !maxHeight.isFinite || minHeight != maxHeight) {
    return null;
  }
  return maxHeight.ceilToDouble();
}

LazyTextFieldLayout _fixedViewportLayout({
  required double width,
  required double height,
  required double reservedScrollbarWidth,
  required double reservedTrailingWidth,
  required double editableTextGutter,
}) {
  final textViewportWidth = math.max<double>(
    0,
    width - reservedScrollbarWidth - reservedTrailingWidth,
  );
  return LazyTextFieldLayout(
    height: height,
    contentHeight: height,
    textViewportWidth: textViewportWidth,
    textLayoutWidth: math.max<double>(
      0,
      textViewportWidth - editableTextGutter,
    ),
    hasVerticalOverflow: false,
    reservedScrollbarWidth: reservedScrollbarWidth,
  );
}

class _TextViewportSizer extends SingleChildRenderObjectWidget {
  const _TextViewportSizer({
    required this.text,
    required this.style,
    required this.singleLine,
    required this.textDirection,
    required this.textScaler,
    required this.minHeight,
    required this.reservedScrollbarWidth,
    required this.reservedTrailingWidth,
    required this.editableTextGutter,
    this.strutStyle,
    this.maxHeight,
    required super.child,
  });

  final String text;
  final TextStyle style;
  final StrutStyle? strutStyle;
  final bool singleLine;
  final TextDirection textDirection;
  final TextScaler textScaler;
  final double minHeight;
  final double? maxHeight;
  final double reservedScrollbarWidth;
  final double reservedTrailingWidth;
  final double editableTextGutter;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _RenderTextViewportSizer(
      text: text,
      style: style,
      strutStyle: strutStyle,
      singleLine: singleLine,
      textDirection: textDirection,
      textScaler: textScaler,
      minHeight: minHeight,
      maxHeight: maxHeight,
      reservedScrollbarWidth: reservedScrollbarWidth,
      reservedTrailingWidth: reservedTrailingWidth,
      editableTextGutter: editableTextGutter,
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderTextViewportSizer renderObject,
  ) {
    renderObject
      ..text = text
      ..style = style
      ..strutStyle = strutStyle
      ..singleLine = singleLine
      ..textDirection = textDirection
      ..textScaler = textScaler
      ..minHeight = minHeight
      ..maxHeight = maxHeight
      ..reservedScrollbarWidth = reservedScrollbarWidth
      ..reservedTrailingWidth = reservedTrailingWidth
      ..editableTextGutter = editableTextGutter;
  }
}

class _RenderTextViewportSizer extends RenderProxyBox {
  _RenderTextViewportSizer({
    required String text,
    required TextStyle style,
    required StrutStyle? strutStyle,
    required bool singleLine,
    required TextDirection textDirection,
    required TextScaler textScaler,
    required double minHeight,
    required double? maxHeight,
    required double reservedScrollbarWidth,
    required double reservedTrailingWidth,
    required double editableTextGutter,
  }) : _text = text,
       _style = style,
       _strutStyle = strutStyle,
       _singleLine = singleLine,
       _textDirection = textDirection,
       _textScaler = textScaler,
       _minHeight = minHeight,
       _maxHeight = maxHeight,
       _reservedScrollbarWidth = reservedScrollbarWidth,
       _reservedTrailingWidth = reservedTrailingWidth,
       _editableTextGutter = editableTextGutter;

  String _text;
  TextStyle _style;
  StrutStyle? _strutStyle;
  bool _singleLine;
  TextDirection _textDirection;
  TextScaler _textScaler;
  double _minHeight;
  double? _maxHeight;
  double _reservedScrollbarWidth;
  double _reservedTrailingWidth;
  double _editableTextGutter;
  double? _cachedLayoutWidth;
  LazyTextFieldLayout? _cachedLayout;

  void _invalidateLayout() {
    _cachedLayoutWidth = null;
    _cachedLayout = null;
    markNeedsLayout();
  }

  set text(String value) {
    if (_text == value) return;
    _text = value;
    _invalidateLayout();
  }

  set style(TextStyle value) {
    if (_style == value) return;
    _style = value;
    _invalidateLayout();
  }

  set strutStyle(StrutStyle? value) {
    if (_strutStyle == value) return;
    _strutStyle = value;
    _invalidateLayout();
  }

  set singleLine(bool value) {
    if (_singleLine == value) return;
    _singleLine = value;
    _invalidateLayout();
  }

  set textDirection(TextDirection value) {
    if (_textDirection == value) return;
    _textDirection = value;
    _invalidateLayout();
  }

  set textScaler(TextScaler value) {
    if (_textScaler == value) return;
    _textScaler = value;
    _invalidateLayout();
  }

  set minHeight(double value) {
    if (_minHeight == value) return;
    _minHeight = value;
    _invalidateLayout();
  }

  set maxHeight(double? value) {
    if (_maxHeight == value) return;
    _maxHeight = value;
    _invalidateLayout();
  }

  set reservedScrollbarWidth(double value) {
    if (_reservedScrollbarWidth == value) return;
    _reservedScrollbarWidth = value;
    _invalidateLayout();
  }

  set reservedTrailingWidth(double value) {
    if (_reservedTrailingWidth == value) return;
    _reservedTrailingWidth = value;
    _invalidateLayout();
  }

  set editableTextGutter(double value) {
    if (_editableTextGutter == value) return;
    _editableTextGutter = value;
    _invalidateLayout();
  }

  LazyTextFieldLayout _layoutFor(double width) {
    if (_cachedLayoutWidth == width && _cachedLayout != null) {
      return _cachedLayout!;
    }
    final fixedHeight = _fixedViewportHeight(_minHeight, _maxHeight);
    final layout = fixedHeight == null
        ? LazyTextFieldLayout.compute(
            text: _text,
            width: math.max(0, width),
            padding: EdgeInsets.zero,
            singleLine: _singleLine,
            style: _style,
            textDirection: _textDirection,
            textScaler: _textScaler,
            strutStyle: _strutStyle,
            minHeight: _minHeight,
            reservedTrailingWidth: _reservedTrailingWidth,
            maxHeight: _maxHeight,
            scrollbarGutter: _reservedScrollbarWidth,
            editableTextGutter: _editableTextGutter,
          )
        : _fixedViewportLayout(
            width: math.max(0, width),
            height: fixedHeight,
            reservedScrollbarWidth: _reservedScrollbarWidth,
            reservedTrailingWidth: _reservedTrailingWidth,
            editableTextGutter: _editableTextGutter,
          );
    _cachedLayoutWidth = width;
    _cachedLayout = layout;
    return layout;
  }

  double _widthFor(BoxConstraints constraints) {
    if (constraints.hasBoundedWidth) {
      return constraints.maxWidth;
    }
    return constraints.constrainWidth(
      child?.getMaxIntrinsicWidth(double.infinity) ?? 0,
    );
  }

  @override
  double computeMinIntrinsicHeight(double width) => _layoutFor(width).height;

  @override
  double computeMaxIntrinsicHeight(double width) => _layoutFor(width).height;

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    final width = _widthFor(constraints);
    return constraints.constrain(Size(width, _layoutFor(width).height));
  }

  @override
  void performLayout() {
    final width = _widthFor(constraints);
    size = constraints.constrain(Size(width, _layoutFor(width).height));
    // InputDecorator reads this child's size/baseline during its own layout.
    child?.layout(BoxConstraints.tight(size), parentUsesSize: true);
  }

  @override
  double? computeDistanceToActualBaseline(TextBaseline baseline) {
    // Baseline can be queried during the parent's performLayout before this
    // box's size is readable — derive width from constraints instead.
    final width = _widthFor(constraints);
    final textWidth = math.max<double>(
      0,
      width -
          _reservedScrollbarWidth -
          _reservedTrailingWidth -
          _editableTextGutter,
    );
    final painter = TextPainter(
      text: TextSpan(
        text: LazyTextFieldLayout.measureText(_text),
        style: _style,
      ),
      textDirection: _textDirection,
      textScaler: _textScaler,
      strutStyle: _strutStyle ?? StrutStyle.fromTextStyle(_style),
      maxLines: _singleLine ? 1 : null,
      ellipsis: _singleLine ? '\u2026' : null,
    )..layout(maxWidth: textWidth);
    return painter.computeDistanceToActualBaseline(baseline);
  }
}

class _StaticTextBody extends StatelessWidget {
  const _StaticTextBody({
    required this.text,
    required this.style,
    required this.strutStyle,
    required this.singleLine,
    required this.textAlign,
    required this.textDirection,
    required this.editableTextGutter,
    required this.readOnlyAsLink,
    required this.overflowExpanded,
    required this.overflowMarkerSize,
    this.hasVerticalOverflow,
    this.onOverflowToggle,
    this.overflowMarkerColor,
    this.expandedOverflowMarkerColor,
    this.overflowMarkerBuilder,
  });

  final String text;
  final TextStyle style;
  final StrutStyle? strutStyle;
  final bool singleLine;
  final TextAlign textAlign;
  final TextDirection textDirection;
  final double editableTextGutter;
  final bool readOnlyAsLink;
  final bool? hasVerticalOverflow;
  final bool overflowExpanded;
  final VoidCallback? onOverflowToggle;
  final double overflowMarkerSize;
  final Color? overflowMarkerColor;
  final Color? expandedOverflowMarkerColor;
  final LazyTextFieldOverflowMarkerBuilder? overflowMarkerBuilder;

  @override
  Widget build(BuildContext context) {
    final textScaler = MediaQuery.textScalerOf(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final textLayoutWidth = math.max<double>(
          0,
          constraints.maxWidth - editableTextGutter,
        );
        final paintedText = CustomPaint(
          painter: _StaticTextPainter(
            text: text,
            style: style,
            strutStyle: strutStyle,
            singleLine: singleLine,
            textAlign: textAlign,
            direction: textDirection,
            textScaler: textScaler,
            maxWidth: textLayoutWidth,
          ),
          size: Size(constraints.maxWidth, constraints.maxHeight),
        );

        Widget body = paintedText;
        if (text.isNotEmpty) {
          final layoutPainter = TextPainter(
            text: TextSpan(
              text: LazyTextFieldLayout.measureText(text),
              style: style,
            ),
            textAlign: textAlign,
            textDirection: textDirection,
            textScaler: textScaler,
            strutStyle: strutStyle ?? StrutStyle.fromTextStyle(style),
            maxLines: singleLine ? 1 : null,
            ellipsis: singleLine ? '\u2026' : null,
          )..layout(maxWidth: textLayoutWidth);

          final overflowsWidth = singleLine && layoutPainter.didExceedMaxLines;
          final overflowsHeight =
              !singleLine &&
              (hasVerticalOverflow ??
                  layoutPainter.height.ceilToDouble() > constraints.maxHeight);
          final hasHiddenText = overflowsWidth || overflowsHeight;

          if (hasHiddenText || overflowExpanded) {
            final markerColor = overflowExpanded
                ? expandedOverflowMarkerColor ?? Colors.red
                : overflowMarkerColor ?? Colors.red;
            final markerDetails = LazyTextFieldOverflowMarkerDetails(
              size: overflowMarkerSize,
              color: markerColor,
              expanded: overflowExpanded,
              hasHiddenText: hasHiddenText,
              onToggle: onOverflowToggle,
            );

            final markerBuilder = overflowMarkerBuilder;
            if (markerBuilder != null) {
              final markerAtEnd = textDirection == TextDirection.ltr;
              body = Stack(
                fit: StackFit.passthrough,
                children: [
                  paintedText,
                  Positioned(
                    left: markerAtEnd ? null : 0,
                    right: markerAtEnd ? 0 : null,
                    bottom: 0,
                    child: _OverflowCornerMarker(
                      details: markerDetails,
                      builder: markerBuilder,
                    ),
                  ),
                ],
              );
            }

            if (hasHiddenText) {
              body = Tooltip(
                message: text,
                waitDuration: const Duration(milliseconds: 350),
                constraints: const BoxConstraints(maxWidth: 900),
                ignorePointer: true,
                child: body,
              );
            }
          }
        }

        return Semantics(
          label: text,
          button: true,
          child: MouseRegion(
            cursor: readOnlyAsLink
                ? SystemMouseCursors.click
                : MouseCursor.defer,
            child: body,
          ),
        );
      },
    );
  }
}

class _StaticTextPainter extends CustomPainter {
  const _StaticTextPainter({
    required this.text,
    required this.style,
    required this.strutStyle,
    required this.singleLine,
    required this.textAlign,
    required this.direction,
    required this.textScaler,
    required this.maxWidth,
  });

  final String text;
  final TextStyle style;
  final StrutStyle? strutStyle;
  final bool singleLine;
  final TextAlign textAlign;
  final TextDirection direction;
  final TextScaler textScaler;
  final double maxWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final painter = TextPainter(
      text: TextSpan(text: LazyTextFieldLayout.measureText(text), style: style),
      textAlign: textAlign,
      textDirection: direction,
      textScaler: textScaler,
      strutStyle: strutStyle ?? StrutStyle.fromTextStyle(style),
      maxLines: singleLine ? 1 : null,
      ellipsis: singleLine ? '\u2026' : null,
    )..layout(maxWidth: maxWidth);

    painter.paint(canvas, Offset.zero);
  }

  @override
  bool shouldRepaint(covariant _StaticTextPainter old) {
    return text != old.text ||
        style != old.style ||
        strutStyle != old.strutStyle ||
        singleLine != old.singleLine ||
        textAlign != old.textAlign ||
        direction != old.direction ||
        textScaler != old.textScaler ||
        maxWidth != old.maxWidth;
  }
}

class _EditorBody extends StatelessWidget {
  const _EditorBody({
    required this.cellId,
    required this.controller,
    required this.focusNode,
    required this.style,
    required this.singleLine,
    required this.scrollController,
    required this.cursorWidth,
    this.strutStyle,
    this.textAlign = TextAlign.start,
    this.textAlignVertical,
    this.textDirection,
    this.onChanged,
    this.onSubmitted,
    this.onEditingComplete,
    this.onTapOutside,
    this.textInputAction,
    this.keyboardType,
    this.inputFormatters,
    this.minLines,
    this.maxLines,
    this.expands,
    this.scrollPhysics,
    this.enabled,
    this.readOnly = false,
    this.autofocus = true,
    this.showCursor,
    this.enableInteractiveSelection,
    this.selectionControls,
    this.cursorColor,
    this.cursorHeight,
    this.cursorRadius,
    this.maxLength,
    this.maxLengthEnforcement,
    this.undoController,
    this.statesController,
    this.autofillHints,
    this.contextMenuBuilder,
    this.mouseCursor,
  });

  final String cellId;
  final TextEditingController controller;
  final FocusNode focusNode;
  final TextStyle style;
  final StrutStyle? strutStyle;
  final bool singleLine;
  final ScrollController scrollController;
  final TextAlign textAlign;
  final TextAlignVertical? textAlignVertical;
  final TextDirection? textDirection;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final VoidCallback? onEditingComplete;
  final TapRegionCallback? onTapOutside;
  final TextInputAction? textInputAction;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final int? minLines;
  final int? maxLines;
  final bool? expands;
  final ScrollPhysics? scrollPhysics;
  final bool? enabled;
  final bool readOnly;
  final bool autofocus;
  final bool? showCursor;
  final bool? enableInteractiveSelection;
  final TextSelectionControls? selectionControls;
  final Color? cursorColor;
  final double cursorWidth;
  final double? cursorHeight;
  final Radius? cursorRadius;
  final int? maxLength;
  final MaxLengthEnforcement? maxLengthEnforcement;
  final UndoHistoryController? undoController;
  final WidgetStatesController? statesController;
  final Iterable<String>? autofillHints;
  final EditableTextContextMenuBuilder? contextMenuBuilder;
  final MouseCursor? mouseCursor;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final effectiveExpands = singleLine ? false : (expands ?? true);
    final effectiveMinLines = effectiveExpands ? null : minLines;
    final effectiveMaxLines = effectiveExpands
        ? null
        : maxLines ?? (singleLine ? 1 : null);
    final effectiveFormatters = singleLine
        ? <TextInputFormatter>[
            FilteringTextInputFormatter.deny(RegExp(r'[\r\n]')),
            ...?inputFormatters,
          ]
        : inputFormatters;

    final field = TextField(
      key: ValueKey('editor-$cellId'),
      controller: controller,
      focusNode: focusNode,
      undoController: undoController,
      decoration: null,
      autofocus: autofocus,
      enabled: enabled,
      readOnly: readOnly,
      showCursor: showCursor,
      style: style,
      strutStyle: strutStyle ?? StrutStyle.fromTextStyle(style),
      textAlign: textAlign,
      textAlignVertical: textAlignVertical,
      textDirection: textDirection,
      cursorColor: cursorColor ?? colorScheme.primary,
      cursorWidth: cursorWidth,
      cursorHeight: cursorHeight,
      cursorRadius: cursorRadius,
      expands: effectiveExpands,
      minLines: effectiveMinLines,
      maxLines: effectiveMaxLines,
      maxLength: maxLength,
      maxLengthEnforcement: maxLengthEnforcement,
      scrollPadding: EdgeInsets.zero,
      scrollController: scrollController,
      scrollPhysics: scrollPhysics ?? const ClampingScrollPhysics(),
      keyboardType:
          keyboardType ??
          (singleLine ? TextInputType.text : TextInputType.multiline),
      textInputAction:
          textInputAction ??
          (singleLine ? TextInputAction.done : TextInputAction.newline),
      inputFormatters: effectiveFormatters,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      onEditingComplete: onEditingComplete,
      onTapOutside: onTapOutside,
      enableInteractiveSelection: enableInteractiveSelection,
      selectionControls: selectionControls,
      statesController: statesController,
      autofillHints: autofillHints,
      contextMenuBuilder:
          contextMenuBuilder ?? _defaultEditorContextMenuBuilder,
      mouseCursor: mouseCursor,
    );

    return Material(
      type: MaterialType.transparency,
      child: ScrollbarTheme(
        data: ScrollbarTheme.of(
          context,
        ).copyWith(thickness: WidgetStateProperty.all(0)),
        child: ScrollConfiguration(
          behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
          child: field,
        ),
      ),
    );
  }
}

class _GutterScrollbar extends StatelessWidget {
  const _GutterScrollbar({
    required this.controller,
    required this.viewportHeight,
    required this.thickness,
    required this.alignment,
    super.key,
  });

  final ScrollController controller;
  final double viewportHeight;
  final double thickness;
  final AlignmentGeometry alignment;

  @override
  Widget build(BuildContext context) {
    final theme = ScrollbarTheme.of(context);
    final minThumbLength = theme.minThumbLength ?? 18.0;

    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        if (!controller.hasClients ||
            !controller.position.hasContentDimensions) {
          return const SizedBox.expand();
        }

        final position = controller.position;
        if (position.maxScrollExtent <= 0) {
          return const SizedBox.expand();
        }

        final contentExtent =
            position.maxScrollExtent + position.viewportDimension;
        final thumbExtent =
            (position.viewportDimension / contentExtent * viewportHeight).clamp(
              minThumbLength,
              viewportHeight,
            );
        final trackExtent = viewportHeight - thumbExtent;
        final thumbOffset = trackExtent <= 0
            ? 0.0
            : position.pixels / position.maxScrollExtent * trackExtent;

        final thumbColor =
            theme.thumbColor?.resolve(const <WidgetState>{}) ??
            Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.45);
        final radius = theme.radius ?? const Radius.circular(2);
        final effectiveThickness = thickness > 0
            ? thickness
            : theme.thickness?.resolve(const <WidgetState>{}) ?? 4.0;

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onVerticalDragUpdate: (details) {
            if (!controller.hasClients || trackExtent <= 0) return;
            final delta =
                details.delta.dy / trackExtent * position.maxScrollExtent;
            controller.jumpTo(
              (position.pixels + delta).clamp(0.0, position.maxScrollExtent),
            );
          },
          onTapDown: (details) {
            if (!controller.hasClients || trackExtent <= 0) return;
            final localY = details.localPosition.dy.clamp(0.0, viewportHeight);
            final target = ((localY - thumbExtent / 2) / trackExtent).clamp(
              0.0,
              1.0,
            );
            controller.jumpTo(target * position.maxScrollExtent);
          },
          child: CustomPaint(
            painter: _GutterScrollbarPainter(
              thumbOffset: thumbOffset,
              thumbExtent: thumbExtent,
              thickness: effectiveThickness,
              radius: radius,
              color: thumbColor,
              alignment: alignment.resolve(Directionality.of(context)),
            ),
            child: const SizedBox.expand(),
          ),
        );
      },
    );
  }
}

class _GutterScrollbarPainter extends CustomPainter {
  _GutterScrollbarPainter({
    required this.thumbOffset,
    required this.thumbExtent,
    required this.thickness,
    required this.radius,
    required this.color,
    required this.alignment,
  });

  final double thumbOffset;
  final double thumbExtent;
  final double thickness;
  final Radius radius;
  final Color color;
  final Alignment alignment;

  @override
  void paint(Canvas canvas, Size size) {
    final thumbX = ((alignment.x + 1) / 2 * (size.width - thickness)).clamp(
      0.0,
      size.width - thickness,
    );
    final thumbRect = Rect.fromLTWH(
      thumbX,
      thumbOffset,
      thickness,
      thumbExtent,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(thumbRect, radius),
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(covariant _GutterScrollbarPainter oldDelegate) {
    return thumbOffset != oldDelegate.thumbOffset ||
        thumbExtent != oldDelegate.thumbExtent ||
        thickness != oldDelegate.thickness ||
        color != oldDelegate.color ||
        alignment != oldDelegate.alignment;
  }
}

class _OverflowCornerMarker extends StatelessWidget {
  const _OverflowCornerMarker({required this.details, required this.builder});

  final LazyTextFieldOverflowMarkerDetails details;
  final LazyTextFieldOverflowMarkerBuilder builder;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      button: true,
      label: details.expanded ? 'Collapse overflow' : 'Expand overflow',
      onTap: details.onToggle,
      child: GestureDetector(
        key: const ValueKey('cell-overflow-corner-marker'),
        behavior: HitTestBehavior.opaque,
        onTap: details.onToggle,
        child: ExcludeSemantics(
          child: SizedBox.square(
            dimension: details.size,
            child: builder(context, details),
          ),
        ),
      ),
    );
  }
}

class _DefaultOverflowCornerMarker extends StatelessWidget {
  const _DefaultOverflowCornerMarker({
    required this.color,
    required this.outlined,
  });

  final Color color;
  final bool outlined;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _OverflowCornerMarkerPainter(color: color, outlined: outlined),
    );
  }
}

class _OverflowCornerMarkerPainter extends CustomPainter {
  const _OverflowCornerMarkerPainter({
    required this.color,
    required this.outlined,
  });

  final Color color;
  final bool outlined;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(size.width, 0)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    if (outlined) {
      final paint = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2;
      canvas.drawPath(path, paint);
    } else {
      final paint = Paint()
        ..color = color
        ..style = PaintingStyle.fill;
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _OverflowCornerMarkerPainter oldDelegate) =>
      color != oldDelegate.color || outlined != oldDelegate.outlined;
}

double _editableTextGutter(double cursorWidth) {
  return cursorWidth + 1;
}

/// Drops [InputDecoration.errorText] / [InputDecoration.error].
///
/// [InputDecoration.copyWith] cannot clear those fields with `null` because it
/// uses `errorText ?? this.errorText`.
InputDecoration _withoutErrorSlot(InputDecoration decoration) {
  if ((decoration.errorText == null || decoration.errorText!.isEmpty) &&
      decoration.error == null) {
    return decoration;
  }
  return InputDecoration(
    icon: decoration.icon,
    iconColor: decoration.iconColor,
    label: decoration.label,
    labelText: decoration.labelText,
    labelStyle: decoration.labelStyle,
    floatingLabelStyle: decoration.floatingLabelStyle,
    helper: decoration.helper,
    helperText: decoration.helperText,
    helperStyle: decoration.helperStyle,
    helperMaxLines: decoration.helperMaxLines,
    hintText: decoration.hintText,
    hint: decoration.hint,
    hintStyle: decoration.hintStyle,
    hintTextDirection: decoration.hintTextDirection,
    hintMaxLines: decoration.hintMaxLines,
    hintFadeDuration: decoration.hintFadeDuration,
    maintainHintSize: decoration.maintainHintSize,
    maintainLabelSize: decoration.maintainLabelSize,
    errorStyle: decoration.errorStyle,
    errorMaxLines: decoration.errorMaxLines,
    floatingLabelBehavior: decoration.floatingLabelBehavior,
    floatingLabelAlignment: decoration.floatingLabelAlignment,
    isCollapsed: decoration.isCollapsed,
    isDense: decoration.isDense,
    contentPadding: decoration.contentPadding,
    prefixIcon: decoration.prefixIcon,
    prefixIconConstraints: decoration.prefixIconConstraints,
    prefix: decoration.prefix,
    prefixText: decoration.prefixText,
    prefixStyle: decoration.prefixStyle,
    prefixIconColor: decoration.prefixIconColor,
    suffixIcon: decoration.suffixIcon,
    suffix: decoration.suffix,
    suffixText: decoration.suffixText,
    suffixStyle: decoration.suffixStyle,
    suffixIconColor: decoration.suffixIconColor,
    suffixIconConstraints: decoration.suffixIconConstraints,
    counter: decoration.counter,
    counterText: decoration.counterText,
    counterStyle: decoration.counterStyle,
    filled: decoration.filled,
    fillColor: decoration.fillColor,
    focusColor: decoration.focusColor,
    hoverColor: decoration.hoverColor,
    errorBorder: decoration.errorBorder,
    focusedBorder: decoration.focusedBorder,
    focusedErrorBorder: decoration.focusedErrorBorder,
    disabledBorder: decoration.disabledBorder,
    enabledBorder: decoration.enabledBorder,
    border: decoration.border,
    enabled: decoration.enabled,
    semanticCounterText: decoration.semanticCounterText,
    alignLabelWithHint: decoration.alignLabelWithHint,
    constraints: decoration.constraints,
    visualDensity: decoration.visualDensity,
  );
}

class _ValidationErrorPopup extends StatelessWidget {
  const _ValidationErrorPopup({required this.cellId, required this.message});

  final String cellId;
  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Material(
      key: LazyTextFieldKeys.errorPopup(cellId),
      elevation: 3,
      borderRadius: BorderRadius.circular(4),
      color: colorScheme.errorContainer,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 280),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Text(
            message,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onErrorContainer,
            ),
          ),
        ),
      ),
    );
  }
}

Widget _defaultEditorContextMenuBuilder(
  BuildContext context,
  EditableTextState editableTextState,
) {
  if (SystemContextMenu.isSupportedByField(editableTextState)) {
    return SystemContextMenu.editableText(editableTextState: editableTextState);
  }
  return AdaptiveTextSelectionToolbar.editableText(
    editableTextState: editableTextState,
  );
}
