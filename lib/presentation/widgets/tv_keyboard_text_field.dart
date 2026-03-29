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
  final FocusNode _focusNode = FocusNode();
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
    _focusNode.addListener(() {
      if (!_focusNode.hasFocus && _isEditing) {
        setState(() => _isEditing = false);
      }
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent || _isEditing) {
      return KeyEventResult.ignored;
    }

    if (_activationKeys.contains(event.logicalKey)) {
      setState(() => _isEditing = true);
      _focusNode.requestFocus();
      SystemChannels.textInput.invokeMethod<void>('TextInput.show');
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      onKeyEvent: _handleKeyEvent,
      child: TextField(
        focusNode: _focusNode,
        controller: widget.controller,
        readOnly: !_isEditing,
        showCursor: _isEditing,
        obscureText: widget.obscureText,
        style: widget.style,
        onTap: () {
          if (!_isEditing) {
            setState(() => _isEditing = true);
          }
        },
        onChanged: widget.onChanged,
        onSubmitted: (_) => setState(() => _isEditing = false),
        onEditingComplete: () => setState(() => _isEditing = false),
        decoration: widget.decoration,
      ),
    );
  }
}
