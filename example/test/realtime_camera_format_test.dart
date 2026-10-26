import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:xmax_sdk/src/service/realtime/RealtimeMediaStream.dart';
import 'package:xmax_sdk/src/service/realtime/RealtimeVideoTrack.dart';
import 'package:xmax_sdk/xmax_sdk.dart';
import 'package:xmax_sdk_example/features/realtime/realtime_camera_format_menu.dart';
import 'package:xmax_sdk_example/features/realtime/realtime_control_panel.dart';
import 'package:xmax_sdk_example/features/realtime/realtime_page.dart';
import 'package:xmax_sdk_example/localization/xlab_localization.dart';

const _menuKey = ValueKey('realtime-camera-format-menu');
const _landscape = RealtimeVideoFormat(width: 1920, height: 1080, fps: 30);
const _portrait = RealtimeVideoFormat(width: 1080, height: 1920, fps: 30);

Finder _option(RealtimeVideoFormat format) => find.byKey(
  ValueKey('realtime-camera-format-${format.width}x${format.height}'),
);

InkResponse _formatButton(WidgetTester tester) => tester.widget<InkResponse>(
  find
      .ancestor(
        of: find.byIcon(Icons.aspect_ratio_rounded),
        matching: find.byType(InkResponse),
      )
      .first,
);

XmaxRealtimeDualVideo _video(WidgetTester tester) =>
    tester.widget<XmaxRealtimeDualVideo>(find.byType(XmaxRealtimeDualVideo));

