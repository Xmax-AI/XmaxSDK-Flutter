import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:xmax_sdk/src/foundation/rtc/RtcMessageQueue.dart';
import 'package:xmax_sdk/src/stream/room/RoomMessageDecoder.dart';

Uint8List _bytes(Object value) => utf8.encode(jsonEncode(value));
Uint8List _part(int index, String data, {int count = 2, String id = 'id'}) =>
    _bytes({
      'event': '__agora_chunk__',
      'eventId': id,
      'index': index,
      'count': count,
      'data': data,
    });

void main() {
  test(
    'decodes plain objects and rejects malformed, oversized, or non-object input',
    () {
      final decoder = RoomMessageDecoder();
      expect(
        decoder.decode(
          sender: 'bot',
          data: _bytes({'event': 'xid_ack', 'xid': 'id', 'count': 1}),
        ),
        containsPair('xid', 'id'),
      );
      for (final data in [
        Uint8List.fromList([255]),
        utf8.encode('{'),
        _bytes([]),
        Uint8List(262145),
      ]) {
        expect(decoder.decode(sender: 'bot', data: data), isNull);
      }
    },
  );
  test(
    'reassembles out of order Unicode fragments and tolerates replacements',
    () {
      final decoder = RoomMessageDecoder();
      final source = {
        'event': 'xid_ack',
        'xid': 'id',
        'count': 1,
        'extra': '中🙂' * 600,
      };
      final packets = RtcMessageCodec.encode(jsonEncode(source));
      for (final packet in packets.skip(1).toList().reversed) {
        expect(decoder.decode(sender: 'bot', data: packet), isNull);
        expect(decoder.decode(sender: 'bot', data: packet), isNull);
      }
      expect(decoder.decode(sender: 'bot', data: packets.first), source);
    },
  );
  test('sender identity separates colliding provider identifiers', () {
    final decoder = RoomMessageDecoder();
    decoder.decode(sender: 'a', data: _part(0, '{"event":'));
    expect(decoder.decode(sender: 'b', data: _part(1, '"xid_ack"}')), isNull);
    expect(decoder.decode(sender: 'a', data: _part(1, '"xid_ack"}')), {
      'event': 'xid_ack',
    });
  });
  test(
    'invalid fragment metadata does not complete or replace a partial record',
    () {
      final decoder = RoomMessageDecoder();
      decoder.decode(sender: 'bot', data: _part(0, '{"event":'));
      for (final data in [
        _part(1, '"bad"}', count: 3),
        _part(-1, ''),
        _part(2, ''),
        _part(0, '', count: 513),
        _bytes({
          'event': '__agora_chunk__',
          'eventId': 'id',
          'index': 1.5,
          'count': 2,
          'data': '',
        }),
      ]) {
        expect(decoder.decode(sender: 'bot', data: data), isNull);
      }
      expect(decoder.decode(sender: 'bot', data: _part(1, '"xid_ack"}')), {
        'event': 'xid_ack',
      });
    },
  );
  test('per-message byte limit discards an oversized record', () {
    final decoder = RoomMessageDecoder();
    decoder.decode(sender: 'bot', data: _part(0, 'a' * 200000));
    expect(decoder.decode(sender: 'bot', data: _part(1, 'a' * 100000)), isNull);
    expect(decoder.decode(sender: 'bot', data: _part(1, '"xid_ack"}')), isNull);
    expect(decoder.decode(sender: 'bot', data: _part(0, '{"event":')), {
      'event': 'xid_ack',
    });
  });
  test(
    'record limit evicts oldest partial messages without refreshing duplicates',
    () {
      final decoder = RoomMessageDecoder();
      for (var i = 0; i <= 1000; i++) {
        decoder.decode(
          sender: 'bot',
          data: _part(0, '{"event":', id: '$i'),
        );
      }
      expect(
        decoder.decode(
          sender: 'bot',
          data: _part(1, '"xid_ack"}', id: '0'),
        ),
        isNull,
      );
      expect(
        decoder.decode(
          sender: 'bot',
          data: _part(1, '"xid_ack"}', id: '1000'),
        ),
        {'event': 'xid_ack'},
      );
    },
  );
  test(
    'aggregate byte limit evicts older messages independently of record limit',
    () {
      final decoder = RoomMessageDecoder();
      for (var i = 0; i < 180; i++) {
        decoder.decode(
          sender: 'bot',
          data: _part(0, '{"padding":"${'x' * 200000}",', id: '$i'),
        );
      }
      expect(
        decoder.decode(
          sender: 'bot',
          data: _part(1, '"event":"xid_ack"}', id: '0'),
        ),
        isNull,
      );
      expect(
        decoder.decode(
          sender: 'bot',
          data: _part(1, '"event":"xid_ack"}', id: '179'),
        )?['event'],
        'xid_ack',
      );
    },
  );
  test(
    'reset removes partial payloads and nested envelopes are not recursively decoded',
    () {
      final decoder = RoomMessageDecoder();
      decoder.decode(sender: 'bot', data: _part(0, '{"event":'));
      decoder.reset();
      expect(
        decoder.decode(sender: 'bot', data: _part(1, '"xid_ack"}')),
        isNull,
      );
      decoder.reset();
      final nested = {
        'event': '__agora_chunk__',
        'eventId': 'inner',
        'count': 1,
        'index': 0,
        'data': '{"event":"xid_ack"}',
      };
      expect(
        decoder.decode(
          sender: 'bot',
          data: _part(0, jsonEncode(nested), count: 1),
        ),
        nested,
      );
    },
  );
}
