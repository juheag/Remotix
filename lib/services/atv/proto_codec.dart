// Minimal hand-written Protocol Buffers wire-format encoder/decoder.
//
// The Android TV Remote protocol (polo.proto for pairing, remotemessage.proto
// for key injection) uses plain protobuf framing but there is no `protoc`
// toolchain available in this environment to generate Dart bindings, so the
// small subset of the wire format actually needed (varints and
// length-delimited fields) is implemented directly here, matching the field
// numbers documented in the upstream .proto files.
import 'dart:convert';
import 'dart:typed_data';

/// Encodes a single protobuf message body (tag/value pairs). Field
/// presence/omission for `optional`/proto3 fields is controlled explicitly
/// by the caller; this class never guesses.
class ProtoWriter {
  final BytesBuilder _buffer = BytesBuilder();

  static Uint8List encodeVarint(int value) {
    final out = BytesBuilder();
    var v = value;
    while (v > 0x7F) {
      out.addByte((v & 0x7F) | 0x80);
      v >>= 7;
    }
    out.addByte(v & 0x7F);
    return out.toBytes();
  }

  void _varint(int value) => _buffer.add(encodeVarint(value));

  void _tag(int fieldNumber, int wireType) => _varint((fieldNumber << 3) | wireType);

  void varintField(int fieldNumber, int value) {
    _tag(fieldNumber, 0);
    _varint(value);
  }

  void boolField(int fieldNumber, bool value) => varintField(fieldNumber, value ? 1 : 0);

  void bytesField(int fieldNumber, List<int> value) {
    _tag(fieldNumber, 2);
    _varint(value.length);
    _buffer.add(value);
  }

  void stringField(int fieldNumber, String value) => bytesField(fieldNumber, utf8.encode(value));

  void messageField(int fieldNumber, Uint8List encodedSubMessage) => bytesField(fieldNumber, encodedSubMessage);

  Uint8List toBytes() => _buffer.toBytes();
}

/// One decoded protobuf field: either a varint or a length-delimited blob.
/// Wire type 5/1 (fixed32/fixed64) are not needed by this protocol and are
/// intentionally unsupported.
class ProtoField {
  final int wireType;
  final int? varintValue;
  final Uint8List? bytesValue;

  const ProtoField.varint(this.varintValue) : wireType = 0, bytesValue = null;
  const ProtoField.bytes(this.bytesValue) : wireType = 2, varintValue = null;
}

class _VarintResult {
  final int value;
  final int nextPos;
  const _VarintResult(this.value, this.nextPos);
}

/// Parses a message body into a map of field number -> values (a field may
/// repeat, e.g. `repeated` fields), without needing a schema up front.
/// Callers interpret the fields they expect and ignore the rest.
class ProtoReader {
  static Map<int, List<ProtoField>> parse(Uint8List data) {
    final fields = <int, List<ProtoField>>{};
    var pos = 0;
    while (pos < data.length) {
      final tagResult = _readVarint(data, pos);
      pos = tagResult.nextPos;
      final fieldNumber = tagResult.value >> 3;
      final wireType = tagResult.value & 0x7;

      if (wireType == 0) {
        final r = _readVarint(data, pos);
        pos = r.nextPos;
        fields.putIfAbsent(fieldNumber, () => []).add(ProtoField.varint(r.value));
      } else if (wireType == 2) {
        final lenResult = _readVarint(data, pos);
        pos = lenResult.nextPos;
        final end = pos + lenResult.value;
        if (end > data.length) {
          throw const FormatException('Truncated protobuf message');
        }
        final bytes = data.sublist(pos, end);
        pos = end;
        fields.putIfAbsent(fieldNumber, () => []).add(ProtoField.bytes(bytes));
      } else {
        throw FormatException('Unsupported protobuf wire type $wireType');
      }
    }
    return fields;
  }

  static _VarintResult _readVarint(Uint8List data, int pos) {
    var result = 0;
    var shift = 0;
    while (true) {
      if (pos >= data.length) {
        throw const FormatException('Truncated varint');
      }
      final b = data[pos];
      pos++;
      result |= (b & 0x7F) << shift;
      if ((b & 0x80) == 0) break;
      shift += 7;
    }
    return _VarintResult(result, pos);
  }

  /// Reads one varint straight off the wire and reports how many bytes it
  /// consumed. Used for the outer length-prefix framing (not a proto field).
  static (int value, int bytesRead) readLengthPrefix(Uint8List data, int offset) {
    final r = _readVarint(data, offset);
    return (r.value, r.nextPos - offset);
  }
}
