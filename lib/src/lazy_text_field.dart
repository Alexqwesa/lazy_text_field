import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lazy_text_field/src/lazy_input_decoration.dart';
import 'package:lazy_text_field/src/lazy_text_field_keys.dart';
import 'package:lazy_text_field/src/lazy_text_field_layout.dart';
import 'package:lazy_text_field/src/lazy_text_field_metrics.dart';

/// Builds the read-only overflow marker shown when static text is clipped.
typedef LazyTextFieldOverflowMarkerBuilder =
    Widget Function(
      BuildContext context,
      LazyTextFieldOverflowMarkerDetails details,
    );

/// State passed to [LazyTextFieldOverflowMarkerBuilder].
class LazyTextFieldOverflowMarkerDetails {
  const LazyTextFieldOverflowMarkerDetails({
    required this.size,
    required this.color,
    required this.expanded,
    required this.hasHiddenText,
    required this.onToggle,
  });

  final double size;
  final Color color;
  final bool expanded;
  final bool hasHiddenText;
  final VoidCallback? onToggle;
}

/// A table/grid cell that stays lazy in read-only mode and mounts a real
/// [TextField] only while editing.
///
/// Pass `controller` and `focusNode` when [isEditing] is true; pass `null` for
/// both otherwise so read-only cells avoid edit allocations.
class LazyTextField extends StatefulWidget {
  const LazyTextField({
    required this.cellId,
    required this.text,
    required this.isEditing,
    required this.onStartEditing,
    this.controller,
    this.focusNode,
    super.key,
    this.singleLine = false,
    this.style,
    this.strutStyle,
    this.textAlign = TextAlign.start,
    this.textDirection,
    this.padding = kDefaultLazyTextFieldPadding,
    this.decoration = const LazyInputDecoration(),
    this.decorationVisibility = LazyInputDecorationVisibility.editing,
    this.minHeight = 0,
    this.maxHeight,
    this.scrollbarGutter = 12,
    this.readOnlyAsLink = false,
    this.reservedTrailingWidth = 0,
    this.readOnlyOverflowExpanded = false,
    this.onReadOnlyOverflowToggle,
    this.overflowMarkerSize = 14,
    this.overflowMarkerColor,
    this.expandedOverflowMarkerColor,
    this.overflowMarkerBuilder = LazyTextField.defaultOverflowMarkerBuilder,
    this.onCalendarPressed,
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
    this.undoController,
    this.statesController,
    this.autofillHints = const <String>[],
    this.contextMenuBuilder,
    this.mouseCursor,
  }) : assert(!isEditing || controller != null),
       assert(!isEditing || focusNode != null);

  final String cellId;
  final String text;
  final bool isEditing;
  final TextEditingController? controller;
  final FocusNode? focusNode;
  final VoidCallback onStartEditing;
  final VoidCallback? onStopEditing;
  final bool singleLine;
  final TextStyle? style;
  final StrutStyle? strutStyle;
  final TextAlign textAlign;
  final TextDirection? textDirection;
  final EdgeInsetsGeometry padding;
  final LazyInputDecoration? decoration;
  final LazyInputDecorationVisibility decorationVisibility;
  final double minHeight;
  final double? maxHeight;
  final double scrollbarGutter;
  final bool readOnlyAsLink;
  final double reservedTrailingWidth;
  final bool readOnlyOverflowExpanded;
  final VoidCallback? onReadOnlyOverflowToggle;
  final double overflowMarkerSize;
  final Color? overflowMarkerColor;
  final Color? expandedOverflowMarkerColor;
  final LazyTextFieldOverflowMarkerBuilder? overflowMarkerBuilder;
  final VoidCallback? onCalendarPressed;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final VoidCallback? onEditingComplete;
  final TapRegionCallback? onTapOutside;
  final ValueChanged<TapDownDetails>? onSecondaryTapDown;
  final ValueChanged<LongPressStartDetails>? onLongPressStart;
  final TextInputAction? textInputAction;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final int? minLines;
  final int? maxLines;
  final bool? expands;
  final ScrollController? scrollController;
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
  bool _isHovering = false;
  String? _lastLayoutText;

