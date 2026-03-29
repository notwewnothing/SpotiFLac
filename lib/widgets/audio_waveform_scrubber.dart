import 'package:flutter/material.dart';

class AppleProgressBar extends StatefulWidget {
  final Duration position;
  final Duration duration;
  final ValueChanged<Duration> onSeek;

  const AppleProgressBar({
    super.key,
    required this.position,
    required this.duration,
    required this.onSeek,
  });

  @override
  State<AppleProgressBar> createState() => _AppleProgressBarState();
}

class _AppleProgressBarState extends State<AppleProgressBar> with SingleTickerProviderStateMixin {
  late AnimationController _expansionController;
  bool _isDragging = false;
  double _dragProgress = 0.0;

  @override
  void initState() {
    super.initState();
    _expansionController = AnimationController(vsync: this, duration: const Duration(milliseconds: 150));
  }

  @override
  void dispose() {
    _expansionController.dispose();
    super.dispose();
  }

  void _handleDragStart(DragStartDetails details, double maxWidth) {
    _startSeek(details.localPosition.dx, maxWidth);
  }

  void _handleTapDown(TapDownDetails details, double maxWidth) {
    _startSeek(details.localPosition.dx, maxWidth);
  }

  void _startSeek(double dx, double maxWidth) {
    setState(() {
      _isDragging = true;
      _dragProgress = (dx / maxWidth).clamp(0.0, 1.0);
    });
    _expansionController.forward();
    _seekToProgress();
  }

  void _handleDragUpdate(DragUpdateDetails details, double maxWidth) {
    setState(() {
      _dragProgress = (details.localPosition.dx / maxWidth).clamp(0.0, 1.0);
    });
    _seekToProgress();
  }

  void _handleDragEnd() {
    setState(() {
      _isDragging = false;
    });
    _expansionController.reverse();
  }

  void _seekToProgress() {
    if (widget.duration.inMilliseconds == 0) return;
    final seekMillis = (_dragProgress * widget.duration.inMilliseconds).round();
    widget.onSeek(Duration(milliseconds: seekMillis));
  }

  @override
  Widget build(BuildContext context) {
    final actualProgress = widget.duration.inMilliseconds > 0
        ? (widget.position.inMilliseconds / widget.duration.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;
    
    final displayProgress = _isDragging ? _dragProgress : actualProgress;

    return LayoutBuilder(
      builder: (context, constraints) {
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragStart: (d) => _handleDragStart(d, constraints.maxWidth),
          onHorizontalDragUpdate: (d) => _handleDragUpdate(d, constraints.maxWidth),
          onHorizontalDragEnd: (_) => _handleDragEnd(),
          onHorizontalDragCancel: _handleDragEnd,
          onTapDown: (d) => _handleTapDown(d, constraints.maxWidth),
          onTapUp: (_) => _handleDragEnd(),
          onTapCancel: _handleDragEnd,
          child: Container(
            height: 40,
            alignment: Alignment.center,
            child: AnimatedBuilder(
              animation: _expansionController,
              builder: (context, child) {
                // When dragging, the bar gets slightly thicker (Apple style)
                final trackHeight = 4.0 + (_expansionController.value * 4.0);
                final thumbSize = 6.0 + (_expansionController.value * 12.0);

                return Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.centerLeft,
                  children: [
                    // Background track
                    Container(
                      height: trackHeight,
                      width: constraints.maxWidth,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(trackHeight / 2),
                      ),
                    ),
                    // Active track
                    Container(
                      height: trackHeight,
                      width: constraints.maxWidth * displayProgress,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(trackHeight / 2),
                      ),
                    ),
                    // Thumb (hidden until dragged, fully visible when dragged)
                    Positioned(
                      left: (constraints.maxWidth * displayProgress) - (thumbSize / 2),
                      child: Opacity(
                        opacity: _expansionController.value,
                        child: Container(
                          width: thumbSize,
                          height: thumbSize,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.2),
                                blurRadius: 4,
                                spreadRadius: 1,
                              )
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }
}

