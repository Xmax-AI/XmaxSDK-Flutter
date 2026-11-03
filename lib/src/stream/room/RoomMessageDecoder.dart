//
//  RoomMessageDecoder.dart
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-Flutter
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import 'dart:convert';
import 'dart:typed_data';

/// Reassembles bounded incoming room commands and receipts for one room lifetime.
final class RoomMessageDecoder {

  /// Creates a decoder with no retained partial messages.
  RoomMessageDecoder();

  /// Partial messages indexed by sender and provider fragment identifier.
  final Map<(String, String), _Record> _records = {};

  /// The aggregate retained UTF-8 bytes across incomplete messages.
  int _bytes = 0;

  /// Decodes plain JSON or completed, possibly out-of-order provider fragments.
  ///
  /// Parameters:
  /// - [sender]: The resolved account separating fragments from different senders.
  /// - [data]: The owned UTF-8 bytes, limited to 256 KiB per message or fragment envelope.
  ///
  /// Returns the completed object, or null for malformed, oversized, or incomplete input.
  Map<String, dynamic>? decode({
    required String sender,
    required Uint8List data,
  }) {
    if (data.length > 262144) {
      return null;
    }

    final message = _parse(data);
    if (message == null || message['event'] != '__agora_chunk__') {
      return message;
    }

    final eventID = message['eventId'];
    final index = message['index'];
    final count = message['count'];
    final part = message['data'];
    if (eventID is! String || eventID.isEmpty || index is! int ||
        count is! int || count < 1 || count > 512 || index < 0 ||
        index >= count || part is! String) {
      return null;
    }

    final key = (sender, eventID);
    final record = _records.putIfAbsent(
      key,
      () => _Record(count),
    );
    if (record.count != count) {
      return null;
    }
    final added = utf8.encode(part).length -
        utf8.encode(record.parts[index] ?? '').length;
    if (record.bytes + added > 262144) {
      _remove(key);
      return null;
    }

    record.parts[index] = part;
    record.bytes += added;
    _bytes += added;

    // Map insertion order bounds retained state without refreshing incomplete message lifetimes.
    while (_records.length > 1000 || _bytes > 32 * 1024 * 1024) {
      _remove(_records.keys.first);
    }
    if (!_records.containsKey(key) || record.parts.length != count) {
      return null;
    }

    _remove(key);
    return _parse(utf8.encode([
      for (var index = 0; index < count; index++) record.parts[index]!,
    ].join()));
  }

  /// Releases every incomplete message when the room is invalidated.
  void reset() {
    _records.clear();
    _bytes = 0;
  }

  /// Releases the retained byte accounting for an incomplete message identified by [key].
  void _remove(
    (String, String) key,
  ) {
    _bytes -= _records.remove(key)?.bytes ?? 0;
  }

  /// Parses strict UTF-8 JSON [data] without interpreting nested fragment envelopes.
  ///
  /// Returns an object or null when decoding fails or the root is not an object.
  static Map<String, dynamic>? _parse(
    Uint8List data,
  ) {
    try {
      final value = jsonDecode(utf8.decode(data));
      return value is Map<String, dynamic> ? value : null;
    } catch (_) {
      return null;
    }
  }
}

/// An incomplete message with a fixed fragment count and bounded payload.
final class _Record {

  /// Creates a partial message with its expected number of pieces.
  _Record(
    this.count,
  );

  /// The expected number of pieces, fixed by the first accepted fragment.
  final int count;

  /// The received JSON slices indexed by position.
  final Map<int, String> parts = {};

  /// The total retained UTF-8 payload bytes.
  int bytes = 0;
}
