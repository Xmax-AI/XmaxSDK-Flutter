<p align="center">
  <img src="./materials/images/brand/xmax-sdk.png" alt="XmaxSDK — Realtime Interactive Video Generation" width="880">
</p>

<p align="center">
  <a href="https://flutter.dev/"><img src="https://img.shields.io/badge/Flutter-3.35%2B-02569B" alt="Flutter 3.35+"></a>
  <a href="https://dart.dev/"><img src="https://img.shields.io/badge/Dart-3.9%2B-0175C2" alt="Dart 3.9+"></a>
  <a href="https://developer.apple.com/ios/"><img src="https://img.shields.io/badge/iOS-15.0%2B-007AFF" alt="iOS 15.0+"></a>
  <a href="https://developer.android.com/"><img src="https://img.shields.io/badge/Android-API%2026%2B-3DDC84" alt="Android API 26+"></a>
  <a href="https://platform.xmaxai.com/"><img src="https://img.shields.io/badge/Realtime-AI-FF9500" alt="Realtime AI"></a>
  <a href="./LICENSE"><img src="https://img.shields.io/badge/License-MIT-4C9A2A" alt="MIT License"></a>
</p>

We introduce XmaxSDK, a Flutter SDK designed for real-time interactive video generation via Xmax models. XmaxSDK implements an end-to-end pipeline covering media acquisition, video streaming, frame-by-frame generation, and on-device rendering, enabling developers to seamlessly integrate low-latency, high-fidelity video transformations into creative applications at a much lower cost than alternative solutions.

<p align="center"><img src="./materials/images/xlab/generation-demo.gif" alt="X-Lab realtime generation demo" width="33%" /><img src="./materials/images/xlab/index-demo.gif" alt="X-Lab index demo" width="33%" /><img src="./materials/images/xlab/storage-demo.gif" alt="X-Lab storage demo" width="33%" /></p>

<br>

## What you can build with XmaxSDK

<table>
  <tr>
    <th width="24%" align="left">Realtime Use Case</th>
    <th width="60%" align="left">Description</th>
    <th width="16%" align="center">Demo</th>
  </tr>
  <tr>
    <td rowspan="2" width="24%" valign="middle">
      <strong>Character Swapping</strong>
    </td>
    <td width="60%" valign="middle">
      Replace anyone in your live feed with a designated avatar in real time.
    </td>
    <td rowspan="2" width="16%" align="center" valign="middle">
      <a href="https://cdn.jsdelivr.net/gh/Xmax-AI/XmaxSDK-Flutter@main/materials/videos/use-cases/character-swapping.mp4">
        <img src="./materials/images/use-cases/character-swapping-poster.png" alt="Play the Character Swapping demo" width="120">
        <br>
        <sub>▶ Play demo</sub>
      </a>
    </td>
  </tr>
  <tr>
    <td width="60%" valign="middle">
      <strong>Prompt:</strong> <code>视频中角色替换成参考图中角色</code>
      <br><br>
      <strong>Reference image:</strong> Select a clear image of the desired character with a clean background.
    </td>
  </tr>
  <tr>
    <td rowspan="2" width="24%" valign="middle">
      <strong>Virtual Try-On</strong>
    </td>
    <td width="60%" valign="middle">
      Seamlessly change outfits, preserving exact body shape, natural motion, and
      an authentic fit.
    </td>
    <td rowspan="2" width="16%" align="center" valign="middle">
      <a href="https://cdn.jsdelivr.net/gh/Xmax-AI/XmaxSDK-Flutter@main/materials/videos/use-cases/virtual-try-on.mp4">
        <img src="./materials/images/use-cases/virtual-try-on-poster.png" alt="Play the Virtual Try-On demo" width="120">
        <br>
        <sub>▶ Play demo</sub>
      </a>
    </td>
  </tr>
  <tr>
    <td width="60%" valign="middle">
      <strong>Prompt:</strong> <code>视频中人物衣服替换成参考图中衣服</code>
      <br><br>
      <strong>Reference image:</strong> Select a clear image of the target outfit with a clean background.
    </td>
  </tr>
  <tr>
    <td rowspan="2" width="24%" valign="middle">
      <strong>Video Restyling</strong>
    </td>
    <td width="60%" valign="middle">
      Reimagine your world in any style with an immersive visual experience.
    </td>
    <td rowspan="2" width="16%" align="center" valign="middle">
      <a href="https://cdn.jsdelivr.net/gh/Xmax-AI/XmaxSDK-Flutter@main/materials/videos/use-cases/video-restyling.mp4">
        <img src="./materials/images/use-cases/video-restyling-poster.png" alt="Play the Video Restyling demo" width="120">
        <br>
        <sub>▶ Play demo</sub>
      </a>
    </td>
  </tr>
  <tr>
    <td width="60%" valign="middle">
      <strong>Prompt:</strong> <code>视频风格变为参考图指定的风格</code>
      <br><br>
      <strong>Reference image:</strong> Select an image that captures the artistic style you want to apply.
    </td>
  </tr>
  <tr>
    <td rowspan="2" width="24%" valign="middle">
      <strong>AI Companions</strong>
    </td>
    <td width="60%" valign="middle">
      Summon virtual characters into your live camera feed and interact with them
      through gestures.
    </td>
    <td rowspan="2" width="16%" align="center" valign="middle">
      <a href="https://cdn.jsdelivr.net/gh/Xmax-AI/XmaxSDK-Flutter@main/materials/videos/use-cases/ai-companions.mp4">
        <img src="./materials/images/use-cases/ai-companions-poster.png" alt="Play the AI Companions demo" width="120">
        <br>
        <sub>▶ Play demo</sub>
      </a>
    </td>
  </tr>
  <tr>
    <td width="60%" valign="middle">
      <strong>Prompt:</strong> <code>指定角色在场景中互动</code>
      <br><br>
      <strong>Reference image:</strong> Select a clear image of the virtual character you want to summon with a clean background.
    </td>
  </tr>