Future<void> _mount(WidgetTester tester, _Manager manager) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData.dark(),
      home: RealtimePage(apiKey: 'test-key', realtimeManager: manager),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _select(WidgetTester tester, RealtimeVideoFormat format) async {
  await tester.tap(find.byIcon(Icons.aspect_ratio_rounded));
  await tester.pumpAndSettle();
  await tester.tap(_option(format));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.withData({});
    await XLabLocalization.shared.setLanguage(XLabLanguage.simplifiedChinese);
  });
  tearDown(() => SharedPreferencesAsyncPlatform.instance = null);

  test('camera ratios use fill only for portrait 9:16', () {
    expect(
      RealtimeModel.x2_1.supportedVideoFormats.map(realtimeCameraAspectRatio),
      ['16:9', '9:16', '1:1', '3:4', '4:3'],
    );
    expect(
      RealtimeModel.x2_1.supportedVideoFormats.map(realtimeCameraContentMode),
      [
        VideoContentMode.fit,
        VideoContentMode.fill,
        VideoContentMode.fit,
        VideoContentMode.fit,
        VideoContentMode.fit,
      ],
    );
  });

  testWidgets(
    'ratio switching updates SDK capture and preserves video identity',
    (tester) async {
      final manager = _Manager();
      await _mount(tester, manager);
      final originalTrack = _video(tester).localTrack;
      final originalView = tester.state(find.byType(XmaxRealtimeDualVideo));

      await tester.tap(find.byIcon(Icons.aspect_ratio_rounded));
      await tester.pumpAndSettle();
      expect(find.text('比例'), findsNWidgets(2));
      for (final ratio in ['16:9', '9:16', '1:1', '3:4', '4:3']) {
        expect(find.text(ratio), findsOneWidget);
      }
      expect(
        tester
            .widget<CupertinoActionSheetAction>(_option(_portrait))
            .isDefaultAction,
        isTrue,
      );
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(manager.updates, isEmpty);

      for (final format in RealtimeModel.x2_1.supportedVideoFormats) {
        await _select(tester, format);
        expect(manager.updates.last, format);
        expect(manager.local.videoTrack!.videoFormat, format);
        expect(
          _video(tester).videoContentMode,
          realtimeCameraContentMode(format),
        );
        expect(_video(tester).localTrack, same(originalTrack));
        expect(
          tester.state(find.byType(XmaxRealtimeDualVideo)),
          same(originalView),
        );
        expect(manager.creations, 1);
        expect(manager.closes, 0);
      }
      expect(manager.updates, hasLength(5));
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('selecting the current ratio leaves capture unchanged', (
    tester,
  ) async {
    final manager = _Manager();
    await _mount(tester, manager);
    await _select(tester, _portrait);
    expect(manager.updates, isEmpty);
    expect(_video(tester).videoContentMode, VideoContentMode.fill);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('only ready disconnected preview allows ratio changes', (
    tester,
  ) async {
    final manager = _Manager();
    await _mount(tester, manager);
    for (final state in RealtimeConnectionState.values) {
      manager.emit(state);
      await tester.pump();
      expect(
        _formatButton(tester).onTap != null,
        state == RealtimeConnectionState.ready,
        reason: state.value,
      );
    }
    expect(manager.updates, isEmpty);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a pending format update blocks controls until SDK completion', (
    tester,
  ) async {
    final manager = _Manager()..updateGate = Completer<void>();
    await _mount(tester, manager);
    await _select(tester, _landscape);
    expect(manager.updates, [_landscape]);
    expect(_formatButton(tester).onTap, isNull);
    expect(
      tester
          .widget<XLabRealtimeControlPanel>(
            find.byType(XLabRealtimeControlPanel),
          )
          .enabled,
      isFalse,
    );
    expect(_video(tester).videoContentMode, VideoContentMode.fill);

    manager.updateGate!.complete();
    await tester.pumpAndSettle();
    expect(_formatButton(tester).onTap, isNotNull);
    expect(_video(tester).videoContentMode, VideoContentMode.fit);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('capture failure preserves the previous ratio and allows retry', (
    tester,
  ) async {
    final manager = _Manager()
      ..updateError = StateError('Capture format rejected');
    await _mount(tester, manager);
    await _select(tester, _landscape);
    expect(manager.local.videoTrack!.videoFormat, _portrait);
    expect(_video(tester).videoContentMode, VideoContentMode.fill);
    expect(_formatButton(tester).onTap, isNotNull);
    manager.updateError = null;
    await _select(tester, _landscape);
    expect(_video(tester).videoContentMode, VideoContentMode.fit);
    expect(find.textContaining('Capture format rejected'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });

  testWidgets('generation waits for an already admitted format update', (
    tester,
  ) async {
    final manager = _Manager()..updateGate = Completer<void>();
    await _mount(tester, manager);
    await _select(tester, _landscape);
    final panel = tester.widget<XLabRealtimeControlPanel>(
      find.byType(XLabRealtimeControlPanel),
    );
    panel.onTouchStart();
    await tester.pump();
    expect(manager.starts, 0);
    manager.updateGate!.complete();
    await tester.pump();
    await tester.pump();
    expect(manager.starts, 1);
    expect(manager.formatAtGeneration, _landscape);
    expect(_formatButton(tester).onTap, isNull);
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'backgrounding dismisses the menu and restores the chosen ratio',
    (tester) async {
      final manager = _Manager();
      await _mount(tester, manager);
      await _select(tester, _landscape);
      await tester.tap(find.byIcon(Icons.aspect_ratio_rounded));
      await tester.pumpAndSettle();
      expect(find.byKey(_menuKey), findsOneWidget);
      final menuRoute = ModalRoute.of(tester.element(find.byKey(_menuKey)))!;

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pumpAndSettle();
      expect(menuRoute.isActive, isFalse);
      expect(manager.closes, 1);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.byKey(_menuKey), findsNothing);
      expect(manager.creations, 2);
      expect(manager.requestedFormats.last, _landscape);
      expect(_video(tester).videoContentMode, VideoContentMode.fit);
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('ratio menu supports English labels', (tester) async {
    await XLabLocalization.shared.setLanguage(XLabLanguage.english);
    await _mount(tester, _Manager());
    await tester.tap(find.byIcon(Icons.aspect_ratio_rounded));
    await tester.pumpAndSettle();
    expect(find.text('Ratio'), findsNWidgets(2));
    expect(find.text('Cancel'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('connecting closes an open ratio menu without changing capture', (
    tester,
  ) async {
    final manager = _Manager();
    await _mount(tester, manager);
    await tester.tap(find.byIcon(Icons.aspect_ratio_rounded));
    await tester.pumpAndSettle();
    manager.emit(RealtimeConnectionState.connecting);
    await tester.pumpAndSettle();
    expect(find.byKey(_menuKey), findsNothing);
    expect(_formatButton(tester).onTap, isNull);
    expect(manager.updates, isEmpty);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'background cleanup invalidates a pending format and generation',
    (tester) async {
      final manager = _Manager()..updateGate = Completer<void>();
      await _mount(tester, manager);
      await _select(tester, _landscape);
      tester
          .widget<XLabRealtimeControlPanel>(
            find.byType(XLabRealtimeControlPanel),
          )
          .onTouchStart();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(manager.creations, 1);
      manager.updateGate!.complete();
      await tester.pumpAndSettle();
      expect(manager.creations, 2);
      expect(manager.starts, 0);
      expect(manager.local.videoTrack!.videoFormat, _portrait);
      expect(_video(tester).videoContentMode, VideoContentMode.fill);
      expect(_formatButton(tester).onTap, isNotNull);
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('disposing the page with an open ratio menu is safe', (
    tester,
  ) async {
    final manager = _Manager();
    await _mount(tester, manager);
    await tester.tap(find.byIcon(Icons.aspect_ratio_rounded));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(manager.updates, isEmpty);
    expect(tester.takeException(), isNull);
  });
}

class _Manager implements XmaxRealtimeManaging {
  @override
  final options = const RealtimeConfiguration(model: RealtimeModel.x2_1);

  RealtimeStateListener? listener;
  late RealtimeMediaStream local;
  final requestedFormats = <RealtimeVideoFormat?>[];
  final updates = <RealtimeVideoFormat>[];
  Completer<void>? updateGate;
  Object? updateError;
  int creations = 0;
  int closes = 0;
  int starts = 0;
  RealtimeVideoFormat? formatAtGeneration;

  void emit(RealtimeConnectionState state) =>
      listener?.call(RealtimeState(connectionState: state));

  @override
  Future<void> setStateListener(RealtimeStateListener? listener) async {
    this.listener = listener;
  }

  @override
  Future<RealtimeMediaStream> createLocalCameraStream({
    RealtimeVideoFormat? videoFormat,
    CameraPosition position = CameraPosition.front,
    RealtimeCameraPreset? preset,
    bool useMicrophone = false,
  }) async {
    creations++;
    requestedFormats.add(videoFormat);
    local = createRealtimeMediaStream(
      id: 'local-$creations',
      videoTrack: createRealtimeVideoTrack(
        id: 'camera-$creations',
        videoFormat: videoFormat ?? options.model.defaultCameraVideoFormat,
        position: position,
      ),
    );
    emit(RealtimeConnectionState.ready);
    return local;
  }

  @override
  Future<void> updateCameraFormat({
    RealtimeVideoFormat? videoFormat,
    RealtimeCameraPreset? preset,
  }) async {
    final track = local.videoTrack!;
    updates.add(videoFormat!);
    await updateGate?.future;
    if (updateError case final error?) throw error;
    updateRealtimeVideoTrack(track: track, videoFormat: videoFormat);
  }

  @override
  Future<RealtimeMediaStream?> startGeneration({
    RealtimeMediaStream? localStream,
    RealtimeContext? context,
    bool faceRestoration = false,
  }) async {
    starts++;
    formatAtGeneration = local.videoTrack!.videoFormat;
    emit(RealtimeConnectionState.generating);
    return null;
  }

  @override
  Future<double> get remoteAudioVolume async => 0;

  @override
  Future<RealtimeQualityLevel?> get uplinkQualityLevel async => null;

  @override
  Future<RealtimeQualityLevel?> get downlinkQualityLevel async => null;

  @override
  Future<void> close() async {
    closes++;
    await updateGate?.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => Future<void>.value();
}
