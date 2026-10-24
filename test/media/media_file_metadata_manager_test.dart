import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xmax_sdk/src/foundation/media/MediaFileMetadataManager.dart';
import 'package:xmax_sdk/src/foundation/storage/StorageUploadSource.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('ai.xmax.sdk/media');
  const reader = MediaFileMetadataManager();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test(
    'image bytes and video file paths report dimensions through native metadata',
    () async {
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return {'width': 832, 'height': 1472};
      });
      final data = Uint8List.fromList([1, 2, 3]);
      expect(
        await reader.readResolution(
          StorageDataUploadSource(data),
          isVideo: false,
        ),
        '832 × 1472',
      );
      expect(calls.single.method, 'readResolution');
      expect(calls.single.arguments, {'mediaType': 'image', 'data': data});
      expect(
        await reader.readResolution(
          StorageFileUploadSource(Uri.file('/tmp/video test.mp4')),
          isVideo: true,
        ),
        '832 × 1472',
      );
      expect(calls.last.arguments, {
        'mediaType': 'video',
        'filePath': '/tmp/video test.mp4',
      });
    },
  );

  test(
    'byte-backed videos match iOS without creating temporary files',
    () async {
      messenger.setMockMethodCallHandler(
        channel,
        (_) async => fail('Unexpected metadata request'),
      );
      expect(
        await reader.readResolution(
          StorageDataUploadSource(Uint8List(1)),
          isVideo: true,
        ),
        '--',
      );
    },
  );

  test(
    'missing, corrupt, and unsupported metadata safely returns placeholder',
    () async {
      final source = StorageFileUploadSource(Uri.file('/tmp/image.png'));
      expect(await reader.readResolution(source, isVideo: false), '--');
      for (final metadata in [
        null,
        {'width': 0, 'height': 800},
        {'width': 'bad', 'height': 800},
      ]) {
        messenger.setMockMethodCallHandler(channel, (_) async => metadata);
        expect(await reader.readResolution(source, isVideo: false), '--');
      }
      messenger.setMockMethodCallHandler(
        channel,
        (_) async => throw PlatformException(code: 'unsupported'),
      );
      expect(await reader.readResolution(source, isVideo: false), '--');
    },
  );
}