  @override
  void initState() {
    super.initState();
    _syncControllerListener();
    _syncFocusNodeListener();
  }

  @override
  void didUpdateWidget(covariant LazyTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncControllerListener();
    _syncFocusNodeListener();

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
    if (!_decorationVisible || !mounted) return;
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

  double? _boundedMaxHeight(BoxConstraints constraints) {
    if (widget.maxHeight != null) {
      return widget.maxHeight;
    }
    if (constraints.hasBoundedHeight && constraints.maxHeight.isFinite) {
      return constraints.maxHeight;
    }
    return null;
  }

  bool get _decorationCanAffectLayout {
    return widget.decoration != null &&
        widget.decorationVisibility != LazyInputDecorationVisibility.never;
  }

  bool get _decorationVisible {
    return switch (widget.decorationVisibility) {
      LazyInputDecorationVisibility.never => false,
      LazyInputDecorationVisibility.editing => widget.isEditing,
      LazyInputDecorationVisibility.always => true,
    };
  }

  @override
  Widget build(BuildContext context) {
    final direction = widget.textDirection ?? Directionality.of(context);
    final resolvedPadding = widget.padding.resolve(direction);
    final resolvedStyle = _resolvedStyle(context);
    final value = widget.isEditing
        ? widget.controller?.text ?? widget.text
        : widget.text;
    final decoration = widget.decoration;
    final decorationAffectsLayout = _decorationCanAffectLayout;
    final decorationVisible = _decorationVisible;
    final prefixWidth =
        decorationAffectsLayout && decoration?.hasPrefixIcon == true
        ? _iconSlotWidth(decoration?.prefixIconConstraints)
        : 0.0;
    final suffixWidth =
        decorationAffectsLayout && decoration?.hasSuffixIcon == true
        ? _iconSlotWidth(decoration?.suffixIconConstraints)
        : 0.0;

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final boundedMaxHeight = _boundedMaxHeight(constraints);
        final layout = LazyTextFieldLayout.computeFromContext(
          context,
          text: value,
          width: width,
          padding: widget.padding,
          singleLine: widget.singleLine,
          style: resolvedStyle,
          strutStyle: widget.strutStyle,
          minHeight: widget.minHeight,
          reservedLeadingWidth: prefixWidth,
          reservedTrailingWidth: suffixWidth + widget.reservedTrailingWidth,
          maxHeight: boundedMaxHeight,
          scrollbarGutter: widget.scrollbarGutter,
          editableTextGutter: _editableTextGutter(widget.cursorWidth),
        );
        final textAreaHeight = math.max<double>(
          0,
          layout.height - resolvedPadding.vertical,
        );
        final needsScrollbar =
            widget.isEditing &&
            layout.hasVerticalOverflow &&
            boundedMaxHeight != null;

        final textColumn = SizedBox(
          key: LazyTextFieldKeys.textViewport(widget.cellId),
          width: layout.textViewportWidth,
          height: textAreaHeight,
          child: ClipRect(
            child: widget.isEditing
                ? _EditorBody(
                    cellId: widget.cellId,
                    controller: widget.controller!,
                    focusNode: widget.focusNode!,
                    style: resolvedStyle,
                    strutStyle: widget.strutStyle,
                    singleLine: widget.singleLine,
                    scrollController: _scrollControllerFor(),
                    textAlign: widget.textAlign,
                    textDirection: widget.textDirection,
                    hintText: decorationVisible ? decoration?.hintText : null,
                    hintStyle: decoration?.hintStyle,
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
                    enabled: widget.enabled ?? decoration?.enabled,
                    readOnly: widget.readOnly,
                    autofocus: widget.autofocus,
                    showCursor: widget.showCursor,
                    enableInteractiveSelection:
                        widget.enableInteractiveSelection,
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
                  )
                : _StaticTextBody(
                    text: widget.text,
                    style: resolvedStyle,
                    singleLine: widget.singleLine,
                    maxWidth: layout.textViewportWidth,
                    textLayoutWidth: layout.textLayoutWidth,
                    textAreaHeight: textAreaHeight,
                    readOnlyAsLink: widget.readOnlyAsLink,
                    hasVerticalOverflow: layout.hasVerticalOverflow,
                    overflowExpanded: widget.readOnlyOverflowExpanded,
                    onOverflowToggle: widget.onReadOnlyOverflowToggle,
                    overflowMarkerSize: widget.overflowMarkerSize,
                    overflowMarkerColor: widget.overflowMarkerColor,
                    expandedOverflowMarkerColor:
                        widget.expandedOverflowMarkerColor,
                    overflowMarkerBuilder: widget.overflowMarkerBuilder,
                    hintText: decorationVisible ? decoration?.hintText : null,
                    hintStyle: decoration?.hintStyle,
                  ),
          ),
        );

        final textRow = Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (prefixWidth > 0)
              _IconSlot(
                key: LazyTextFieldKeys.prefixIcon(widget.cellId),
                width: prefixWidth,
                height: textAreaHeight,
                visible: decorationVisible,
                child: decoration?.prefixIcon,
              ),
            textColumn,
            if (layout.reservedScrollbarWidth > 0)
              SizedBox(
                width: layout.reservedScrollbarWidth,
                height: textAreaHeight,
                child: needsScrollbar
                    ? _GutterScrollbar(
                        key: LazyTextFieldKeys.scrollbar(widget.cellId),
                        controller: _scrollControllerFor(),
                        viewportHeight: textAreaHeight,
                      )
                    : const SizedBox.shrink(),
              ),
            if (suffixWidth > 0)
              _IconSlot(
                key: LazyTextFieldKeys.suffixIcon(widget.cellId),
                width: suffixWidth,
                height: textAreaHeight,
                visible: decorationVisible,
                child: decoration?.suffixIcon,
              ),
          ],
        );

