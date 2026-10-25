import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xmax_sdk/src/render/video/VideoRenderSurface.dart';
import 'package:xmax_sdk/src/render/RenderController.dart';
import 'package:xmax_sdk/src/render/video/VideoTextureFrameObserver.dart';
import 'package:xmax_sdk/src/foundation/rtc/RemoteStream.dart';
import 'package:xmax_sdk/src/foundation/rtc/LocalStream.dart';
import 'package:xmax_sdk/src/media/interaction/InteractionFrame.dart';
import 'package:xmax_sdk/src/render/trajectory/TrajectoryBinding.dart';
import 'package:xmax_sdk/src/render/trajectory/TrajectoryRegistry.dart';
import 'package:xmax_sdk/src/render/video/VideoRenderBinding.dart';
import 'package:xmax_sdk/src/render/video/VideoRenderRegistry.dart';
import 'package:xmax_sdk/src/render/video/XmaxRealtimeDualVideo.dart';
import 'package:xmax_sdk/src/render/video/XmaxRealtimeVideo.dart';
import 'package:xmax_sdk/src/service/realtime/RealtimeVideoTrack.dart';

void main() {
  testWidgets('an already rendered track also uses the configured fade-in', (
    tester,
  ) async {
    final remote = createRealtimeVideoTrack(id: 'already-rendered');
    VideoRenderRegistry.register(
      remote,
      const RemoteVideoRenderBinding(
        RemoteStream(roomID: 'room', userID: 'bot', streamID: 'stream'),
        firstFrameRendered: true,
      ),
    );
    addTearDown(() => VideoRenderRegistry.unregister(remote));
    await tester.pumpWidget(
      MaterialApp(
        home: XmaxRealtimeDualVideo(
          remoteTrack: remote,
          remoteVideoFadeInDuration: 0.8,
        ),
      ),
    );
    expect(_remoteOpacity(tester), lessThan(0.01));
    await tester.pump(const Duration(milliseconds: 400));
    expect(_remoteOpacity(tester), closeTo(0.5, 0.01));
    await tester.pump(const Duration(milliseconds: 400));
    expect(_remoteOpacity(tester), 1);
  });

  testWidgets(
    'replacing a ready track starts a new fade without remounting local preview',
    (tester) async {
      final local = createRealtimeVideoTrack(id: 'persistent-local');
      final first = createRealtimeVideoTrack(id: 'first-result');
      final second = createRealtimeVideoTrack(id: 'second-result');
      VideoRenderRegistry.register(
        local,
        LocalVideoRenderBinding.fromStream(const LocalStream()),
      );
      for (final track in [first, second]) {
        VideoRenderRegistry.register(
          track,
          RemoteVideoRenderBinding(
            RemoteStream(roomID: 'room', userID: 'bot', streamID: track.id),
            firstFrameRendered: true,
          ),
        );
      }
      addTearDown(() {
        for (final track in [local, first, second]) {
          VideoRenderRegistry.unregister(track);
        }
      });
      Widget view(RealtimeVideoTrack remote) => MaterialApp(
        home: XmaxRealtimeDualVideo(
          localTrack: local,
          remoteTrack: remote,
          remoteVideoFadeInDuration: 0.8,
        ),
      );
      await tester.pumpWidget(view(first));
      await tester.pump(const Duration(milliseconds: 800));
      expect(_remoteOpacity(tester), 1);
      final localElement = tester.element(
        find.byType(XmaxRealtimeVideo).first,
      );
      await tester.pumpWidget(view(second));
      expect(_remoteOpacity(tester), lessThan(0.01));
      expect(
        tester.element(find.byType(XmaxRealtimeVideo).first),
        same(localElement),
      );
      await tester.pump(const Duration(milliseconds: 400));
      expect(_remoteOpacity(tester), closeTo(0.5, 0.01));
      await tester.pump(const Duration(milliseconds: 400));
      expect(_remoteOpacity(tester), 1);
    },
  );

  testWidgets('custom fade-in duration controls the remote transition', (
    tester,
  ) async {
    final remote = createRealtimeVideoTrack(id: 'custom-fade');
    const stream = RemoteStream(
      roomID: 'room',
      userID: 'bot',
      streamID: 'stream',
    );
    VideoRenderRegistry.register(
      remote,
      const RemoteVideoRenderBinding(stream),
    );
    addTearDown(() => VideoRenderRegistry.unregister(remote));
    await tester.pumpWidget(
      MaterialApp(
        home: XmaxRealtimeDualVideo(
          remoteTrack: remote,
          remoteVideoFadeInDuration: 0.8,
        ),
      ),
    );

    VideoRenderRegistry.register(
      remote,
      const RemoteVideoRenderBinding(stream, firstFrameRendered: true),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(_remoteOpacity(tester), closeTo(0.5, 0.01));
    await tester.pump(const Duration(milliseconds: 400));
    expect(_remoteOpacity(tester), 1);
  });

  for (final seconds in [
    0.0,
    -0.3,
    double.nan,
    double.infinity,
    double.negativeInfinity,
  ]) {
    testWidgets('fade-in is disabled for $seconds seconds', (tester) async {
      final remote = createRealtimeVideoTrack(id: 'no-fade');
      const stream = RemoteStream(
        roomID: 'room',
        userID: 'bot',
        streamID: 'stream',
      );
      VideoRenderRegistry.register(
        remote,
        const RemoteVideoRenderBinding(stream),
      );
      addTearDown(() => VideoRenderRegistry.unregister(remote));
      var readyCount = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: XmaxRealtimeDualVideo(
            remoteTrack: remote,
            remoteVideoFadeInDuration: seconds,
            onRemoteVideoReady: () => readyCount += 1,
          ),
        ),
      );
      expect(_remoteOpacity(tester), greaterThan(0));
      expect(_remoteOpacity(tester), lessThan(0.01));
      expect(readyCount, 0);

      VideoRenderRegistry.register(
        remote,
        const RemoteVideoRenderBinding(stream, firstFrameRendered: true),
      );
      await tester.pump();
      expect(_remoteOpacity(tester), 1);
      expect(readyCount, 1);
      VideoRenderRegistry.register(remote, null);
      await tester.pump();
      expect(_remoteOpacity(tester), 0);
    });
  }

  testWidgets(
    'duration changes apply to the next fade without retiming the current fade',
    (tester) async {
      final remote = createRealtimeVideoTrack(id: 'duration-change');
      const stream = RemoteStream(
        roomID: 'room',
        userID: 'bot',
        streamID: 'stream',
      );
      VideoRenderRegistry.register(
        remote,
        const RemoteVideoRenderBinding(stream),
      );
      addTearDown(() => VideoRenderRegistry.unregister(remote));
      Widget view(double seconds) => MaterialApp(
        home: XmaxRealtimeDualVideo(
          remoteTrack: remote,
          remoteVideoFadeInDuration: seconds,
        ),
      );
      void rendered() => VideoRenderRegistry.register(
        remote,
        const RemoteVideoRenderBinding(stream, firstFrameRendered: true),
      );
      await tester.pumpWidget(view(0.3));
      rendered();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      final initialOpacity = _remoteOpacity(tester);
      expect(initialOpacity, inExclusiveRange(0.01, 1));

      await tester.pumpWidget(view(0.8));
      expect(_remoteOpacity(tester), initialOpacity);
      await tester.pump(const Duration(milliseconds: 200));
      expect(_remoteOpacity(tester), 1);

      VideoRenderRegistry.register(
        remote,
        const RemoteVideoRenderBinding(stream),
      );
      await tester.pump();
      expect(_remoteOpacity(tester), lessThan(0.01));
      rendered();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(_remoteOpacity(tester), closeTo(0.5, 0.01));
      await tester.pump(const Duration(milliseconds: 400));
      expect(_remoteOpacity(tester), 1);

      await tester.pumpWidget(view(0));
      VideoRenderRegistry.register(
        remote,
        const RemoteVideoRenderBinding(stream),
      );
      await tester.pump();
      rendered();
      await tester.pump();
      expect(_remoteOpacity(tester), 1);
    },
  );

  testWidgets(
    'submitted texture dismisses loading without a native frame event',
    (tester) async {
      final controller = RenderController();
      final remote = createRealtimeVideoTrack(id: 'texture-result');
      controller.registerRemoteTrack(remote, interactionListener: (_) {});
      controller.setRemoteStream(
        const RemoteStream(roomID: 'room', userID: 'bot', streamID: 'one'),
      );
      addTearDown(() => controller.resetRemoteTrack(remote));
      final binding =
          VideoRenderRegistry.handleFor(remote)!.value
              as RemoteVideoRenderBinding;
      var loading = true;

      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) => Stack(
              fit: StackFit.expand,
              children: [
                XmaxRealtimeDualVideo(
                  remoteTrack: remote,
                  onRemoteVideoReady: () => setState(() => loading = false),
                ),
                // Simulate the RTC renderer inserting its first nonempty texture.
                VideoTextureFrameObserver(
                  binding: binding.stream,
                  onFirstFrameRendered: binding.onFirstFrameRendered,
                  child: const Texture(textureId: 1),
                ),
                if (loading) const Text('Loading'),
              ],
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(find.text('Loading'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(milliseconds: 300));
      expect(_remoteOpacity(tester), 1);
    },
  );

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
        home: XmaxRealtimeDualVideo(
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
                XmaxRealtimeDualVideo(
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
          home: XmaxRealtimeDualVideo(
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
              home: XmaxRealtimeDualVideo(
                onRemoteVideoReady: () => calls += 1,
              ),
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
      MaterialApp(home: XmaxRealtimeDualVideo(remoteTrack: remote)),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: XmaxRealtimeDualVideo(
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
      VideoRenderRegistry.register(
        local,
        LocalVideoRenderBinding.fromStream(const LocalStream()),
      );
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
          home: XmaxRealtimeDualVideo(
            localTrack: local,
            remoteTrack: remote,
          ),
        ),
      );
      final localSurface = tester.element(
        find.byType(VideoRenderSurface).first,
      );
      final remoteSurface = tester.element(
        find.byType(VideoRenderSurface).last,
      );
      await tester.pump(const Duration(milliseconds: 300));
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
      MaterialApp(home: XmaxRealtimeDualVideo(remoteTrack: remote)),
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
      LocalVideoRenderBinding.fromStream(
        const LocalStream(),
        onPreviewAttached: () => attachments += 1,
      ),
    );
    addTearDown(() => VideoRenderRegistry.unregister(localTrack));

    await tester.pumpWidget(
      MaterialApp(home: XmaxRealtimeVideo(track: localTrack)),
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
      MaterialApp(home: XmaxRealtimeDualVideo(remoteTrack: remoteTrack)),
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
    VideoRenderRegistry.register(
      localTrack,
      LocalVideoRenderBinding.fromStream(const LocalStream()),
    );
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
        home: XmaxRealtimeDualVideo(
          localTrack: localTrack,
          remoteTrack: remoteTrack,
        ),
      ),
    );
    final localElement = tester.element(
      find.byType(XmaxRealtimeVideo).first,
    );

    await tester.pumpWidget(
      MaterialApp(home: XmaxRealtimeDualVideo(localTrack: localTrack)),
    );

    expect(
      tester.element(find.byType(XmaxRealtimeVideo)),
      same(localElement),
    );
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
            child: XmaxRealtimeDualVideo(remoteTrack: remoteTrack),
          ),
        ),
      );
      await tester.pump();

      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(XmaxRealtimeDualVideo)),
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
