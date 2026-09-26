// Maintains the ongoing control connection with an already-paired Android
// TV on port 6466: answers the device's configuration/keep-alive handshake
// and sends button presses.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'atv_identity.dart';
import 'atv_key_code.dart';
import 'framed_message_reassembler.dart';
import 'proto_codec.dart';
import 'remote_messages.dart';

const int atvRemotePort = 6466;

class AtvRemoteException implements Exception {
  final String message;
  const AtvRemoteException(this.message);
  @override
  String toString() => message;
}

enum AtvConnectionState { connecting, connected, disconnected }

class AtvRemoteClient {
  final String host;
  final AtvIdentity identity;

  SecureSocket? _socket;
  StreamSubscription<Uint8List>? _subscription;
  final _reassembler = FramedMessageReassembler();
  int _negotiatedFeatures = AtvFeature.supportedByClient;

  final _stateController = StreamController<AtvConnectionState>.broadcast();
  final _powerStateController = StreamController<bool>.broadcast();
  final _errorController = StreamController<String>.broadcast();

  Stream<AtvConnectionState> get connectionState => _stateController.stream;
  Stream<bool> get isTvOn => _powerStateController.stream;
  Stream<String> get errors => _errorController.stream;

  AtvRemoteClient({required this.host, required this.identity});

  /// Opens the control connection. The TV must already trust
  /// [identity.certificatePem] from a prior pairing, otherwise the TLS
  /// handshake will be rejected by the device.
  Future<void> connect() async {
    _stateController.add(AtvConnectionState.connecting);
    final context = SecurityContext(withTrustedRoots: false)
      ..useCertificateChainBytes(utf8.encode(identity.certificatePem))
      ..usePrivateKeyBytes(utf8.encode(identity.privateKeyPem));

    try {
      _socket = await SecureSocket.connect(
        host,
        atvRemotePort,
        context: context,
        onBadCertificate: (cert) => true,
        timeout: const Duration(seconds: 10),
      );
    } on Object catch (e) {
      _stateController.add(AtvConnectionState.disconnected);
      throw AtvRemoteException('No se pudo conectar a $host:$atvRemotePort: $e');
    }

    _stateController.add(AtvConnectionState.connected);
    _subscription = _socket!.listen(
      _onData,
      onError: (Object e, StackTrace st) => _handleDisconnect('Error de conexión: $e'),
      onDone: () => _handleDisconnect('La TV cerró la conexión.'),
    );
  }

  void sendKey(AtvKeyCode key, {AtvKeyDirection direction = AtvKeyDirection.shortPress}) {
    _send(buildKeyInjectMessage(key, direction));
  }

  Future<void> dispose() async {
    await _subscription?.cancel();
    await _socket?.close();
    await _stateController.close();
    await _powerStateController.close();
    await _errorController.close();
  }

  void _send(Uint8List message) {
    final socket = _socket;
    if (socket == null) return;
    socket.add(ProtoWriter.encodeVarint(message.length));
    socket.add(message);
  }

  void _onData(Uint8List chunk) {
    for (final message in _reassembler.addChunk(chunk)) {
      _handleMessage(message);
    }
  }

  void _handleMessage(Uint8List raw) {
    final RemoteServerMessage msg;
    try {
      msg = parseRemoteServerMessage(raw);
    } on Object catch (e) {
      _errorController.add('Mensaje inválido de la TV: $e');
      return;
    }

    switch (msg.kind) {
      case RemoteServerMessageKind.configure:
        _negotiatedFeatures = msg.remoteConfigureCode1 & AtvFeature.supportedByClient;
        _send(buildRemoteConfigureMessage(_negotiatedFeatures));
        break;
      case RemoteServerMessageKind.setActive:
        _send(buildRemoteSetActiveMessage(_negotiatedFeatures));
        break;
      case RemoteServerMessageKind.pingRequest:
        _send(buildPingResponseMessage(msg.pingVal1));
        break;
      case RemoteServerMessageKind.start:
        _powerStateController.add(msg.started);
        break;
      case RemoteServerMessageKind.error:
        _errorController.add('La TV reportó un error de protocolo.');
        break;
      case RemoteServerMessageKind.volumeLevel:
      case RemoteServerMessageKind.unknown:
        break;
    }
  }

  void _handleDisconnect(String reason) {
    if (_stateController.isClosed) return;
    _stateController.add(AtvConnectionState.disconnected);
    _errorController.add(reason);
  }
}
