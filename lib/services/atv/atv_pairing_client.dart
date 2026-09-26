// Drives the pairing handshake with an Android TV on port 6467. This is
// only needed the first time Remotix talks to a given TV: after
// [finishPairing] succeeds, the TV remembers this app's certificate and
// AtvRemoteClient can connect straight to the control port from then on.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'atv_identity.dart';
import 'framed_message_reassembler.dart';
import 'pairing_messages.dart';
import 'pairing_secret.dart';
import 'proto_codec.dart';

const int atvPairingPort = 6467;

class AtvPairingException implements Exception {
  final String message;
  const AtvPairingException(this.message);
  @override
  String toString() => message;
}

class AtvPairingClient {
  final String host;
  final AtvIdentity identity;

  SecureSocket? _socket;
  StreamSubscription<Uint8List>? _subscription;
  final _reassembler = FramedMessageReassembler();
  Completer<void>? _pendingStep;

  AtvPairingClient({required this.host, required this.identity});

  /// Connects and negotiates up to the point where the TV is showing a PIN
  /// on screen. Throws [AtvPairingException] on any protocol-level failure.
  Future<void> startPairing({String clientName = 'Remotix'}) async {
    final context = SecurityContext(withTrustedRoots: false)
      ..useCertificateChainBytes(utf8.encode(identity.certificatePem))
      ..usePrivateKeyBytes(utf8.encode(identity.privateKeyPem));

    try {
      _socket = await SecureSocket.connect(
        host,
        atvPairingPort,
        context: context,
        onBadCertificate: (cert) => true, // trust is anchored by the PIN check in finishPairing, not the CA chain
        timeout: const Duration(seconds: 10),
      );
    } on Object catch (e) {
      throw AtvPairingException('No se pudo conectar a $host:$atvPairingPort: $e');
    }

    _subscription = _socket!.listen(_onData, onError: _onSocketError, onDone: () => _fail('La TV cerró la conexión.'));

    _pendingStep = Completer<void>();
    _send(buildPairingRequestMessage(clientName: clientName));
    await _pendingStep!.future;
  }

  /// Completes pairing using the 6-hex-digit code shown on the TV.
  Future<void> finishPairing(String pairingCode) async {
    final socket = _socket;
    if (socket == null) {
      throw const AtvPairingException('El emparejamiento no ha comenzado.');
    }

    final peerCertDer = socket.peerCertificate?.der;
    if (peerCertDer == null) {
      throw const AtvPairingException('No se pudo leer el certificado TLS de la TV.');
    }

    final serverPublicKey = rsaPublicKeyFromCertificateDer(Uint8List.fromList(peerCertDer));
    final secret = computePairingSecret(
      clientPublicKey: identity.publicKey,
      serverPublicKey: serverPublicKey,
      pairingCode: pairingCode,
    );

    _pendingStep = Completer<void>();
    _send(buildSecretMessage(secret));
    await _pendingStep!.future;
  }

  Future<void> dispose() async {
    await _subscription?.cancel();
    await _socket?.close();
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
    final PoloServerMessage msg;
    try {
      msg = parsePoloServerMessage(raw);
    } on Object catch (e) {
      _fail('Mensaje de emparejamiento inválido: $e');
      return;
    }

    if (msg.status != 200) {
      _fail('La TV rechazó el emparejamiento (código ${msg.status}).');
      return;
    }

    switch (msg.kind) {
      case PoloServerMessageKind.pairingRequestAck:
        _send(buildOptionsMessage());
        break;
      case PoloServerMessageKind.options:
        _send(buildConfigurationMessage());
        break;
      case PoloServerMessageKind.configurationAck:
      case PoloServerMessageKind.secretAck:
        _completeStep();
        break;
      case PoloServerMessageKind.unknown:
        _fail('Respuesta inesperada de la TV durante el emparejamiento.');
        break;
    }
  }

  void _completeStep() {
    final step = _pendingStep;
    if (step != null && !step.isCompleted) step.complete();
  }

  void _fail(String message) {
    final error = AtvPairingException(message);
    final step = _pendingStep;
    if (step != null && !step.isCompleted) step.completeError(error);
  }

  void _onSocketError(Object error, StackTrace stackTrace) {
    _fail('Error de conexión: $error');
  }
}
