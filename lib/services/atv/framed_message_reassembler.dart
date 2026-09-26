// Both Android TV Remote sockets (pairing on 6467, control on 6466) frame
// each protobuf message as [varint length][message bytes]. TCP delivers
// bytes in arbitrary chunks, so incoming data has to be reassembled before
// it can be parsed as discrete messages.
import 'dart:typed_data';

import 'proto_codec.dart';

class FramedMessageReassembler {
  final List<int> _buffer = <int>[];

  /// Feeds newly received bytes in and returns every message that is now
  /// fully available (zero or more).
  List<Uint8List> addChunk(List<int> chunk) {
    _buffer.addAll(chunk);
    final messages = <Uint8List>[];

    while (true) {
      int length;
      int prefixLen;
      try {
        final (len, read) = ProtoReader.readLengthPrefix(Uint8List.fromList(_buffer), 0);
        length = len;
        prefixLen = read;
      } catch (_) {
        break; // the length varint itself hasn't fully arrived yet
      }
      if (_buffer.length < prefixLen + length) break; // message body incomplete

      messages.add(Uint8List.fromList(_buffer.sublist(prefixLen, prefixLen + length)));
      _buffer.removeRange(0, prefixLen + length);
    }

    return messages;
  }
}
