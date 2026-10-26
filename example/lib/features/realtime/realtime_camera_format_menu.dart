import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:xmax_sdk/xmax_sdk.dart';

import '../../localization/xlab_localization.dart';

String realtimeCameraAspectRatio(RealtimeVideoFormat format) {
  final divisor = format.width.gcd(format.height);
  return '${format.width ~/ divisor}:${format.height ~/ divisor}';
}

VideoContentMode realtimeCameraContentMode(RealtimeVideoFormat format) =>
    format.width * 16 == format.height * 9
    ? VideoContentMode.fill
    : VideoContentMode.fit;

Future<RealtimeVideoFormat?> showRealtimeCameraFormatMenu({
  required BuildContext context,
  required List<RealtimeVideoFormat> formats,
  required RealtimeVideoFormat currentFormat,
  required ValueChanged<Route<RealtimeVideoFormat>> onPresented,
}) {
  final route = CupertinoModalPopupRoute<RealtimeVideoFormat>(
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    builder: (context) => CupertinoActionSheet(
      key: const ValueKey('realtime-camera-format-menu'),
      title: Text(XLabLocalization.shared.text('realtime.camera.format')),
      actions: [
        for (final format in formats)
          CupertinoActionSheetAction(
            key: ValueKey(
              'realtime-camera-format-${format.width}x${format.height}',
            ),
            isDefaultAction:
                format.width == currentFormat.width &&
                format.height == currentFormat.height,
            onPressed: () => Navigator.of(context).pop(format),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(realtimeCameraAspectRatio(format)),
                if (format.width == currentFormat.width &&
                    format.height == currentFormat.height) ...[
                  const SizedBox(width: 8),
                  const Icon(Icons.check_rounded, size: 18),
                ],
              ],
            ),
          ),
      ],
      cancelButton: CupertinoActionSheetAction(
        onPressed: () => Navigator.of(context).pop(),
        child: Text(XLabLocalization.shared.text('common.cancel')),
      ),
    ),
  );
  onPresented(route);
  return Navigator.of(context, rootNavigator: true).push(route);
}
