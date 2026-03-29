import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class TvKeyboardTextField extends StatefulWidget {
  final TextEditingController controller;
  final InputDecoration decoration;
  final TextStyle? style;
  final bool obscureText;
  final ValueChanged<String>? onChanged;

  const TvKeyboardTextField({
    super.key,
    required this.controller,
    required this.decoration,
    this.style,
    this.obscureText = false,
    this.onChanged,
  });

  @override
  State<TvKeyboardTextField> createState() => _TvKeyboardTextFieldState();
}

class _TvKeyboardTextFieldState extends State<TvKeyboardTextField> {
  final FocusNode _traversalFocusNode = FocusNode(debugLabel: 'tvTextTraversal');
  final FocusNode _textFieldFocusNode = FocusNode(debugLabel: 'tvTextEditor');
  bool _isEditing = false;

  static const Set<LogicalKeyboardKey> _activationKeys = <LogicalKeyboardKey>{
    LogicalKeyboardKey.enter,
    LogicalKeyboardKey.select,
    LogicalKeyboardKey.gameButtonA,
    LogicalKeyboardKey.numpadEnter,
  };

  @override
  void initState() {
    super.initState();
    _textFieldFocusNode.canRequestFocus = false;

    _traversalFocusNode.addListener(_onFocusChange);
    _textFieldFocusNode.addListener(_onTextFieldFocusChange);
  }

  void _onFocusChange() {
    if (mounted) {
      setState(() {});
    }
  }

  void _onTextFieldFocusChange() {
    _onFocusChange();
    if (!_textFieldFocusNode.hasFocus && _isEditing) {
      _stopEditing();
    }
  }

  @override
  void dispose() {
    _traversalFocusNode
      ..removeListener(_onFocusChange)
      ..dispose();
    _textFieldFocusNode
      ..removeListener(_onTextFieldFocusChange)
      ..dispose();
    super.dispose();
  }

  void _startEditing() {
    if (_isEditing) {
      return;
    }

    setState(() {
      _isEditing = true;
      _textFieldFocusNode.canRequestFocus = true;
    });

    _textFieldFocusNode.requestFocus();
    SystemChannels.textInput.invokeMethod<void>('TextInput.show');
  }

  void _stopEditing() {
    if (!_isEditing) {
      return;
    }

    setState(() {
      _isEditing = false;
      _textFieldFocusNode.canRequestFocus = false;
    });

    _traversalFocusNode.requestFocus();
  }

  KeyEventResult _handleTraversalKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent || _isEditing) {
      return KeyEventResult.ignored;
    }

    if (_activationKeys.contains(event.logicalKey)) {
      _startEditing();
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _traversalFocusNode,
      onKeyEvent: _handleTraversalKeyEvent,
      child: Builder(
        builder: (context) {
          final hasFocus = _traversalFocusNode.hasFocus || _textFieldFocusNode.hasFocus;
          final decoration = widget.decoration.copyWith(
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: hasFocus ? Colors.white : Colors.transparent,
                width: hasFocus ? 2 : 1,
              ),
            ),
          );

          return AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              boxShadow: hasFocus
                  ? const [
                      BoxShadow(
                        color: Color(0x55FFFFFF),
                        blurRadius: 8,
                        spreadRadius: 1,
                      ),
                    ]
                  : null,
            ),
            child: TextField(
              focusNode: _textFieldFocusNode,
              controller: widget.controller,
              readOnly: !_isEditing,
              canRequestFocus: _isEditing,
              showCursor: _isEditing,
              obscureText: widget.obscureText,
              style: widget.style,
              onTap: _startEditing,
              onChanged: widget.onChanged,
              onSubmitted: (_) => _stopEditing(),
              onEditingComplete: _stopEditing,
              decoration: decoration,
            ),
          );
        },
      ),
    );
  }
}