        final content = Padding(
          padding: resolvedPadding,
          child: widget.onCalendarPressed != null
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    textRow,
                    SizedBox(
                      width: widget.reservedTrailingWidth,
                      child: IconButton(
                        icon: const Icon(Icons.calendar_today, size: 20),
                        onPressed: widget.onCalendarPressed,
                        padding: EdgeInsets.zero,
                      ),
                    ),
                  ],
                )
              : textRow,
        );

        final frameKey = widget.isEditing
            ? LazyTextFieldKeys.editorSurface(widget.cellId)
            : null;
        final legacySurfaceKey = widget.isEditing
            ? LazyTextFieldKeys.legacyEditorFrame(widget.cellId)
            : LazyTextFieldKeys.legacyReadOnlySurface(widget.cellId);

        Widget framed = _LazyDecorationFrame(
          key: legacySurfaceKey,
          decoration: decoration,
          visible: decorationVisible,
          isFocused: widget.focusNode?.hasFocus ?? false,
          isHovering: _isHovering,
          textDirection: direction,
          child: SizedBox(width: double.infinity, child: content),
        );
        if (frameKey != null) {
          framed = KeyedSubtree(key: frameKey, child: framed);
        }

        Widget root = MouseRegion(
          cursor: widget.mouseCursor ?? MouseCursor.defer,
          onEnter: (_) => _setHovering(true),
          onExit: (_) => _setHovering(false),
          child: SizedBox(
            key: LazyTextFieldKeys.root(widget.cellId),
            width: width,
            height: layout.height,
            child: framed,
          ),
        );

        if (!widget.isEditing) {
          root = GestureDetector(
            key: LazyTextFieldKeys.staticSurface(widget.cellId),
            behavior: HitTestBehavior.opaque,
            onTap: widget.onStartEditing,
            onSecondaryTapDown: widget.onSecondaryTapDown,
            onLongPressStart: widget.onLongPressStart,
            child: root,
          );
        }

        return root;
      },
    );
  }

  void _setHovering(bool value) {
    if (_isHovering == value) return;
    _isHovering = value;
    if (_decorationVisible && mounted) {
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
}

class _StaticTextBody extends StatelessWidget {
  const _StaticTextBody({
    required this.text,
    required this.style,
    required this.singleLine,
    required this.maxWidth,
    required this.textLayoutWidth,
    required this.textAreaHeight,
    required this.readOnlyAsLink,
    required this.hasVerticalOverflow,
    required this.overflowExpanded,
    required this.overflowMarkerSize,
    this.onOverflowToggle,
    this.overflowMarkerColor,
    this.expandedOverflowMarkerColor,
    this.overflowMarkerBuilder,
    this.hintText,
    this.hintStyle,
  });

  final String text;
  final TextStyle style;
  final bool singleLine;
  final double maxWidth;
  final double textLayoutWidth;
  final double textAreaHeight;
  final bool readOnlyAsLink;
  final bool hasVerticalOverflow;
  final bool overflowExpanded;
  final VoidCallback? onOverflowToggle;
  final double overflowMarkerSize;
  final Color? overflowMarkerColor;
  final Color? expandedOverflowMarkerColor;
  final LazyTextFieldOverflowMarkerBuilder? overflowMarkerBuilder;
  final String? hintText;
  final TextStyle? hintStyle;

  @override
  Widget build(BuildContext context) {
    final direction = Directionality.of(context);
    final textScaler = MediaQuery.textScalerOf(context);
    final displayText = text.isEmpty ? hintText ?? text : text;
    final displayStyle = text.isEmpty && hintText != null
        ? style.merge(hintStyle)
        : style;

    final paintedText = CustomPaint(
      painter: _StaticTextPainter(
        text: displayText,
        style: displayStyle,
        singleLine: singleLine,
        direction: direction,
        textScaler: textScaler,
        maxWidth: textLayoutWidth,
      ),
      size: Size(maxWidth, textAreaHeight),
    );

    Widget body = paintedText;

    if (text.isNotEmpty) {
      final layoutPainter = TextPainter(
        text: TextSpan(
          text: LazyTextFieldLayout.measureText(text),
          style: style,
        ),
        textDirection: direction,
        textScaler: textScaler,
        strutStyle: StrutStyle.fromTextStyle(style),
        maxLines: singleLine ? 1 : null,
        ellipsis: singleLine ? '\u2026' : null,
      )..layout(maxWidth: textLayoutWidth);

      final overflowsWidth = singleLine && layoutPainter.didExceedMaxLines;
      final overflowsHeight = !singleLine && hasVerticalOverflow;
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
          final marker = _OverflowCornerMarker(
            details: markerDetails,
            builder: markerBuilder,
          );

          body = Stack(
            fit: StackFit.passthrough,
            children: [
              paintedText,
              Positioned(right: 0, bottom: 0, child: marker),
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
        cursor: readOnlyAsLink ? SystemMouseCursors.click : MouseCursor.defer,
        child: body,
      ),
    );
  }
}

class _StaticTextPainter extends CustomPainter {
  const _StaticTextPainter({
    required this.text,
    required this.style,
    required this.singleLine,
    required this.direction,
    required this.textScaler,
    required this.maxWidth,
  });

  final String text;
  final TextStyle style;
  final bool singleLine;
  final TextDirection direction;
  final TextScaler textScaler;
  final double maxWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final painter = TextPainter(
      text: TextSpan(text: LazyTextFieldLayout.measureText(text), style: style),
      textDirection: direction,
      textScaler: textScaler,
      strutStyle: StrutStyle.fromTextStyle(style),
      maxLines: singleLine ? 1 : null,
      ellipsis: singleLine ? '\u2026' : null,
    )..layout(maxWidth: maxWidth);

    painter.paint(canvas, Offset.zero);
  }

  @override
  bool shouldRepaint(covariant _StaticTextPainter old) {
    return text != old.text ||
        style != old.style ||
        singleLine != old.singleLine ||
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
    this.textDirection,
    this.hintText,
    this.hintStyle,
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
  final TextDirection? textDirection;
  final String? hintText;
  final TextStyle? hintStyle;
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
    final effectiveExpands = expands ?? true;
    final effectiveMinLines = effectiveExpands ? null : minLines;
    final effectiveMaxLines = effectiveExpands
        ? null
        : maxLines ?? (singleLine ? 1 : null);

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
      inputFormatters: inputFormatters,
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
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (controller.text.isEmpty && hintText != null)
                IgnorePointer(
                  child: Align(
                    alignment: _alignmentFor(
                      textAlign,
                      Directionality.of(context),
                    ),
                    child: Text(
                      hintText!,
                      maxLines: singleLine ? 1 : null,
                      overflow: singleLine
                          ? TextOverflow.ellipsis
                          : TextOverflow.clip,
                      style: style.merge(hintStyle),
                      textAlign: textAlign,
                      textDirection: textDirection,
                    ),
                  ),
                ),
              field,
            ],
          ),
        ),
      ),
    );
  }
}

