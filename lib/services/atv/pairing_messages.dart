// Wire-level messages for the pairing handshake (polo.proto / OuterMessage),
// used once per device the first time Remotix connects to it on port 6467.
// Field numbers below are taken verbatim from
// https://github.com/tronikos/androidtvremote2/blob/main/src/androidtvremote2/polo.proto
import 'dart:typed_data';

import 'proto_codec.dart';

const int _statusOk = 200;
const int _roleTypeInput = 1;
const int _encodingTypeHexadecimal = 3;
const int _hexSymbolLength = 6;

class PoloEncoding {
  static Uint8List encode() {
    final w = ProtoWriter();
    w.varintField(1, _encodingTypeHexadecimal);
    w.varintField(2, _hexSymbolLength);
    return w.toBytes();
  }
}

/// Builds the OuterMessage that kicks off pairing: a PairingRequest.
Uint8List buildPairingRequestMessage({required String clientName}) {
  final request = ProtoWriter();
  request.stringField(1, 'atvremote'); // service_name
  request.stringField(2, clientName); // client_name

  final outer = ProtoWriter();
  outer.varintField(1, 2); // protocol_version
  outer.varintField(2, _statusOk); // status
  outer.messageField(10, request.toBytes()); // pairing_request
  return outer.toBytes();
}

/// Builds the OuterMessage answering the server's `options` with our chosen
/// hexadecimal/6-digit encoding and INPUT role.
Uint8List buildOptionsMessage() {
  final options = ProtoWriter();
  options.messageField(1, PoloEncoding.encode()); // input_encodings
  options.varintField(3, _roleTypeInput); // preferred_role

  final outer = ProtoWriter();
  outer.varintField(1, 2);
  outer.varintField(2, _statusOk);
  outer.messageField(20, options.toBytes()); // options
  return outer.toBytes();
}

/// Builds the OuterMessage confirming the session Configuration.
Uint8List buildConfigurationMessage() {
  final configuration = ProtoWriter();
  configuration.messageField(1, PoloEncoding.encode()); // encoding
  configuration.varintField(2, _roleTypeInput); // client_role

  final outer = ProtoWriter();
  outer.varintField(1, 2);
  outer.varintField(2, _statusOk);
  outer.messageField(30, configuration.toBytes()); // configuration
  return outer.toBytes();
}

/// Builds the OuterMessage carrying the SHA-256 secret derived from the PIN
/// shown on the TV and both certificates' public keys.
Uint8List buildSecretMessage(Uint8List secretHash) {
  final secret = ProtoWriter();
  secret.bytesField(1, secretHash);

  final outer = ProtoWriter();
  outer.varintField(1, 2);
  outer.varintField(2, _statusOk);
  outer.messageField(40, secret.toBytes()); // secret
  return outer.toBytes();
}

/// What the server's last OuterMessage means for the pairing state machine.
enum PoloServerMessageKind {
  pairingRequestAck,
  options,
  configurationAck,
  secretAck,
  unknown,
}

class PoloServerMessage {
  final PoloServerMessageKind kind;
  final int status;
  const PoloServerMessage(this.kind, this.status);
}

PoloServerMessage parsePoloServerMessage(Uint8List data) {
  final fields = ProtoReader.parse(data);
  final status = fields[2]?.first.varintValue ?? _statusOk;
  if (fields.containsKey(11)) return PoloServerMessage(PoloServerMessageKind.pairingRequestAck, status);
  if (fields.containsKey(20)) return PoloServerMessage(PoloServerMessageKind.options, status);
  if (fields.containsKey(31)) return PoloServerMessage(PoloServerMessageKind.configurationAck, status);
  if (fields.containsKey(41)) return PoloServerMessage(PoloServerMessageKind.secretAck, status);
  return PoloServerMessage(PoloServerMessageKind.unknown, status);
}
