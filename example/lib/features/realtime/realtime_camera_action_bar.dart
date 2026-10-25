import 'package:flutter/material.dart';

import '../../localization/xlab_localization.dart';

class RealtimeCameraActionBar extends StatelessWidget {
  const RealtimeCameraActionBar({
    required this.cameraEnabled,
    required this.statisticsVisible,
    required this.onSwitchCamera,
    required this.onToggleStatistics,
    required this.onOpenAudioVolume,
    super.key,
  });

  final bool cameraEnabled;
  final bool statisticsVisible;
  final VoidCallback onSwitchCamera;
  final VoidCallback onToggleStatistics;
  final ValueChanged<BuildContext> onOpenAudioVolume;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: <Widget>[
      _CameraActionButton(
        icon: Icons.sync_rounded,
        label: XLabLocalization.shared.text('realtime.flip'),
        tooltip: XLabLocalization.shared.text('realtime.flipCamera'),
        onPressed: cameraEnabled ? onSwitchCamera : null,
      ),
      _CameraActionButton(
        icon: Icons.tune_rounded,
        label: XLabLocalization.shared.text('realtime.volume'),
        tooltip: XLabLocalization.shared.text('realtime.volume.remote.adjust'),
        onPressedWithContext: onOpenAudioVolume,
      ),
      _CameraActionButton(
        icon: Icons.bar_chart_rounded,
        label: XLabLocalization.shared.text('statistics.title'),
        tooltip: XLabLocalization.shared.text('statistics.title'),
        selected: statisticsVisible,
        onPressed: onToggleStatistics,
      ),
    ],
  );
}

class _CameraActionButton extends StatelessWidget {
  const _CameraActionButton({
    required this.icon,
    required this.label,
    required this.tooltip,
    this.onPressed,
    this.onPressedWithContext,
    this.selected = false,
  });

  final IconData icon;
  final String label;
  final String tooltip;
  final VoidCallback? onPressed;
  final ValueChanged<BuildContext>? onPressedWithContext;
  final bool selected;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 58,
    height: 62,
    child: Semantics(
      button: true,
      enabled: onPressed != null || onPressedWithContext != null,
      selected: selected,
      child: Tooltip(
        message: tooltip,
        child: InkResponse(
          onTap: onPressedWithContext != null
              ? () => onPressedWithContext!(context)
              : onPressed,
          radius: 29,
          child: Opacity(
            opacity: onPressed != null || onPressedWithContext != null
                ? 1
                : 0.45,
            child: Column(
              children: <Widget>[
                const SizedBox(height: 9),
                Icon(
                  icon,
                  color: selected ? const Color(0xFF007AFF) : Colors.white,
                  size: 22,
                  shadows: const <Shadow>[
                    Shadow(
                      color: Colors.black54,
                      blurRadius: 2,
                      offset: Offset(0, 1),
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      label,
                      maxLines: 1,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        shadows: <Shadow>[
                          Shadow(
                            color: Colors.black54,
                            blurRadius: 2,
                            offset: Offset(0, 1),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
