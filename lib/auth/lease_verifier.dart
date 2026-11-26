import 'dart:convert';
import 'dart:typed_data';
import 'package:pointycastle/export.dart';

class LeaseVerifier {
  static Uint8List decode(String value) =>
      base64Url.decode(base64Url.normalize(value));
  static BigInt integer(Uint8List bytes) =>
      bytes.fold(BigInt.zero, (n, b) => (n << 8) | BigInt.from(b));

  // Returns signed lifetime in seconds, never a device-clock deadline.
  static int? verify(String token, String user, String device) {
    try {
      if (token.length > 8192) return null;
      final parts = token.split('.');
      if (parts.length != 3) return null;
      final header = jsonDecode(utf8.decode(decode(parts[0])));
      if (header['alg'] != 'ES256' || header['kid'] != 'markys-v1') return null;
      final domain = ECDomainParameters('prime256v1');
      final x = integer(decode('OBMZ6RgWt_1mxiUycxNFezCOqZpi2ztMoyWJtJt4xlI'));
      final y = integer(decode('PcdmOuPoGLjlDNzOlW31Xyqsf3uHb7XP1Sh_dLLI2o0'));
      final key = ECPublicKey(domain.curve.createPoint(x, y), domain);
      final sig = decode(parts[2]);
      if (sig.length != 64) return null;
      final verifier = ECDSASigner(SHA256Digest())
        ..init(false, PublicKeyParameter<ECPublicKey>(key));
      if (!verifier.verifySignature(Uint8List.fromList(utf8.encode('${parts[0]}.${parts[1]}')),
          ECSignature(integer(sig.sublist(0, 32)), integer(sig.sublist(32))))) return null;
      final p = jsonDecode(utf8.decode(decode(parts[1])));
      if (p['iss'] != 'markys-licencas' || p['aud'] != 'markys-pdv-mobile' ||
          p['sub'] != user || p['device_id'] != device) return null;
      final iat = p['iat'], exp = p['exp'];
      if (iat is! int || exp is! int || exp <= iat || exp - iat > 86400) return null;
      return exp - iat;
    } catch (_) { return null; }
  }
}