</table>

<br>

## Why XmaxSDK?

<table>
  <thead>
    <tr>
      <th height="104" align="center" valign="middle">
        <img src="./materials/images/why/low-latency.svg" alt="Low latency" width="36" height="36"><br>Low latency
      </th>
      <th height="104" align="center" valign="middle">
        <img src="./materials/images/why/low-cost.svg" alt="Cost efficiency" width="36" height="36"><br>Cost efficiency
      </th>
      <th height="104" align="center" valign="middle">
        <img src="./materials/images/why/high-fidelity.svg" alt="High fidelity" width="36" height="36"><br>High fidelity
      </th>
    </tr>
  </thead>
  <tbody>
    <tr>
      <td>End-to-end latency is measured in <img src="./materials/images/why/latency-highlight.svg" alt="hundreds of milliseconds" width="192" height="20" align="absmiddle">, ensuring that updates to generation conditions and interaction controls are reflected instantly.</td>
      <td>Run on a <img src="./materials/images/why/gpu-highlight.svg" alt="single RTX 5090" width="126" height="20" align="absmiddle">, reducing inference costs by orders of magnitude versus datacenter GPUs like H100.</td>
      <td>Our models support real-time generation at up to <img src="./materials/images/why/resolution-highlight.svg" alt="1080p" width="48" height="20" align="absmiddle">, delivering production-ready, high-quality video output.</td>
    </tr>
  </tbody>
</table>

<br>

## Prerequisites

- Flutter 3.35 or later
- Dart 3.9 or later
- iOS 15.0 or later, or Android API 26 or later
- Java 17 for Android builds
- An Xmax API key

