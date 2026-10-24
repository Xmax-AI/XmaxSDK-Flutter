import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencentcloud_cos_sdk_plugin_nobeacon/cos.dart';
import 'package:xmax_sdk/src/foundation/storage/StorageConfiguration.dart';
import 'package:xmax_sdk/src/foundation/storage/StorageCredential.dart';
import 'package:xmax_sdk/src/foundation/storage/StorageManager.dart';
import 'package:xmax_sdk/src/foundation/storage/StorageUploadSource.dart';
import 'package:xmax_sdk/xmax_sdk.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  var index = 0;
  late StorageConfiguration configuration;
  late StorageManager manager;
  late List<List<Object?>> registrations;
  late List<List<Object?>> cancellations;
  late Completer<void> started, bothStarted;
  Completer<void>? registrationGate;
  var inlineSuccess = false, cancelFails = false;
  final cancelled = throwsA(
    isA<XmaxError>().having(
      (error) => error.code,
      'code',
      XmaxErrorCode.cancelled,
    ),
  );

  void mock(String method, Future<Object?> Function(Object?) handler) {
    for (final prefix in [
      'dev.flutter.pigeon.',
      'dev.flutter.pigeon.tencentcloud_cos_sdk_plugin.',
    ]) {
      final channel = BasicMessageChannel<Object?>(
        '$prefix$method',
        const _Codec(),
      );
      messenger.setMockDecodedMessageHandler<Object?>(channel, handler);
      addTearDown(
        () => messenger.setMockDecodedMessageHandler<Object?>(channel, null),
      );
    }
  }

  List<Object?> record(String key) =>
      registrations.singleWhere((args) => args[2] == key);
  void complete(String key) {
    final args = record(key);
    Cos().getTransferManger(args[0]! as String).runResultSuccessCallBack(
      args[12]! as int,
      {'etag': 'uploaded'},
      null,
    );
  }

  void progress(String key) {
    final args = record(key);
    Cos()
        .getTransferManger(args[0]! as String)
        .runProgressCallBack(args[14]! as int, 3, 3);
  }

  setUp(() {
    registrations = [];
    cancellations = [];
    started = Completer<void>();
    bothStarted = Completer<void>();
    registrationGate = null;
    inlineSuccess = false;
    cancelFails = false;
    configuration = StorageConfiguration(
      bucket: 'cancel-tests-${++index}',
      region: 'ap-shanghai',
      endpoint: '',
      credential: const StorageCredential(
        accessKeyID: 'id',
        secretAccessKey: 'secret',
        sessionToken: 'token',
      ),
    );
    final client = HttpClient();
    addTearDown(() => client.close(force: true));
    manager = StorageManager(httpClient: client);
    mock('CosApi.initWithSessionCredential', (_) async => [null]);
    mock(
      'CosApi.registerTransferManger',
      (message) async => [(message! as List).first],
    );
    mock('CosTransferApi.upload', (message) async {
      final args = List<Object?>.from(message! as List);
      registrations.add(args);
      if (!started.isCompleted) started.complete();
      if (registrations.length == 2) bothStarted.complete();
      if (inlineSuccess) complete(args[2]! as String);
      await registrationGate?.future;
      return ['task-${args[2]}'];
    });
    mock('CosTransferApi.cancel', (message) async {
      cancellations.add(List<Object?>.from(message! as List));
      return cancelFails ? ['native', 'already ended', null] : [null];
    });
  });

  Future<XmaxError?> upload(
    String key,
    XmaxStorageCancellationToken token, {
    void Function(int, int)? onProgress,
  }) async {
    try {
      await manager.upload(
        source: StorageDataUploadSource(Uint8List.fromList([1, 2, 3])),
        objectKey: key,
        contentType: 'image/png',
        configuration: configuration,
        cancellationToken: token,
        progress: onProgress,
      );
      return null;
    } on XmaxError catch (error) {
      return error;
    }
  }

  test(
    'an already cancelled upload never registers a native transfer',
    () async {
      final token = XmaxStorageCancellationToken()..cancel();
      expect((await upload('pre.png', token))?.code, XmaxErrorCode.cancelled);
      expect(registrations, isEmpty);
      expect(cancellations, isEmpty);
    },
  );

  test(
    'cancellation during registration waits for its task and cancels exactly that task',
    () async {
      registrationGate = Completer<void>();
      final token = XmaxStorageCancellationToken();
      var completed = false;
      final result = upload('pending.png', token).then((value) {
        completed = true;
        return value;
      });
      await started.future;
      token.cancel();
      await Future<void>.delayed(Duration.zero);
      expect(completed, isFalse);
      expect(cancellations, isEmpty);
      progress('pending.png');
      registrationGate!.complete();
      expect((await result)?.code, XmaxErrorCode.cancelled);
      expect(cancellations.single.first, 'task-pending.png');
      complete('pending.png');
      expect(cancellations, hasLength(1));
    },
  );

  test(
    'cancelling one active upload preserves another and ignores late callbacks',
    () async {
      final firstToken = XmaxStorageCancellationToken();
      final secondToken = XmaxStorageCancellationToken();
      var firstProgress = 0, secondProgress = 0;
      final first = upload(
        'first.png',
        firstToken,
        onProgress: (_, _) => firstProgress++,
      );
      final second = upload(
        'second.png',
        secondToken,
        onProgress: (_, _) => secondProgress++,
      );
      await bothStarted.future;
      await Future<void>.delayed(Duration.zero);
      firstToken.cancel();
      expect((await first)?.code, XmaxErrorCode.cancelled);
      progress('first.png');
      complete('first.png');
      progress('second.png');
      complete('second.png');
      expect(await second, isNull);
      secondToken.cancel();
      expect(firstProgress, 0);
      expect(secondProgress, 1);
      expect(cancellations, hasLength(1));
      expect(cancellations.single.first, 'task-first.png');
    },
  );

  test('completed uploads are not cancelled by a later token signal', () async {
    inlineSuccess = true;
    final token = XmaxStorageCancellationToken();
    expect(await upload('done.png', token), isNull);
    token.cancel();
    expect(cancellations, isEmpty);
  });

  test(
    'native cancellation failure preserves the cancellation result',
    () async {
      cancelFails = true;
      final token = XmaxStorageCancellationToken();
      final pending = upload('failed.png', token);
      await started.future;
      await Future<void>.delayed(Duration.zero);
      token.cancel();
      expect((await pending)?.code, XmaxErrorCode.cancelled);
      expect(cancellations.single.first, 'task-failed.png');
      complete('failed.png');
    },
  );

  test('file-backed video cancellation preserves the source file', () async {
    final directory = await Directory.systemTemp.createTemp(
      'xmax-upload-cancel-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/video.mp4');
    await file.writeAsBytes([1, 2, 3]);
    final token = XmaxStorageCancellationToken();
    final pending = expectLater(
      manager.upload(
        source: StorageFileUploadSource(file.uri),
        objectKey: 'video.mp4',
        contentType: 'video/mp4',
        configuration: configuration,
        cancellationToken: token,
      ),
      cancelled,
    );
    await started.future;
    await Future<void>.delayed(Duration.zero);
    token.cancel();
    await pending;
    expect(await file.readAsBytes(), [1, 2, 3]);
    expect(record('video.mp4')[4], file.path);
    expect(record('video.mp4')[5], isNull);
    expect(cancellations.single.first, 'task-video.mp4');
    complete('video.mp4');
  });
}

class _Codec extends StandardMessageCodec {
  const _Codec();
  @override
  Object? readValueOfType(int type, ReadBuffer buffer) =>
      type >= 128 && type <= 146
      ? readValue(buffer)
      : super.readValueOfType(type, buffer);
}
