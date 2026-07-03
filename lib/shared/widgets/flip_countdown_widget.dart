import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/app_typography.dart';

/// Yarış etkinlikleri için premium flip-saat tarzı geri sayım.
/// Klasik flip kart mekaniği: üst yarı menteşeden aşağı kapanır, alt yarı yeni rakamı gösterir.
class FlipCountdownWidget extends StatefulWidget {
  final DateTime targetDate;

  const FlipCountdownWidget({
    super.key,
    required this.targetDate,
  });

  @override
  State<FlipCountdownWidget> createState() => _FlipCountdownWidgetState();
}

class _FlipCountdownWidgetState extends State<FlipCountdownWidget> {
  late Timer _timer;
  int _days = 0;
  int _hours = 0;
  int _minutes = 0;
  int _seconds = 0;
  bool _isPast = false;

  DateTime _asLocalWallTime(DateTime dt) {
    return DateTime(
      dt.year,
      dt.month,
      dt.day,
      dt.hour,
      dt.minute,
      dt.second,
      dt.millisecond,
      dt.microsecond,
    );
  }

  @override
  void initState() {
    super.initState();
    _updateCountdown();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _updateCountdown());
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  void _updateCountdown() {
    final now = _asLocalWallTime(DateTime.now());
    final target = _asLocalWallTime(widget.targetDate);

    if (target.isBefore(now) || target.isAtSameMomentAs(now)) {
      if (!_isPast) {
        setState(() {
          _isPast = true;
          _days = 0;
          _hours = 0;
          _minutes = 0;
          _seconds = 0;
        });
      }
      return;
    }
    final diff = target.difference(now);
    setState(() {
      _days = diff.inDays;
      _hours = diff.inHours % 24;
      _minutes = diff.inMinutes % 60;
      _seconds = diff.inSeconds % 60;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isPast) return const SizedBox.shrink();

    final cs = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [cs.surfaceContainerHigh, cs.surfaceContainerHighest],
        ),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
          BoxShadow(
            color: cs.primary.withValues(alpha: 0.15),
            blurRadius: 20,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _FlipSegment(label: 'Gün', value: _days, segmentWidth: 38),
          _buildDotSeparator(cs),
          _FlipSegment(label: 'Sa', value: _hours),
          _buildDotSeparator(cs),
          _FlipSegment(label: 'Dk', value: _minutes),
          _buildDotSeparator(cs),
          _FlipSegment(label: 'Sn', value: _seconds),
        ],
      ),
    );
  }

  Widget _buildDotSeparator(ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Text(
        ':',
        style: AppTypography.titleLarge.copyWith(
          color: cs.onSurface.withValues(alpha: 0.5),
          fontWeight: FontWeight.w300,
          height: 1.2,
        ),
      ),
    );
  }
}

/// Tek bir basamak için klasik flip-saat kartı (üst yarı kapanır, alt yarı sabit).
class _FlipSegment extends StatefulWidget {
  final String label;
  final int value;
  final double segmentWidth;

  const _FlipSegment({
    required this.label,
    required this.value,
    this.segmentWidth = 26.0,
  });

  @override
  State<_FlipSegment> createState() => _FlipSegmentState();
}

