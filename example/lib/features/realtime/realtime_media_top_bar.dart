import 'package:flutter/material.dart';
import '../../localization/xlab_localization.dart';
import 'realtime_video_recorder.dart';

class RealtimeMediaTopBar extends StatelessWidget {
  const RealtimeMediaTopBar({
    super.key,
    required this.enabled,
    required this.isMuted,
    required this.statisticsVisible,
    required this.onGallery,
    required this.onMute,
    required this.onVolume,
    required this.onStatistics,
    this.recordingState = RealtimeRecordingState.idle,
    this.onRecording,
  });

  final bool enabled;
  final bool isMuted;
  final bool statisticsVisible;
  final VoidCallback onGallery;
  final VoidCallback onMute;
  final ValueChanged<BuildContext> onVolume;
  final VoidCallback onStatistics;
  final RealtimeRecordingState recordingState;
  final VoidCallback? onRecording;

  @override
  Widget build(BuildContext context) {
    final t = XLabLocalization.shared.text;
    Widget action(
      IconData icon,
      String title,
      VoidCallback? callback, {
      bool selected = false,
      Color? tint,
    }) => SizedBox(
      width: 48,
      height: 50,
      child: Semantics(
        button: true,
        selected: selected,
        enabled: callback != null,
        child: InkResponse(
          onTap: callback,
          child: Opacity(
            opacity: callback == null ? 0.4 : 1,
            child: Column(
              children: [
                const SizedBox(height: 5),
                SizedBox(
                  width: 28,
                  height: 22,
                  child: Icon(
                    icon,
                    size: 17,
                    color:
                        tint ??
                        (selected ? const Color(0xFF007AFF) : Colors.white),
                    shadows: const [
                      Shadow(
                        color: Colors.black54,
                        blurRadius: 2,
                        offset: Offset(0, 1),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    shadows: [
                      Shadow(
                        color: Colors.black54,
                        blurRadius: 2,
                        offset: Offset(0, 1),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        action(
          Icons.bar_chart_rounded,
          t('statistics.title'),
          onStatistics,
          selected: statisticsVisible,
        ),
        if (onRecording != null)
          action(
            recordingState == RealtimeRecordingState.recording
                ? Icons.stop_circle_outlined
                : recordingState == RealtimeRecordingState.saving ||
                      recordingState == RealtimeRecordingState.preparing
                ? Icons.hourglass_top_rounded
                : Icons.radio_button_checked,
            t(
              recordingState == RealtimeRecordingState.recording
                  ? 'record.stop'
                  : recordingState == RealtimeRecordingState.saving
                  ? 'record.saving'
                  : 'record.title',
            ),
            recordingState == RealtimeRecordingState.preparing ||
                    recordingState == RealtimeRecordingState.saving
                ? null
                : onRecording,
            tint: recordingState == RealtimeRecordingState.recording
                ? const Color(0xFFFF3B30)
                : null,
          ),
        Builder(
          builder: (context) => action(
            Icons.tune_rounded,
            t('realtime.volume'),
            () => onVolume(context),
          ),
        ),
        action(
          isMuted ? Icons.volume_off_outlined : Icons.volume_up_outlined,
          t(isMuted ? 'realtime.mute' : 'realtime.audio'),
          onMute,
        ),
        action(
          Icons.photo_library_outlined,
          t('realtime.gallery'),
          enabled ? onGallery : null,
        ),
      ],
    );
  }
}
