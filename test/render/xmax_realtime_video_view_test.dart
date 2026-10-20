import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xmax_sdk/src/render/video/VideoRenderSurface.dart';
import 'package:xmax_sdk/src/foundation/rtc/RtcModels.dart';
import 'package:xmax_sdk/src/media/interaction/InteractionFrame.dart';
import 'package:xmax_sdk/src/render/trajectory/TrajectoryBinding.dart';
import 'package:xmax_sdk/src/render/trajectory/TrajectoryRegistry.dart';
import 'package:xmax_sdk/src/render/video/VideoRenderBinding.dart';
import 'package:xmax_sdk/src/render/video/VideoRenderRegistry.dart';
import 'package:xmax_sdk/src/render/video/XmaxRealtimeVideoView.dart';
import 'package:xmax_sdk/src/render/video/XmaxVideoView.dart';
import 'package:xmax_sdk/src/service/realtime/RealtimeVideoTrack.dart';

void main() {
  testWidgets(
    'ready callback waits for rendering and repeats only on rebinding',
    (tester) async {
      final remote = createRealtimeVideoTrack(id: 'remote');
      const stream = RemoteStream(
        roomID: 'room',
        userID: 'bot',
        streamID: 'one',
      );
      VideoRenderRegistry.register(
        remote,
        const RemoteVideoRenderBinding(stream),
      );
      addTearDown(() => VideoRenderRegistry.unregister(remote));
      var calls = 0;
      Widget view() => MaterialApp(
        home: XmaxRealtimeVideoView(
          remoteTrack: remote,
          onRemoteVideoReady: () => calls += 1,
        ),
      );
      await tester.pumpWidget(view());
      await tester.pump(const Duration(seconds: 1));
      expect(calls, 0);

      void rendered() => VideoRenderRegistry.register(
        remote,
        const RemoteVideoRenderBinding(stream, firstFrameRendered: true),
      );
      rendered();
      expect(calls, 0);
      await tester.pump();
      expect(calls, 1);
      // Notification starts the transition; it does not wait for the fade.
      expect(_remoteOpacity(tester), lessThan(1));
      await tester.pumpWidget(view());
      rendered();
      await tester.pump();
      expect(calls, 1);

      VideoRenderRegistry.register(remote, null);
      rendered();
      await tester.pump();
      expect(calls, 2);
      VideoRenderRegistry.register(
        remote,
        const RemoteVideoRenderBinding(
          RemoteStream(roomID: 'room', userID: 'bot', streamID: 'two'),
          firstFrameRendered: true,
        ),
      );
      await tester.pump();
      expect(calls, 3);
    },
  );

  testWidgets(
    'already ready track can safely dismiss a parent loading overlay',
    (tester) async {
      final remote = createRealtimeVideoTrack(id: 'remote');
      VideoRenderRegistry.register(
        remote,
        const RemoteVideoRenderBinding(
          RemoteStream(roomID: 'room', userID: 'bot', streamID: 'stream'),
          firstFrameRendered: true,
        ),
      );
      addTearDown(() => VideoRenderRegistry.unregister(remote));
      var loading = true;
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) => Stack(
              children: [
                XmaxRealtimeVideoView(
                  remoteTrack: remote,
                  onRemoteVideoReady: () => setState(() => loading = false),
                ),
                if (loading) const Text('Loading'),
              ],
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('Loading'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  for (final cancellation in ['unbind', 'replace', 'dispose', 'conceal']) {
    testWidgets('queued ready callback is discarded on $cancellation', (
      tester,
    ) async {
      final remote = createRealtimeVideoTrack(id: 'remote');
      VideoRenderRegistry.register(remote, null);
      addTearDown(() => VideoRenderRegistry.unregister(remote));
      var calls = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: XmaxRealtimeVideoView(
            remoteTrack: remote,
            onRemoteVideoReady: () => calls += 1,
          ),
        ),
      );
      VideoRenderRegistry.register(
        remote,
        const RemoteVideoRenderBinding(
          RemoteStream(roomID: 'room', userID: 'bot', streamID: 'stream'),
          firstFrameRendered: true,
        ),
      );

      switch (cancellation) {
        case 'unbind':
          VideoRenderRegistry.register(remote, null);
          await tester.pump();
        case 'replace':
          await tester.pumpWidget(
            MaterialApp(
              home: XmaxRealtimeVideoView(onRemoteVideoReady: () => calls += 1),
            ),
          );
        case 'dispose':
          await tester.pumpWidget(const SizedBox());
        case 'conceal':
          final concealed = VideoRenderRegistry.handleFor(
            remote,
          )!.prepareForRemoval();
          await tester.pump();
          await concealed;
      }
      expect(calls, 0);
    });
  }

  testWidgets('callback added after readiness is delivered once', (
    tester,
  ) async {
    final remote = createRealtimeVideoTrack(id: 'remote');
    VideoRenderRegistry.register(
      remote,
      const RemoteVideoRenderBinding(
        RemoteStream(roomID: 'room', userID: 'bot', streamID: 'stream'),
        firstFrameRendered: true,
      ),
    );
    addTearDown(() => VideoRenderRegistry.unregister(remote));
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(home: XmaxRealtimeVideoView(remoteTrack: remote)),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: XmaxRealtimeVideoView(
          remoteTrack: remote,
          onRemoteVideoReady: () => calls += 1,
        ),
      ),
    );
    await tester.pump();
    expect(calls, 1);
  });

  testWidgets(
    'remote surface is concealed before unbinding without replacing preview',
    (tester) async {
      final local = createRealtimeVideoTrack(id: 'local');
      final remote = createRealtimeVideoTrack(id: 'remote');
      VideoRenderRegistry.register(local, const LocalVideoRenderBinding());
      VideoRenderRegistry.register(
        remote,
        const RemoteVideoRenderBinding(
          RemoteStream(roomID: 'room', userID: 'bot', streamID: 'stream'),
          firstFrameRendered: true,
        ),
      );
      addTearDown(() {
        VideoRenderRegistry.unregister(local);
        VideoRenderRegistry.unregister(remote);
      });
      await tester.pumpWidget(
        MaterialApp(
          home: XmaxRealtimeVideoView(localTrack: local, remoteTrack: remote),
        ),
      );
      final localSurface = tester.element(
        find.byType(VideoRenderSurface).first,
      );
      final remoteSurface = tester.element(
        find.byType(VideoRenderSurface).last,
      );
      expect(_remoteOpacity(tester), 1);

      var concealed = false;
      final hide = VideoRenderRegistry.handleFor(
        remote,
      )!.prepareForRemoval().then((_) => concealed = true);
      expect(concealed, isFalse);
      expect(VideoRenderRegistry.handleFor(remote)!.value, isNotNull);
      await tester.pump();
      await hide;
      expect(_remoteOpacity(tester), 0);
      expect(
        tester.element(find.byType(VideoRenderSurface).last),
        same(remoteSurface),
      );
      expect(
        tester.element(find.byType(VideoRenderSurface).first),
        same(localSurface),
      );

      VideoRenderRegistry.register(remote, null);
      await tester.pump();
      expect(_remoteOpacity(tester), 0);
      expect(
        tester.element(find.byType(VideoRenderSurface)),
        same(localSurface),
      );

      VideoRenderRegistry.register(
        remote,
        const RemoteVideoRenderBinding(
          RemoteStream(
            roomID: 'new-room',
            userID: 'bot',
            streamID: 'new-stream',
          ),
        ),
      );
      await tester.pump();
      expect(_remoteOpacity(tester), greaterThan(0));
      expect(_remoteOpacity(tester), lessThan(0.01));
    },
  );

  testWidgets('background teardown never waits for a paused frame', (
    tester,
  ) async {
    final remote = createRealtimeVideoTrack(id: 'remote');
    VideoRenderRegistry.register(
      remote,
      const RemoteVideoRenderBinding(
        RemoteStream(roomID: 'room', userID: 'bot', streamID: 'stream'),
        firstFrameRendered: true,
      ),
    );
    addTearDown(() => VideoRenderRegistry.unregister(remote));
    await tester.pumpWidget(
      MaterialApp(home: XmaxRealtimeVideoView(remoteTrack: remote)),
    );
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await VideoRenderRegistry.handleFor(remote)!.prepareForRemoval();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(_remoteOpacity(tester), 0);
  });

  testWidgets('local preview waits for a native surface attachment', (
    tester,
  ) async {
    final localTrack = createRealtimeVideoTrack(id: 'local');
    var attachments = 0;
    VideoRenderRegistry.register(
      localTrack,
      LocalVideoRenderBinding(onPreviewAttached: () => attachments += 1),
    );
    addTearDown(() => VideoRenderRegistry.unregister(localTrack));

    await tester.pumpWidget(
      MaterialApp(home: XmaxVideoView(track: localTrack)),
    );
    expect(attachments, 0);

    await tester.pump();
    expect(attachments, 0);
  });

  testWidgets('remote fades in only after its first rendered frame', (
    tester,
  ) async {
    final remoteTrack = createRealtimeVideoTrack(id: 'remote');
    VideoRenderRegistry.register(remoteTrack, null);
    addTearDown(() => VideoRenderRegistry.unregister(remoteTrack));

    await tester.pumpWidget(
      MaterialApp(home: XmaxRealtimeVideoView(remoteTrack: remoteTrack)),
    );

    expect(_remoteOpacity(tester), lessThan(0.01));

    VideoRenderRegistry.register(
      remoteTrack,
      const RemoteVideoRenderBinding(
        RemoteStream(roomID: 'room', userID: 'bot', streamID: 'stream'),
      ),
    );
    await tester.pump();
    expect(_remoteOpacity(tester), lessThan(0.01));
    final opacity = tester.renderObject<RenderOpacity>(find.byType(Opacity));
    // A nonzero double can still round to alpha=0 and suppress platform-view
    // painting. Verify the render object's behavior, not only the widget value.
    expect(opacity.paintsChild(opacity.child!), isTrue);

    VideoRenderRegistry.register(
      remoteTrack,
      const RemoteVideoRenderBinding(
        RemoteStream(roomID: 'room', userID: 'bot', streamID: 'stream'),
        firstFrameRendered: true,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    expect(_remoteOpacity(tester), greaterThan(0.01));
    expect(_remoteOpacity(tester), lessThan(1));
    await tester.pump(const Duration(milliseconds: 150));
    expect(_remoteOpacity(tester), 1);

    VideoRenderRegistry.register(remoteTrack, null);
    await tester.pump();

    expect(_remoteOpacity(tester), lessThan(0.01));
  });

  testWidgets('removing remote track keeps the local preview mounted', (
    tester,
  ) async {
    final localTrack = createRealtimeVideoTrack(id: 'local-preview');
    final remoteTrack = createRealtimeVideoTrack(id: 'remote-result');
    VideoRenderRegistry.register(localTrack, const LocalVideoRenderBinding());
    VideoRenderRegistry.register(
      remoteTrack,
      const RemoteVideoRenderBinding(
        RemoteStream(roomID: 'room', userID: 'bot', streamID: 'stream'),
        firstFrameRendered: true,
      ),
    );
    addTearDown(() {
      VideoRenderRegistry.unregister(localTrack);
      VideoRenderRegistry.unregister(remoteTrack);
    });

    await tester.pumpWidget(
      MaterialApp(
        home: XmaxRealtimeVideoView(
          localTrack: localTrack,
          remoteTrack: remoteTrack,
        ),
      ),
    );
    final localElement = tester.element(find.byType(XmaxVideoView).first);

    await tester.pumpWidget(
      MaterialApp(home: XmaxRealtimeVideoView(localTrack: localTrack)),
    );

    expect(tester.element(find.byType(XmaxVideoView)), same(localElement));
  });

  testWidgets(
    'remote interaction continuously samples active touches at 30Hz',
    (tester) async {
      final remoteTrack = createRealtimeVideoTrack(id: 'interactive-remote');
      final frames = <InteractionFrame>[];

      VideoRenderRegistry.register(
        remoteTrack,
        const RemoteVideoRenderBinding(
          RemoteStream(roomID: 'room', userID: 'bot', streamID: 'stream'),
          firstFrameRendered: true,
        ),
      );
      TrajectoryRegistry.register(
        remoteTrack,
        TrajectoryBinding(interactionListener: frames.add),
      );
      addTearDown(() {
        VideoRenderRegistry.unregister(remoteTrack);
        TrajectoryRegistry.unregister(remoteTrack);
      });

      await tester.pumpWidget(
        MaterialApp(
          home: SizedBox.expand(
            child: XmaxRealtimeVideoView(remoteTrack: remoteTrack),
          ),
        ),
      );
      await tester.pump();

      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(XmaxRealtimeVideoView)),
      );

      // Touch-down is sent immediately, even before the first sampling tick.
      expect(frames, hasLength(1));
      expect(frames.single.points, hasLength(1));

      // The ticker follows screen refreshes but throttles outbound tracks to
      // 30 Hz, including while the finger remains stationary.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      expect(frames, hasLength(1));
      await tester.pump(const Duration(milliseconds: 18));
      expect(frames, hasLength(2));

      await gesture.up();
      final countAfterUp = frames.length;
      await tester.pump(const Duration(milliseconds: 100));
      expect(frames, hasLength(countAfterUp));
    },
  );
}

double _remoteOpacity(WidgetTester tester) =>
    tester.widget<Opacity>(find.byType(Opacity)).opacity;
