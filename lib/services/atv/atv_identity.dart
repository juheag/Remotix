// The Android TV Remote protocol authenticates the phone with a self-signed
// TLS client certificate: the TV shows a PIN once, the app proves it holds
// the private key behind that PIN via a SHA-256 challenge (see
// pairing_secret.dart), and from then on the TV trusts this exact
// certificate. So it must be generated once and reused forever - a new
// certificate on every launch would mean re-pairing every time.
import 'dart:io';

import 'package:basic_utils/basic_utils.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pointycastle/asymmetric/api.dart';

class AtvIdentity {
  final RSAPrivateKey privateKey;
  final RSAPublicKey publicKey;
  final String certificatePem;
  final String privateKeyPem;

  const AtvIdentity({
    required this.privateKey,
    required this.publicKey,
    required this.certificatePem,
    required this.privateKeyPem,
  });

  static Future<AtvIdentity> loadOrCreate() async {
    final dir = await getApplicationSupportDirectory();
    final certFile = File('${dir.path}/remotix_atv_client_cert.pem');
    final keyFile = File('${dir.path}/remotix_atv_client_key.pem');
    final pubKeyFile = File('${dir.path}/remotix_atv_client_pub.pem');

    if (await certFile.exists() && await keyFile.exists() && await pubKeyFile.exists()) {
      final certPem = await certFile.readAsString();
      final keyPem = await keyFile.readAsString();
      final pubPem = await pubKeyFile.readAsString();
      return AtvIdentity(
        privateKey: CryptoUtils.rsaPrivateKeyFromPem(keyPem),
        publicKey: CryptoUtils.rsaPublicKeyFromPem(pubPem),
        certificatePem: certPem,
        privateKeyPem: keyPem,
      );
    }

    final keyPair = CryptoUtils.generateRSAKeyPair(keySize: 2048);
    final privateKey = keyPair.privateKey as RSAPrivateKey;
    final publicKey = keyPair.publicKey as RSAPublicKey;

    final csrPem = X509Utils.generateRsaCsrPem({'CN': 'Remotix'}, privateKey, publicKey);
    final certPem = X509Utils.generateSelfSignedCertificate(privateKey, csrPem, 3650);
    final keyPem = CryptoUtils.encodeRSAPrivateKeyToPem(privateKey);
    final pubPem = CryptoUtils.encodeRSAPublicKeyToPem(publicKey);

    await certFile.writeAsString(certPem);
    await keyFile.writeAsString(keyPem);
    await pubKeyFile.writeAsString(pubPem);

    return AtvIdentity(
      privateKey: privateKey,
      publicKey: publicKey,
      certificatePem: certPem,
      privateKeyPem: keyPem,
    );
  }
}
