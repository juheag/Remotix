// Computes and validates the pairing secret shown as a 6-hex-digit PIN on
// the TV screen. This ties the TLS session to a value a human actually saw
// on the device, which is what makes trusting a self-signed certificate
// safe here (classic TOFU, anchored by an out-of-band code).
//
// Algorithm ported from the reference implementation at
// https://github.com/tronikos/androidtvremote2 (pairing.py), which in turn
// documents it as coming from Google's own google-tv-pairing-protocol.
import 'dart:convert';
import 'dart:typed_data';

import 'package:basic_utils/basic_utils.dart';
import 'package:crypto/crypto.dart';
import 'package:pointycastle/asymmetric/api.dart';

class PairingSecretMismatch implements Exception {
  final String message;
  const PairingSecretMismatch(this.message);
  @override
  String toString() => message;
}

Uint8List _hexToBytes(String hex) {
  final normalized = hex.length.isOdd ? '0$hex' : hex;
  final bytes = Uint8List(normalized.length ~/ 2);
  for (var i = 0; i < bytes.length; i++) {
    bytes[i] = int.parse(normalized.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return bytes;
}

String _derCertificateToPem(Uint8List der) {
  final base64Str = base64.encode(der);
  final chunks = <String>[];
  for (var i = 0; i < base64Str.length; i += 64) {
    final end = i + 64 > base64Str.length ? base64Str.length : i + 64;
    chunks.add(base64Str.substring(i, end));
  }
  return '-----BEGIN CERTIFICATE-----\n${chunks.join('\n')}\n-----END CERTIFICATE-----\n';
}

/// Extracts the RSA public key (modulus + exponent) from a peer certificate
/// as handed back by `SecureSocket.peerCertificate.der`.
RSAPublicKey rsaPublicKeyFromCertificateDer(Uint8List der) {
  final pem = _derCertificateToPem(der);
  final modulus = X509Utils.getModulusFromRSAX509Pem(pem);
  final certData = X509Utils.x509CertificateFromPem(pem);
  final exponent = certData.publicKeyData.exponent;
  if (exponent == null) {
    throw const PairingSecretMismatch('El certificado de la TV no es RSA; no se puede emparejar.');
  }
  return RSAPublicKey(modulus, BigInt.from(exponent));
}

/// Computes the SHA-256 secret to send back to the TV, and validates that
/// the entered [pairingCode] actually matches what the TV displayed (its
/// first byte is a checksum baked into the code itself).
Uint8List computePairingSecret({
  required RSAPublicKey clientPublicKey,
  required RSAPublicKey serverPublicKey,
  required String pairingCode,
}) {
  final code = pairingCode.trim().toUpperCase();
  if (code.length != 6 || int.tryParse(code, radix: 16) == null) {
    throw const PairingSecretMismatch('El código debe tener exactamente 6 caracteres hexadecimales.');
  }

  final clientModHex = clientPublicKey.modulus.toRadixString(16);
  final clientExpHex = '0${clientPublicKey.exponent.toRadixString(16)}';
  final serverModHex = serverPublicKey.modulus.toRadixString(16);
  final serverExpHex = '0${serverPublicKey.exponent.toRadixString(16)}';
  final codeTail = code.substring(2);

  final input = BytesBuilder()
    ..add(_hexToBytes(clientModHex))
    ..add(_hexToBytes(clientExpHex))
    ..add(_hexToBytes(serverModHex))
    ..add(_hexToBytes(serverExpHex))
    ..add(_hexToBytes(codeTail));

  final digest = sha256.convert(input.toBytes()).bytes;
  final expectedFirstByte = int.parse(code.substring(0, 2), radix: 16);
  if (digest[0] != expectedFirstByte) {
    throw const PairingSecretMismatch('El código ingresado no coincide con esta TV. Verifica e inténtalo de nuevo.');
  }
  return Uint8List.fromList(digest);
}
