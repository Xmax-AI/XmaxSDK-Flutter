import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../localization/xlab_localization.dart';
import 'realtime_audio_controls.dart';

Future<void> showRealtimeAudioVolumeMenu({
  required BuildContext context,
  required BuildContext sourceContext,
  required RealtimeAudioControls controls,
  required bool preferLeft,
  ValueChanged<Route<void>>? onPresented,
}) {
  final source = sourceContext.findRenderObject() as RenderBox?;
  final navigator = Navigator.of(context, rootNavigator: true);
  final overlay = navigator.overlay?.context.findRenderObject() as RenderBox?;
  if (source == null || overlay == null || !source.attached) {
    return Future<void>.value();
  }
  final anchor =
      source.localToGlobal(Offset.zero, ancestor: overlay) & source.size;
  final route = RawDialogRoute<void>(
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 150),
    pageBuilder: (context, _, _) => LayoutBuilder(
      builder: (context, constraints) {
        final layout = _VolumeMenuLayout(
          anchor: anchor,
          safeInsets: MediaQuery.paddingOf(context),
          preferLeft: preferLeft,
        );
        final size = layout.getConstraintsForChild(constraints).biggest;
        final position = layout.getPositionForChild(constraints.biggest, size);
        return CustomSingleChildLayout(
          delegate: layout,
          child: CustomPaint(
            painter: _VolumeMenuArrow(
              anchor: anchor.center - position,
              preferLeft: layout.canPlaceLeft(size),
              color: _volumeMenuColor(context),
            ),
            child: RealtimeAudioVolumeMenu(controls: controls),
          ),
        );
      },
    ),
    transitionBuilder: (context, animation, _, child) =>
        FadeTransition(opacity: animation, child: child),
  );
  onPresented?.call(route);
  return navigator.push(route);
}

class RealtimeAudioVolumeMenu extends StatelessWidget {
  const RealtimeAudioVolumeMenu({required this.controls, super.key});

  final RealtimeAudioControls controls;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final title = XLabLocalization.shared.text('realtime.volume.remote');
    return Material(
      key: const ValueKey('realtime-volume-menu'),
      color: _volumeMenuColor(context),
      borderRadius: BorderRadius.circular(14),
      elevation: 8,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: AnimatedBuilder(
          animation: controls,
          builder: (context, _) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                height: 16,
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.2,
                          fontWeight: FontWeight.w500,
                          color: dark ? Colors.white : Colors.black,
                        ),
                      ),
                    ),
                    Text(
                      '${(controls.value * 100).round()}%',
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.2,
                        fontFeatures: const [FontFeature.tabularFigures()],
                        color: dark
                            ? const Color(0x99FFFFFF)
                            : const Color(0x99000000),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              SizedBox(
                height: 34,
                child: Semantics(
                  label: title,
                  value: '${(controls.value * 100).round()}%',
                  child: CupertinoSlider(
                    key: const ValueKey('realtime-remote-volume-slider'),
                    value: controls.value,
                    activeColor: const Color(0xFFFF2D55),
                    onChanged: (value) => unawaited(controls.setVolume(value)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Color _volumeMenuColor(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
    ? const Color(0xFF2C2C2E)
    : const Color(0xFFF2F2F7);

class _VolumeMenuArrow extends CustomPainter {
  const _VolumeMenuArrow({
    required this.anchor,
    required this.preferLeft,
    required this.color,
  });

  final Offset anchor;
  final bool preferLeft;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path();
    if (preferLeft) {
      final y = anchor.dy.clamp(14.0, size.height - 14);
      path.moveTo(size.width, y - 7);
      path.lineTo(size.width + 8, y);
      path.lineTo(size.width, y + 7);
    } else {
      final x = anchor.dx.clamp(14.0, math.max(14, size.width - 14)).toDouble();
      path.moveTo(x - 7, 0);
      path.lineTo(x, -8);
      path.lineTo(x + 7, 0);
    }
    path.close();
    canvas.drawShadow(path, Colors.black54, 4, false);
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_VolumeMenuArrow oldDelegate) =>
      anchor != oldDelegate.anchor ||
      preferLeft != oldDelegate.preferLeft ||
      color != oldDelegate.color;
}

class _VolumeMenuLayout extends SingleChildLayoutDelegate {
  const _VolumeMenuLayout({
    required this.anchor,
    required this.safeInsets,
    required this.preferLeft,
  });

  final Rect anchor;
  final EdgeInsets safeInsets;
  final bool preferLeft;

  bool canPlaceLeft(Size childSize) =>
      preferLeft && anchor.left - childSize.width - 8 >= safeInsets.left + 12;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      BoxConstraints.tightFor(
        width: math.min(
          260,
          math.max(0, constraints.maxWidth - safeInsets.horizontal - 24),
        ),
        height: 82,
      );

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final left = canPlaceLeft(childSize);
    final x = left
        ? anchor.left - childSize.width - 8
        : anchor.center.dx - childSize.width / 2;
    final y = left
        ? anchor.center.dy - childSize.height / 2
        : anchor.bottom + 8;
    return Offset(
      x.clamp(
        safeInsets.left + 12,
        math.max(
          safeInsets.left + 12,
          size.width - safeInsets.right - childSize.width - 12,
        ),
      ),
      y.clamp(
        safeInsets.top + 8,
        math.max(
          safeInsets.top + 8,
          size.height - safeInsets.bottom - childSize.height - 8,
        ),
      ),
    );
  }

  @override
  bool shouldRelayout(_VolumeMenuLayout oldDelegate) =>
      anchor != oldDelegate.anchor ||
      safeInsets != oldDelegate.safeInsets ||
      preferLeft != oldDelegate.preferLeft;
}