> [!WARNING]
> Never commit your Xmax API key to version control. Pass it securely at
> runtime or use short-lived temporary keys issued by the Xmax API. For step-by-step
> instructions, see [Authentication](https://platform.xmaxai.com/docs/authentication).

<br>

## Installation

XmaxSDK is published on [pub.dev](https://pub.dev/packages/xmax_sdk) and can also
be integrated from a Git revision or a local source checkout.

### pub.dev

Add XmaxSDK to your application's `pubspec.yaml`:

```yaml
dependencies:
  xmax_sdk: ^1.0.5
```

### Git

To use a release tag or commit directly from GitHub:

```yaml
dependencies:
  xmax_sdk:
    git:
      url: https://github.com/Xmax-AI/XmaxSDK-Flutter.git
      ref: 1.0.5
```

### Local path

To use a local source checkout during development:

```yaml
dependencies:
  xmax_sdk:
    path: ../XmaxSDK
```

Install the dependencies:

```bash
flutter pub get
```

<br>

## Host Configuration

### iOS

Set the deployment target to iOS 15.0 or later. For CocoaPods integration, use
the standard CocoaPods CDN source in `ios/Podfile`:

```ruby
source 'https://cdn.cocoapods.org/'

platform :ios, '15.0'

target 'Runner' do
  use_frameworks!

  # Keep the Flutter pod installation generated by the Flutter template here.
end
```

Enable camera and optional microphone permission handlers in the existing `post_install` block:

```ruby
post_install do |installer|
  installer.pods_project.targets.each do |target|
    flutter_additional_ios_build_settings(target)
    target.build_configurations.each do |config|
      config.build_settings['GCC_PREPROCESSOR_DEFINITIONS'] ||= [
        '$(inherited)',
        'PERMISSION_CAMERA=1',
        'PERMISSION_MICROPHONE=1',
      ]
    end
  end
end
```

Add a camera usage description to `ios/Runner/Info.plist`. Include the microphone
description if your app enables microphone input:

```xml
<key>NSCameraUsageDescription</key>
<string>This app uses the camera for real-time video input.</string>
<key>NSMicrophoneUsageDescription</key>
<string>This app uses the microphone for real-time audio input.</string>
```

Customize this message to match your application's user experience. XmaxSDK
automatically requests camera access when creating the video stream. With
`useMicrophone: true`, it also requests microphone access. Stream creation fails
with an `XmaxError` if a required permission is denied or unavailable.

See the complete [`example/ios/Podfile`](example/ios/Podfile) for a working setup.

With Swift Package Manager, the permission plugin derives its enabled permissions
from the usage descriptions in `Info.plist`. After adding a permission, refresh
the Swift package manifest and the app's derived build caches once, then rebuild;
an existing cached configuration can otherwise keep that permission disabled.

### Android

Set the application's minimum SDK to 26 and compile with Java 17 in
`android/app/build.gradle.kts`:

```kotlin
android {
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        minSdk = 26
    }
}
```

Use the standard Google and Maven Central dependency repositories in
`android/build.gradle.kts`:

```kotlin
allprojects {
    repositories {
        google()
        mavenCentral()
    }
}
```

Also make it available while Flutter plugins are resolved in
`android/settings.gradle.kts`:

```kotlin
pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}
```

Enable AndroidX and Jetifier in `android/gradle.properties`:

```properties
android.useAndroidX=true
android.enableJetifier=true
```

Declare the required permissions in `android/app/src/main/AndroidManifest.xml`:

```xml
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.CAMERA" />
<uses-permission android:name="android.permission.RECORD_AUDIO" />
<uses-permission android:name="android.permission.MODIFY_AUDIO_SETTINGS" />
```

`RECORD_AUDIO` is required only when using `useMicrophone: true`. External sources
can submit their own PCM audio without microphone permission. The example's
[`AndroidManifest.xml`](example/android/app/src/main/AndroidManifest.xml)
removes unused capabilities during manifest merging.

Release builds with R8 must also suppress warnings for optional device and serializer
APIs referenced by Tencent COS. Add the following rules to the
host application's Release ProGuard configuration:

```proguard
-dontwarn java.awt.**
-dontwarn javax.money.**
-dontwarn com.google.common.collect.ArrayListMultimap
-dontwarn com.google.common.collect.Multimap
-dontwarn org.javamoney.moneta.**
-dontwarn org.joda.time.**
-dontwarn springfox.documentation.spring.web.json.Json
```

The same configuration is available in the example's
[`proguard-rules.pro`](example/android/app/proguard-rules.pro).

<br>

## Quick Start

Complete the [host configuration](#host-configuration) before running these examples.

### Create a client

Create a client and a realtime manager for your screen. This example uses the China
service; for the global service, use `XmaxEnvironment.global` with the same X2.1 model.

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:xmax_sdk/xmax_sdk.dart';

final client = XmaxClient(
  configuration: XmaxConfiguration(apiKey: 'YOUR_XMAX_API_KEY'),
);
late final realtime = client.createRealtimeManager(
  options: const RealtimeConfiguration(
    model: RealtimeModel.x2_1,
  ),
);
```

<br>

### Generate and display video

Keep the manager and streams in your widget's state, and display the local track
before starting generation. `XmaxRealtimeDualVideo` switches from preview to the
generated video when its first frame is ready.

```dart
RealtimeMediaStream? localStream;
RealtimeMediaStream? remoteStream;

Future<void> startGeneration() async {
  final local = await realtime.createLocalCameraStream();
  if (!mounted) return;
  setState(() => localStream = local);

  final remote = await realtime.startGeneration(
    localStream: local,
    context: RealtimeContext(
      prompt: '视频中角色替换成参考图中角色',
      referencePath:
          'https://platform.xmaxai.com/images/source/charx/chatx_image1.jpg',
    ),
  );
  if (!mounted) return;
  setState(() => remoteStream = remote);
}
```

```dart
@override
Widget build(BuildContext context) {
  final local = localStream;
  if (local == null) {
    return const Center(child: CircularProgressIndicator());
  }

  return XmaxRealtimeDualVideo(
    localTrack: local.videoTrack,
    remoteTrack: remoteStream?.videoTrack,
  );
}
```

<br>

### Listen for events

Register listeners before creating the input stream. Observe state changes and
runtime failures through `setStateListener`, and handle errors from awaited calls
with `try` / `catch`.

```dart
await realtime.setStateListener((state) {
  debugPrint('State: ${state.connectionState.value}');
  final error = state.reason?.error;
  if (error != null) {
    debugPrint('Error: ${error.code.value} ${error.message}');
  }
});
```

<br>

### Resource cleanup

Use `disconnect()` to stop generation while keeping the local preview active:

```dart
await realtime.disconnect();
```

Call `close()` when leaving the screen to release all SDK resources; there is no
need to disconnect first.

```dart
@override
void dispose() {
  unawaited(realtime.close());
  super.dispose();
}
```

<br>

### Upload a reference image

`RealtimeContext.referencePath` accepts a remote image URL. Upload a local image
through the storage manager and pass the returned URL as the reference.

```dart
final storage = client.createStorageManager();
final uploaded = await storage.uploadImage(
  at: Uri.file('/path/to/reference.jpg'),
);
final referenceImageURL = uploaded.url.toString();
```

<br>

See the [XLab realtime example](example/lib/features/realtime/realtime_page.dart)
for external capture, recording, touch interaction, and quality controls. Detailed
contracts are documented in the
[realtime API](lib/src/core/realtime/XmaxRealtimeManaging.dart) and
[storage API](lib/src/core/storage/XmaxStorageManaging.dart).

<br>

## Example Project

A complete example application for both iOS and Android is available in
[`example`](https://github.com/Xmax-AI/XmaxSDK-Flutter/tree/main/example). It
demonstrates real-time generation using live camera feeds and app-owned external
video sources, including decoded video and optional PCM audio.

<p align="center"><img src="./materials/images/xlab/home.jpg" alt="X-Lab home" width="20%" /><img src="./materials/images/xlab/features.jpg" alt="X-Lab SDK features" width="20%" /><img src="./materials/images/xlab/storage.jpg" alt="X-Lab storage service" width="20%" /><img src="./materials/images/xlab/realtime-generation.jpg" alt="X-Lab realtime generation" width="20%" /><img src="./materials/images/xlab/trajectory-generation.jpg" alt="X-Lab trajectory generation" width="20%" /></p>

<br>

## Dependencies

- <ins><strong>Agora RTC SDK</strong></ins> enables low-latency, real-time audio and video communication.
- <ins><strong>Tencent Cloud COS SDK</strong></ins> handles media upload and download via object storage.

<br>

## Contact us

For bug reports and feature requests, please open a
[GitHub Issue](https://github.com/Xmax-AI/XmaxSDK-Flutter/issues). For integration
assistance and technical support, contact us at [sdk@xmax.ai](mailto:sdk@xmax.ai).

<br>

## License

XmaxSDK is available under the terms of the [MIT License](LICENSE).
