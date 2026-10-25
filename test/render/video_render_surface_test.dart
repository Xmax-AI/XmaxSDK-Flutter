import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xmax_sdk/src/foundation/rtc/RemoteStream.dart';
import 'package:xmax_sdk/src/render/video/VideoRenderBinding.dart';
import 'package:xmax_sdk/src/render/video/VideoRenderSurface.dart';
import 'package:xmax_sdk/src/render/video/VideoTextureFrameObserver.dart';
import 'package:xmax_sdk/xmax_sdk.dart';

void main() {
  testWidgets('remote rendering uses channel and assigned local UID', (
    tester,
  ) async {
    await tester.pumpWidget(const SizedBox());
    final context = tester.element(find.byType(SizedBox));
    final engine = _Engine();
    var rendered = 0;
    final observer =
        VideoRenderSurface(
              binding: RemoteVideoRenderBinding(
                RemoteStream(
                  roomID: 'room',
                  userID: 'bot',
                  streamID: 'bot',
                  uid: 7,
                  localUid: 42,
                  engine: engine,
                ),
                onFirstFrameRendered: () => rendered++,
              ),
              track: null,
              contentMode: VideoContentMode.fill,
            ).build(context)
            as VideoTextureFrameObserver;
    final view = observer.child! as AgoraVideoView;
    observer.onFirstFrameRendered!();
    expect(rendered, 1);
    expect(view.controller.rtcEngine, same(engine));
    expect(view.controller.connection?.channelId, 'room');
    expect(view.controller.connection?.localUid, 42);
    expect(view.controller.canvas.uid, 7);
    expect(view.controller.useFlutterTexture, isTrue);
  });

  testWidgets('local preview remains independent from channel identity', (
    tester,
  ) async {
    await tester.pumpWidget(const SizedBox());
    final context = tester.element(find.byType(SizedBox));
    final engine = _Engine();
    final view =
        VideoRenderSurface(
              binding: LocalVideoRenderBinding(engine: engine),
              track: null,
              contentMode: VideoContentMode.fill,
            ).build(context)
            as AgoraVideoView;
    expect(view.controller.rtcEngine, same(engine));
    expect(view.controller.canvas.uid, 0);
    expect(
      view.controller.canvas.sourceType,
      VideoSourceType.videoSourceCamera,
    );
    expect(view.controller.connection?.channelId, isNull);
    expect(view.controller.connection?.localUid, isNull);
  });

  testWidgets(
    'external preview binds the custom video input without mirroring',
    (tester) async {
      await tester.pumpWidget(const SizedBox());
      final context = tester.element(find.byType(SizedBox));
      final view =
          VideoRenderSurface(
                binding: LocalVideoRenderBinding(
                  engine: _Engine(),
                  sourceType: VideoSourceType.videoSourceCustom,
                ),
                track: null,
                contentMode: VideoContentMode.fit,
              ).build(context)
              as AgoraVideoView;
      expect(
        view.controller.canvas.sourceType,
        VideoSourceType.videoSourceCustom,
      );
      expect(
        view.controller.canvas.mirrorMode,
        VideoMirrorModeType.videoMirrorModeDisabled,
      );
      expect(view.controller.canvas.uid, 0);
      expect(view.controller.connection?.channelId, isNull);
    },
  );

  testWidgets(
    'remote rendering does not substitute UID zero for an unknown connection',
    (tester) async {
      await tester.pumpWidget(const SizedBox());
      final context = tester.element(find.byType(SizedBox));
      final view = VideoRenderSurface(
        binding: RemoteVideoRenderBinding(
          RemoteStream(
            roomID: 'room',
            userID: 'bot',
            streamID: 'bot',
            uid: 7,
            engine: _Engine(),
          ),
        ),
        track: null,
        contentMode: VideoContentMode.fill,
      ).build(context);
      expect(view, isA<ColoredBox>());
    },
  );
}

class _Engine implements RtcEngineEx {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