class _IconSlot extends StatelessWidget {
  const _IconSlot({
    required this.width,
    required this.height,
    required this.visible,
    this.child,
    super.key,
  });

  final double width;
  final double height;
  final bool visible;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: height,
      child: visible && child != null
          ? Center(child: child)
          : const SizedBox.shrink(),
    );
  }
}

class _LazyDecorationFrame extends StatelessWidget {
  const _LazyDecorationFrame({
    required this.decoration,
    required this.visible,
    required this.isFocused,
    required this.isHovering,
    required this.textDirection,
    required this.child,
    super.key,
  });

  final LazyInputDecoration? decoration;
  final bool visible;
  final bool isFocused;
  final bool isHovering;
  final TextDirection textDirection;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!visible || decoration == null) {
      return child;
    }

    final states = <WidgetState>{
      if (!decoration!.enabled) WidgetState.disabled,
      if (decoration!.hasError) WidgetState.error,
      if (isFocused) WidgetState.focused,
      if (isHovering) WidgetState.hovered,
    };

    return CustomPaint(
      painter: _LazyDecorationPainter(
        decoration: decoration!,
        border: _resolveBorder(context, decoration!, states),
        fillColor: _resolveFillColor(context, decoration!, states),
        textDirection: textDirection,
      ),
      child: child,
    );
  }
}

