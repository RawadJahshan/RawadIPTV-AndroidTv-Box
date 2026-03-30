import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class TvFocusable extends StatefulWidget {
  final Widget Function(BuildContext context, bool isActive) builder;
  final VoidCallback? onTap;
  final BorderRadius borderRadius;
  final double focusedScale;
  final Duration duration;
  final bool autofocus;

  const TvFocusable({
    super.key,
    required this.builder,
    this.onTap,
    this.borderRadius = const BorderRadius.all(Radius.circular(12)),
    this.focusedScale = 1.02,
    this.duration = const Duration(milliseconds: 140),
    this.autofocus = false,
  });

  @override
  State<TvFocusable> createState() => _TvFocusableState();
}

class _TvFocusableState extends State<TvFocusable> {
  bool _isFocused = false;
  bool _isHovering = false;

  bool get _enableHover =>
      kIsWeb ||
      defaultTargetPlatform == TargetPlatform.windows ||
      defaultTargetPlatform == TargetPlatform.macOS ||
      defaultTargetPlatform == TargetPlatform.linux;

  @override
  Widget build(BuildContext context) {
    final isActive = _isFocused || _isHovering;

    return MouseRegion(
      onEnter: (_) {
        if (_enableHover) {
          setState(() => _isHovering = true);
        }
      },
      onExit: (_) {
        if (_enableHover) {
          setState(() => _isHovering = false);
        }
      },
      child: AnimatedScale(
        duration: widget.duration,
        scale: isActive ? widget.focusedScale : 1,
        child: ClipRRect(
          borderRadius: widget.borderRadius,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              autofocus: widget.autofocus,
              borderRadius: widget.borderRadius,
              onTap: widget.onTap,
              onFocusChange: (focused) {
                if (_isFocused != focused) {
                  setState(() => _isFocused = focused);
                }
              },
              child: widget.builder(context, isActive),
            ),
          ),
        ),
      ),
    );
  }
}
