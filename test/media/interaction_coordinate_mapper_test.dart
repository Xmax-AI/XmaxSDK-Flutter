import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xmax_sdk/src/foundation/media/video/VideoContentMode.dart';
import 'package:xmax_sdk/src/media/interaction/InteractionCoordinateMapper.dart';

void main() {
  test('fit ignores points in letterbox and maps displayed pixels', () {
    const viewport = Size(300, 300);
    const video = Size(300, 150);

    expect(
      InteractionCoordinateMapper.map(
        point: const Offset(150, 20),
        viewportSize: viewport,
        videoSize: video,
        contentMode: VideoContentMode.fit,
      ),
      isNull,
    );
    final center = InteractionCoordinateMapper.map(
      point: const Offset(150, 150),
      viewportSize: viewport,
      videoSize: video,
      contentMode: VideoContentMode.fit,
    );
    expect(center?.x, 0.5);
    expect(center?.y, 0.5);
  });

  test('fill clamps cropped coordinates to the model frame', () {
    final point = InteractionCoordinateMapper.map(
      point: const Offset(0, 150),
      viewportSize: const Size(300, 300),
      videoSize: const Size(300, 150),
      contentMode: VideoContentMode.fill,
    );
    expect(point?.x, 0.25);
    expect(point?.y, 0.5);
  });
}