class _LazyDecorationPainter extends CustomPainter {
  const _LazyDecorationPainter({
    required this.decoration,
    required this.border,
    required this.fillColor,
    required this.textDirection,
  });

  final LazyInputDecoration decoration;
  final InputBorder border;
  final Color? fillColor;
  final TextDirection textDirection;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    if (fillColor != null) {
      final paint = Paint()..color = fillColor!;
      final path = border == InputBorder.none
          ? (Path()..addRect(rect))
          : border.getOuterPath(rect, textDirection: textDirection);
      canvas.drawPath(path, paint);
    }
    if (border != InputBorder.none) {
      border.paint(canvas, rect, textDirection: textDirection);
    }
  }

  @override
  bool shouldRepaint(covariant _LazyDecorationPainter oldDelegate) {
    return decoration != oldDelegate.decoration ||
        border != oldDelegate.border ||
        fillColor != oldDelegate.fillColor ||
        textDirection != oldDelegate.textDirection;
  }
}

class _GutterScrollbar extends StatelessWidget {
  const _GutterScrollbar({
    required this.controller,
    required this.viewportHeight,
    super.key,
  });

  final ScrollController controller;
  final double viewportHeight;

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
        final thickness =
            theme.thickness?.resolve(const <WidgetState>{}) ?? 4.0;

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
              thickness: thickness,
              radius: radius,
              color: thumbColor,
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
  });

  final double thumbOffset;
  final double thumbExtent;
  final double thickness;
  final Radius radius;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final thumbRect = Rect.fromLTWH(
      (size.width - thickness) / 2,
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
        color != oldDelegate.color;
  }
}

class _OverflowCornerMarker extends StatelessWidget {
  const _OverflowCornerMarker({required this.details, required this.builder});

