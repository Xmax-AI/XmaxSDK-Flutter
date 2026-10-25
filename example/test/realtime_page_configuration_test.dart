import 'package:flutter_test/flutter_test.dart';
import 'package:xmax_sdk_example/features/realtime/realtime_control_panel.dart';
import 'package:xmax_sdk_example/features/realtime/realtime_local_input.dart';
import 'package:xmax_sdk_example/features/realtime/realtime_page.dart';

void main() {
  test('trajectory customization keeps the normal camera workflow', () {
    expect(
      initialRealtimePanelMode(localInput: null),
      XLabRealtimePanelMode.character,
    );
  });

  test('an image input still starts from touch generation', () {
    expect(
      initialRealtimePanelMode(
        localInput: const XLabRealtimeImageInput(
          path: '/tmp/reference.png',
          name: 'reference.png',
        ),
      ),
      XLabRealtimePanelMode.touch,
    );
  });

  test('external video keeps camera-style generation conditions', () {
    expect(
      initialRealtimePanelMode(
        localInput: const XLabRealtimeExternalVideoInput(
          path: '/test/video.mp4',
          name: 'video.mp4',
        ),
      ),
      XLabRealtimePanelMode.character,
    );
  });
}
