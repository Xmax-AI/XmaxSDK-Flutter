import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencentcloud_cos_sdk_plugin_nobeacon/cos.dart';
import 'package:tencentcloud_cos_sdk_plugin_nobeacon/pigeon.dart';
import 'package:xmax_sdk/src/foundation/storage/StorageManager.dart';
import 'package:xmax_sdk/src/foundation/storage/StorageCredential.dart';
import 'package:xmax_sdk/src/foundation/storage/StorageConfiguration.dart';
import 'package:xmax_sdk/src/foundation/storage/StorageUploadSource.dart';
import 'package:xmax_sdk/src/foundation/storage/StoredFile.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'concurrent uploads initialize signing before registering simple PUT',
    () async {
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      void mockChannel(
        String method,
        Future<Object?> Function(Object?) handler,
      ) {
        // Generated channel names differ between supported plugin versions.
        // Decode request records without relying on generated codec symbols.
        for (final prefix in [
          'dev.flutter.pigeon.',
          'dev.flutter.pigeon.tencentcloud_cos_sdk_plugin.',
        ]) {
          final channel = BasicMessageChannel<Object?>(
            '$prefix$method',
            const _CosRequestCodec(),
          );
          messenger.setMockDecodedMessageHandler<Object?>(channel, handler);
          addTearDown(
            () =>
                messenger.setMockDecodedMessageHandler<Object?>(channel, null),
          );
        }
      }

      final initialized = Completer<void>();
      final initStarted = Completer<void>();
      var initCount = 0;
      var registerCount = 0;
      final requests = <List<Object?>>[];

      mockChannel('CosApi.initWithSessionCredential', (_) async {
        initCount += 1;
        initStarted.complete();
        await initialized.future;
        return <Object?>[null];
      });
      mockChannel('CosApi.registerTransferManger', (message) async {
        expect(initialized.isCompleted, isTrue);
        registerCount += 1;
        final args = message! as List<Object?>;
        final config = TransferConfig.decode(args[2]!);
        expect(config.forceSimpleUpload, isTrue);
        expect(config.divisionForUpload, 0x7FFFFFFFFFFFFFFF);
        return <Object?>[args[0]];
      });
      mockChannel('CosTransferApi.upload', (message) async {
        final args = message! as List<Object?>;
        requests.add(args);
        expect(args[6], isNull, reason: 'Never resume a multipart upload');
        final credential = SessionQCloudCredentials.decode(args[16]!);
        expect(
          credential.token,
          args[1] == 'image-123' ? 'image-token' : 'video-token',
        );
        final transfer = Cos().getTransferManger(args[0]! as String);
        transfer.runProgressCallBack(args[14]! as int, 10, 10);
        transfer.runResultSuccessCallBack(args[12]! as int, <String, String>{
          'etag': 'test-etag',
        }, null);
        return <Object?>['test-upload'];
      });

      final directory = await Directory.systemTemp.createTemp(
        'xmax-upload-test-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}/video.mp4');
      await file.writeAsBytes(<int>[1, 2, 3]);
      final client = HttpClient();
      addTearDown(() => client.close(force: true));
      final manager = StorageManager(httpClient: client);
      final progress = <int>[];

      StorageConfiguration configuration(String media) => StorageConfiguration(
        bucket: '$media-123',
        region: 'ap-shanghai',
        endpoint: '',
        credential: StorageCredential(
          accessKeyID: '$media-id',
          secretAccessKey: '$media-secret',
          sessionToken: '$media-token',
        ),
      );

      final image = manager.upload(
        source: StorageDataUploadSource(Uint8List(9 * 1024 * 1024)),
        objectKey: 'image.jpg',
        contentType: 'image/jpeg',
        configuration: configuration('image'),
        progress: (completed, _) => progress.add(completed),
      );
      final video = manager.upload(
        source: StorageFileUploadSource(file.uri),
        objectKey: 'video.mp4',
        contentType: 'video/mp4',
        configuration: configuration('video'),
        progress: (completed, _) => progress.add(completed),
      );
      await initStarted.future;
      expect(initCount, 1);
      expect(registerCount, 0);
      expect(requests, isEmpty);
      initialized.complete();

      final results = await Future.wait(<Future<StoredFile>>[image, video]);
      expect(registerCount, 2);
      expect(requests, hasLength(2));
      final imageRequest = requests.singleWhere(
        (args) => args[1] == 'image-123',
      );
      final videoRequest = requests.singleWhere(
        (args) => args[1] == 'video-123',
      );
      expect((imageRequest[5]! as Uint8List).length, 9 * 1024 * 1024);
      expect(videoRequest[4], file.path);
      expect(videoRequest[5], isNull, reason: 'Video stays file-backed');
      expect(progress, <int>[10, 10]);
      expect(results.map((result) => result.etag), everyElement('test-etag'));
    },
  );
}

/// Pigeon wraps each custom request value in a type tag followed by its fields.
/// Leave those fields intact so the installed plugin can decode its own model.
class _CosRequestCodec extends StandardMessageCodec {
  const _CosRequestCodec();

  @override
  Object? readValueOfType(int type, ReadBuffer buffer) {
    if (type >= 128 && type <= 146) return readValue(buffer);
    return super.readValueOfType(type, buffer);
  }
}