  final LazyTextFieldOverflowMarkerDetails details;
  final LazyTextFieldOverflowMarkerBuilder builder;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      key: const ValueKey('cell-overflow-corner-marker'),
      behavior: HitTestBehavior.opaque,
      onTap: details.onToggle,
      child: SizedBox.square(
        dimension: details.size,
        child: builder(context, details),
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

InputBorder _resolveBorder(
  BuildContext context,
  LazyInputDecoration decoration,
  Set<WidgetState> states,
) {
  final candidate = switch ((
    states.contains(WidgetState.disabled),
    states.contains(WidgetState.focused),
    states.contains(WidgetState.error),
  )) {
    (true, _, true) => decoration.errorBorder ?? decoration.disabledBorder,
    (true, _, false) => decoration.disabledBorder,
    (false, true, true) => decoration.focusedErrorBorder,
    (false, true, false) => decoration.focusedBorder,
    (false, false, true) => decoration.errorBorder,
    (false, false, false) => decoration.enabledBorder,
  };

  return WidgetStateProperty.resolveAs<InputBorder?>(
        candidate ?? decoration.border,
        states,
      ) ??
      _defaultBorder(context, states);
}

InputBorder _defaultBorder(BuildContext context, Set<WidgetState> states) {
  final theme = Theme.of(context);
  final colorScheme = theme.colorScheme;
  final side = switch ((
    states.contains(WidgetState.disabled),
    states.contains(WidgetState.focused),
    states.contains(WidgetState.error),
    states.contains(WidgetState.hovered),
  )) {
    (true, _, _, _) => BorderSide(color: theme.disabledColor),
    (false, true, true, _) => BorderSide(color: colorScheme.error, width: 2),
    (false, true, false, _) => BorderSide(color: colorScheme.primary, width: 2),
    (false, false, true, _) => BorderSide(color: colorScheme.error),
    (false, false, false, true) => BorderSide(color: colorScheme.onSurface),
    (false, false, false, false) => BorderSide(color: theme.dividerColor),
  };
  return UnderlineInputBorder(borderSide: side);
}

Color? _resolveFillColor(
  BuildContext context,
  LazyInputDecoration decoration,
  Set<WidgetState> states,
) {
  if (decoration.filled != true) {
    return null;
  }
  if (states.contains(WidgetState.disabled)) {
    return decoration.fillColor ??
        Theme.of(context).disabledColor.withValues(alpha: 0.08);
  }
  if (states.contains(WidgetState.focused) && decoration.focusColor != null) {
    return decoration.focusColor;
  }
  if (states.contains(WidgetState.hovered) && decoration.hoverColor != null) {
    return decoration.hoverColor;
  }
  return decoration.fillColor ??
      Theme.of(context).colorScheme.surfaceContainerHighest;
}

double _iconSlotWidth(BoxConstraints? constraints) {
  if (constraints == null) {
    return kMinInteractiveDimension;
  }
  if (constraints.hasTightWidth && constraints.maxWidth.isFinite) {
    return constraints.maxWidth;
  }
  if (constraints.minWidth.isFinite && constraints.minWidth > 0) {
    return constraints.minWidth;
  }
  if (constraints.maxWidth.isFinite) {
    return constraints.maxWidth;
  }
  return kMinInteractiveDimension;
}

double _editableTextGutter(double cursorWidth) {
  return cursorWidth + 1;
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

Alignment _alignmentFor(TextAlign textAlign, TextDirection direction) {
  return switch (textAlign) {
    TextAlign.center => Alignment.center,
    TextAlign.right => Alignment.centerRight,
    TextAlign.end =>
      direction == TextDirection.rtl
          ? Alignment.centerLeft
          : Alignment.centerRight,
    TextAlign.left => Alignment.centerLeft,
    TextAlign.start =>
      direction == TextDirection.rtl
          ? Alignment.centerRight
          : Alignment.centerLeft,
    TextAlign.justify =>
      direction == TextDirection.rtl
          ? Alignment.centerRight
          : Alignment.centerLeft,
  };
}
