// Wire-level messages for the ongoing remote-control connection
// (remotemessage.proto / RemoteMessage) on port 6466. Field numbers are
// taken verbatim from
// https://github.com/tronikos/androidtvremote2/blob/main/src/androidtvremote2/remotemessage.proto
import 'dart:typed_data';

import 'atv_key_code.dart';
import 'proto_codec.dart';

Uint8List _encodeDeviceInfo() {
  final w = ProtoWriter();
  w.varintField(3, 1); // unknown1
  w.stringField(4, '1'); // unknown2
  w.stringField(5, 'com.remotix.app'); // package_name
  w.stringField(6, '1.0.0'); // app_version
  return w.toBytes();
}

/// Reply to the server's `remote_configure`, echoing the features we
/// support and identifying this client.
Uint8List buildRemoteConfigureMessage(int activeFeatures) {
  final cfg = ProtoWriter();
  cfg.varintField(1, activeFeatures); // code1
  cfg.messageField(2, _encodeDeviceInfo()); // device_info

  final msg = ProtoWriter();
  msg.messageField(1, cfg.toBytes()); // remote_configure
  return msg.toBytes();
}

/// Reply to the server's `remote_set_active`.
Uint8List buildRemoteSetActiveMessage(int activeFeatures) {
  final setActive = ProtoWriter();
  setActive.varintField(1, activeFeatures); // active

  final msg = ProtoWriter();
  msg.messageField(2, setActive.toBytes()); // remote_set_active
  return msg.toBytes();
}

/// Keepalive reply: the TV pings roughly every 5s and disconnects after 3
/// unanswered pings, so this must be echoed back promptly.
Uint8List buildPingResponseMessage(int val1) {
  final ping = ProtoWriter();
  ping.varintField(1, val1);

  final msg = ProtoWriter();
  msg.messageField(9, ping.toBytes()); // remote_ping_response
  return msg.toBytes();
}

/// A single button press/release to send to the TV.
Uint8List buildKeyInjectMessage(AtvKeyCode key, AtvKeyDirection direction) {
  final inject = ProtoWriter();
  inject.varintField(1, key.wireValue); // key_code
  inject.varintField(2, direction.wireValue); // direction

  final msg = ProtoWriter();
  msg.messageField(10, inject.toBytes()); // remote_key_inject
  return msg.toBytes();
}

enum RemoteServerMessageKind {
  configure,
  setActive,
  pingRequest,
  start,
  volumeLevel,
  error,
  unknown,
}

class RemoteServerMessage {
  final RemoteServerMessageKind kind;
  final int remoteConfigureCode1;
  final int pingVal1;
  final bool started;
  final int volumeLevel;
  final int volumeMax;
  final bool volumeMuted;

  const RemoteServerMessage._({
    required this.kind,
    this.remoteConfigureCode1 = 0,
    this.pingVal1 = 0,
    this.started = false,
    this.volumeLevel = 0,
    this.volumeMax = 0,
    this.volumeMuted = false,
  });

  static RemoteServerMessage unknown() => const RemoteServerMessage._(kind: RemoteServerMessageKind.unknown);
}

RemoteServerMessage parseRemoteServerMessage(Uint8List data) {
  final fields = ProtoReader.parse(data);

  if (fields.containsKey(1)) {
    final cfgFields = ProtoReader.parse(fields[1]!.first.bytesValue!);
    final code1 = cfgFields[1]?.first.varintValue ?? 0;
    return RemoteServerMessage._(kind: RemoteServerMessageKind.configure, remoteConfigureCode1: code1);
  }
  if (fields.containsKey(2)) {
    return const RemoteServerMessage._(kind: RemoteServerMessageKind.setActive);
  }
  if (fields.containsKey(3)) {
    return const RemoteServerMessage._(kind: RemoteServerMessageKind.error);
  }
  if (fields.containsKey(8)) {
    final pingFields = ProtoReader.parse(fields[8]!.first.bytesValue!);
    final val1 = pingFields[1]?.first.varintValue ?? 0;
    return RemoteServerMessage._(kind: RemoteServerMessageKind.pingRequest, pingVal1: val1);
  }
  if (fields.containsKey(40)) {
    final startFields = ProtoReader.parse(fields[40]!.first.bytesValue!);
    final started = (startFields[1]?.first.varintValue ?? 0) != 0;
    return RemoteServerMessage._(kind: RemoteServerMessageKind.start, started: started);
  }
  if (fields.containsKey(50)) {
    final volFields = ProtoReader.parse(fields[50]!.first.bytesValue!);
    return RemoteServerMessage._(
      kind: RemoteServerMessageKind.volumeLevel,
      volumeLevel: volFields[7]?.first.varintValue ?? 0,
      volumeMax: volFields[6]?.first.varintValue ?? 0,
      volumeMuted: (volFields[8]?.first.varintValue ?? 0) != 0,
    );
  }
  return RemoteServerMessage.unknown();
}
