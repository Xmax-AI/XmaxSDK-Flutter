import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:xmax_sdk/src/service/realtime/RealtimeMediaStream.dart';
import 'package:xmax_sdk/xmax_sdk.dart';
import 'package:xmax_sdk_example/features/realtime/realtime_local_input.dart';
import 'package:xmax_sdk_example/features/realtime/realtime_audio_controls.dart';
import 'package:xmax_sdk_example/features/realtime/realtime_audio_volume_menu.dart';
import 'package:xmax_sdk_example/features/realtime/realtime_page.dart';
import 'package:xmax_sdk_example/localization/xlab_localization.dart';

const _menuKey = ValueKey('realtime-volume-menu');
const _sliderKey = ValueKey('realtime-remote-volume-slider');

void main() {
  setUp(() async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.withData({});
    await XLabLocalization.shared.setLanguage(XLabLanguage.simplifiedChinese);
  });
  tearDown(() => SharedPreferencesAsyncPlatform.instance = null);

  testWidgets(
    'volume popup stays within a narrow viewport and uses English labels',
    (tester) async {
      tester.view.physicalSize = const Size(320, 480);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await XLabLocalization.shared.setLanguage(XLabLanguage.english);
      final controls = RealtimeAudioControls(
        readVolume: () async => 0.4,
        writeVolume: (_) async {},
        onError: (error) => fail('$error'),
      )..reset(0.4);
      addTearDown(controls.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: Scaffold(
            body: Align(
              alignment: Alignment.topRight,
              child: Builder(
                builder: (context) => IconButton(
                  icon: const Icon(Icons.tune_rounded),
                  onPressed: () => showRealtimeAudioVolumeMenu(
                    context: context,
                    sourceContext: context,
                    controls: controls,
                    preferLeft: true,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      final source = tester.getRect(find.byType(IconButton));
      await tester.tap(find.byIcon(Icons.tune_rounded));
      await tester.pumpAndSettle();
      final menu = tester.getRect(find.byKey(_menuKey));
      expect(menu.size, const Size(260, 82));
      expect(menu.left, greaterThanOrEqualTo(12));
      expect(menu.right, lessThanOrEqualTo(308));
      expect(menu.top, greaterThan(source.bottom));
      expect(find.text('Generated audio'), findsOneWidget);
      expect(find.text('40%'), findsOneWidget);
      await tester.tapAt(const Offset(20, 350));
      await tester.pumpAndSettle();
      expect(find.byKey(_menuKey), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'camera volume opens beside the button and writes through the SDK',
    (tester) async {
      final manager = _Manager();
      await tester.pumpWidget(
        MaterialApp(
          home: RealtimePage(apiKey: 'test-key', realtimeManager: manager),
        ),
      );
      await tester.pumpAndSettle();
      expect(manager.useMicrophone, isTrue);
      expect(
        tester
            .widget<XmaxRealtimeDualVideo>(find.byType(XmaxRealtimeDualVideo))
            .videoContentMode,
        VideoContentMode.fill,
      );
      expect(find.text('音量'), findsOneWidget);
      expect(find.byIcon(Icons.aspect_ratio_rounded), findsOneWidget);
      expect(find.byIcon(Icons.bolt), findsNothing);
      final anchor = tester.getRect(find.byIcon(Icons.tune_rounded));
      await tester.tap(find.text('音量'));
      await tester.pumpAndSettle();
      final menu = tester.getRect(find.byKey(_menuKey));
      expect(menu.size, const Size(260, 82));
      expect(menu.right, lessThan(anchor.left));
      expect(find.text('0%'), findsOneWidget);
      expect(find.text('生成声音'), findsOneWidget);
      final slider = tester.widget<CupertinoSlider>(find.byKey(_sliderKey));
      expect(slider.activeColor, const Color(0xFFFF2D55));
      slider.onChanged!(0.63);
      await tester.pumpAndSettle();
      expect(manager.volume, 0.63);
      expect(find.text('63%'), findsOneWidget);
      await tester.tapAt(const Offset(100, 400));
      await tester.pumpAndSettle();
      expect(find.byKey(_menuKey), findsNothing);
      await tester.tap(find.text('音量'));
      await tester.pumpAndSettle();
      expect(find.text('63%'), findsOneWidget);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.idle();
      expect(manager.closes, 1);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.byKey(_menuKey), findsNothing);
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'external video shares the volume menu and preserves the mute volume',
    (tester) async {
      const channel = MethodChannel('ai.xmax.xlab/external_video');
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        (call) async => {
          'width': 640,
          'height': 480,
          'durationUs': 1000000,
          'hasAudio': true,
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );
      final manager = _Manager();
      await tester.pumpWidget(
        MaterialApp(
          home: RealtimePage(
            apiKey: 'test-key',
            realtimeManager: manager,
            localInput: const XLabRealtimeExternalVideoInput(
              path: '/test/video.mp4',
              name: 'video.mp4',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(manager.volume, 1);
      expect(
        tester
            .widget<XmaxRealtimeDualVideo>(find.byType(XmaxRealtimeDualVideo))
            .videoContentMode,
        VideoContentMode.fit,
      );
      expect(find.text('声音'), findsOneWidget);
      expect(find.byIcon(Icons.aspect_ratio_rounded), findsNothing);
      final anchor = tester.getRect(find.byIcon(Icons.tune_rounded));
      await tester.tap(find.text('音量'));
      await tester.pumpAndSettle();
      expect(
        tester.getRect(find.byKey(_menuKey)).top,
        greaterThan(anchor.bottom),
      );
      tester.widget<CupertinoSlider>(find.byKey(_sliderKey)).onChanged!(0.5);
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(100, 400));
      await tester.pumpAndSettle();
      await tester.tap(find.text('声音'));
      await tester.pumpAndSettle();
      expect(manager.volume, 0);
      expect(find.text('静音'), findsOneWidget);
      await tester.tap(find.text('静音'));
      await tester.pumpAndSettle();
      expect(manager.volume, 0.5);
      expect(find.text('声音'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    },
  );
}

class _Manager implements XmaxRealtimeManaging {
  RealtimeStateListener? listener;
  double volume = 0;
  int closes = 0;

  @override
  Future<void> setStateListener(RealtimeStateListener? listener) async =>
      this.listener = listener;

  Future<RealtimeMediaStream> _create() async {
    volume = 0;
    listener?.call(
      const RealtimeState(connectionState: RealtimeConnectionState.ready),
    );
    return createRealtimeMediaStream(id: 'local');
  }

  @override
  Future<RealtimeMediaStream> createLocalCameraStream({
    RealtimeVideoFormat? videoFormat,
    CameraPosition position = CameraPosition.front,
    RealtimeCameraPreset? preset,
    bool useMicrophone = false,
  }) {
    this.useMicrophone = useMicrophone;
    return _create();
  }

  bool? useMicrophone;

  @override
  Future<RealtimeMediaStream> createExternalVideoStream({
    required RealtimeExternalVideoSource source,
  }) => _create();

  @override
  Future<double> get remoteAudioVolume async => volume;

  @override
  Future<void> setRemoteAudioVolume(double value) async => volume = value;

  @override
  Future<RealtimeQualityLevel?> get uplinkQualityLevel async => null;

  @override
  Future<RealtimeQualityLevel?> get downlinkQualityLevel async => null;

  @override
  Future<void> close() async => closes++;

  @override
  dynamic noSuchMethod(Invocation invocation) => Future<void>.value();
}