class _FlipSegmentState extends State<_FlipSegment>
    with SingleTickerProviderStateMixin {
  late int _displayedValue;
  late int _nextValue;
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _displayedValue = widget.value;
    _nextValue = widget.value;
    _controller = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    _animation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Cubic(0.25, 0.1, 0.25, 1),
      ),
    );
  }

  @override
  void didUpdateWidget(_FlipSegment oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != _displayedValue && !_controller.isAnimating) {
      _nextValue = widget.value;
      _controller.forward(from: 0).then((_) {
        if (mounted) {
          setState(() => _displayedValue = widget.value);
          _controller.reset();
        }
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedBuilder(
          animation: _animation,
          builder: (_, __) => _SplitFlipCard(
            currentValue: _displayedValue,
            nextValue: _nextValue,
            flipT: _controller.isAnimating ? _animation.value : 0,
            width: widget.segmentWidth,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          widget.label,
          style: AppTypography.labelSmall.copyWith(
            color: cs.onSurfaceVariant,
            fontSize: 9,
            letterSpacing: 0.5,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

/// Üst yarı menteşeden aşağı kapanan, alt yarı sabit kalan split flip kartı.
class _SplitFlipCard extends StatelessWidget {
  final int currentValue;
  final int nextValue;
  final double flipT;
  final double width;

  const _SplitFlipCard({
    required this.currentValue,
    required this.nextValue,
    required this.flipT,
    this.width = 26.0,
  });

  static const double _h = 34.0;
  static const double _halfH = _h / 2;
  static const double _perspective = 0.0008;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final showBottomAsNext = flipT >= 0.5;

    return SizedBox(
      width: width,
      height: _h,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Stack(
          children: [
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  height: _halfH,
                  child: ClipRect(
                    child: Transform(
                      alignment: Alignment.bottomCenter,
                      transform: Matrix4.identity()
                        ..setEntry(3, 2, _perspective)
                        ..rotateX(-math.pi * flipT),
                      child: Stack(
                        children: [
                          _HalfDigitFace(
                            value: nextValue,
                            isTopHalf: true,
                            isBackFace: true,
                            width: width,
                            fullHeight: _h,
                          ),
                          _HalfDigitFace(
                            value: currentValue,
                            isTopHalf: true,
                            isBackFace: false,
                            width: width,
                            fullHeight: _h,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                SizedBox(
                  height: _halfH,
                  width: width,
                  child: ClipRect(
                    clipBehavior: Clip.hardEdge,
                    child: Stack(
                      clipBehavior: Clip.hardEdge,
                      children: [
                        Positioned(
                          top: -_halfH,
                          left: 0,
                          right: 0,
                          child: _FullDigitContent(
                            value: showBottomAsNext ? nextValue : currentValue,
                            width: width,
                            height: _h,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            Positioned(
              top: _halfH - 0.5,
              left: 0,
              right: 0,
              height: 1,
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: [
                      cs.outlineVariant,
                      cs.primary.withValues(alpha: 0.6),
                      cs.outlineVariant,
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Tam rakam içeriği (tek yüz).
class _FullDigitContent extends StatelessWidget {
  final int value;
  final double width;
  final double height;

  const _FullDigitContent({
    required this.value,
    required this.width,
    required this.height,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = value.toString().padLeft(2, '0');
    final style = AppTypography.titleMedium.copyWith(
      fontWeight: FontWeight.w700,
      color: cs.onSurface,
      fontSize: 18,
      height: 1.0,
      fontFeatures: const [FontFeature.tabularFigures()],
      shadows: [
        Shadow(
          color: Colors.black.withValues(alpha: 0.25),
          blurRadius: 2,
          offset: const Offset(0, 1),
        ),
      ],
    );
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
      ),
      alignment: Alignment.center,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(text, style: style),
      ),
    );
  }
}

/// Yarım yüz: sadece üst yarıyı gösterir (ClipRect + Stack ile taşma yok). Arkadaki yüz 180° döndürülür.
class _HalfDigitFace extends StatelessWidget {
  final int value;
  final bool isTopHalf;
  final bool isBackFace;
  final double width;
  final double fullHeight;

  const _HalfDigitFace({
    required this.value,
    required this.isTopHalf,
    required this.isBackFace,
    required this.width,
    required this.fullHeight,
  });

  @override
  Widget build(BuildContext context) {
    final halfH = fullHeight / 2;
    final content = _FullDigitContent(
      value: value,
      width: width,
      height: fullHeight,
    );

    final half = SizedBox(
      height: halfH,
      width: width,
      child: ClipRect(
        clipBehavior: Clip.hardEdge,
        child: Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: content,
            ),
          ],
        ),
      ),
    );

    if (isBackFace) {
      return Transform(
        alignment: Alignment.center,
        transform: Matrix4.rotationX(math.pi),
        child: half,
      );
    }
    return half;
  }
}
