import 'package:flutter_test/flutter_test.dart';
import 'package:xmax_sdk/src/foundation/errors/XmaxError.dart';
import 'package:xmax_sdk/src/foundation/rtc/RemoteStream.dart';
import 'package:xmax_sdk/src/render/RenderController.dart';
import 'package:xmax_sdk/src/render/video/VideoRenderBinding.dart';
import 'package:xmax_sdk/src/render/video/VideoRenderRegistry.dart';
import 'package:xmax_sdk/src/service/realtime/RealtimeVideoTrack.dart';

void main() {
  const stream = RemoteStream(
    roomID: 'room-id',
    userID: 'bot-id',
    streamID: 'bot-stream',
  );

  test('headless remote cleanup does not require a Flutter frame', () async {
    final controller = RenderController();
    final track = createRealtimeVideoTrack(id: 'remote');
    controller.registerRemoteTrack(track, interactionListener: (_) {});
    controller.setRemoteStream(stream);
    await controller.prepareForRemoteRemoval();
    controller.resetRemoteTrack(track);
  });

  test(
    'decoded readiness does not depend on a mounted or rendered view',
    () async {
      final controller = RenderController();
      final track = createRealtimeVideoTrack(id: 'remote');
      controller.registerRemoteTrack(track, interactionListener: (_) {});
      controller.setRemoteStream(stream);
      var completed = false;
      final wait = controller.waitUntilRemoteFrameReady().then(
        (_) => completed = true,
      );
      controller.markRemoteFrameReady(
        const RemoteStream(
          roomID: 'old',
          userID: 'bot-id',
          streamID: 'bot-stream',
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(completed, isFalse);
      controller.markRemoteFrameReady(stream);
      await wait;
      final binding =
          VideoRenderRegistry.handleFor(track)!.value
              as RemoteVideoRenderBinding;
      expect(binding.firstFrameRendered, isFalse);
      await controller.waitUntilRemoteFrameReady();
      controller.resetRemoteTrack(track);
    },
  );

  test('clearing a stream cancels pending readiness waits', () async {
    final controller = RenderController();
    final track = createRealtimeVideoTrack(id: 'remote');
    controller.registerRemoteTrack(track, interactionListener: (_) {});
    controller.setRemoteStream(stream);
    final cancelled = expectLater(
      controller.waitUntilRemoteFrameReady(),
      throwsA(
        isA<XmaxError>().having((e) => e.code, 'code', XmaxErrorCode.cancelled),
      ),
    );
    controller.setRemoteStream(null);
    await cancelled;
    controller.resetRemoteTrack(track);
  });

  test(
    'missing first frame times out without changing the visual binding',
    () async {
      final controller = RenderController(
        remoteFrameReadyTimeout: Duration.zero,
      );
      final track = createRealtimeVideoTrack(id: 'remote');
      controller.registerRemoteTrack(track, interactionListener: (_) {});
      controller.setRemoteStream(stream);
      await expectLater(
        controller.waitUntilRemoteFrameReady(),
        throwsA(
          isA<XmaxError>().having((e) => e.code, 'code', XmaxErrorCode.timeout),
        ),
      );
      controller.resetRemoteTrack(track);
    },
  );

  test('a selected remote stream is bound immediately', () {
    final controller = RenderController();
    final track = createRealtimeVideoTrack(id: 'remote-track');
    controller.registerRemoteTrack(track, interactionListener: (_) {});
    addTearDown(() => controller.resetRemoteTrack(track));

    controller.setRemoteStream(stream);

    final binding = VideoRenderRegistry.handleFor(track)?.value;
    expect(binding, isA<RemoteVideoRenderBinding>());
    expect((binding as RemoteVideoRenderBinding).stream, stream);
    expect(binding.firstFrameRendered, isFalse);
  });

  test('only the selected remote stream can reveal its first frame', () {
    final controller = RenderController();
    final track = createRealtimeVideoTrack(id: 'remote-track');
    controller.registerRemoteTrack(track, interactionListener: (_) {});
    addTearDown(() => controller.resetRemoteTrack(track));
    controller.setRemoteStream(stream);

    controller.markRemoteFrameRendered(
      const RemoteStream(
        roomID: 'room-id',
        userID: 'bot-id',
        streamID: 'stale-stream',
      ),
    );
    var binding =
        VideoRenderRegistry.handleFor(track)?.value as RemoteVideoRenderBinding;
    expect(binding.firstFrameRendered, isFalse);

    controller.markRemoteFrameRendered(stream);
    binding =
        VideoRenderRegistry.handleFor(track)?.value as RemoteVideoRenderBinding;
    expect(binding.firstFrameRendered, isTrue);

    controller.setRemoteStream(
      const RemoteStream(
        roomID: 'room-id',
        userID: 'bot-id',
        streamID: 'next-stream',
      ),
    );
    binding =
        VideoRenderRegistry.handleFor(track)?.value as RemoteVideoRenderBinding;
    expect(binding.firstFrameRendered, isFalse);
  });

  test('clearing the selected remote stream clears its binding', () {
    final controller = RenderController();
    final track = createRealtimeVideoTrack(id: 'remote-track');
    controller.registerRemoteTrack(track, interactionListener: (_) {});
    addTearDown(() => controller.resetRemoteTrack(track));
    controller.setRemoteStream(stream);

    controller.setRemoteStream(null);

    expect(VideoRenderRegistry.handleFor(track)?.value, isNull);
  });
}
