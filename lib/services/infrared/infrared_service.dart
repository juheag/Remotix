// Thin wrapper around Android's ConsumerIrManager (there is no iOS
// equivalent - no iPhone exposes a built-in IR blaster). Sending an actual
// TV command needs the exact carrier frequency and on/off pulse pattern for
// that brand's remote, which this file intentionally does not fabricate;
// callers supply real, verified patterns (e.g. from a NEC/vendor code
// database added later).
import 'package:flutter/services.dart';

class InfraredService {
  static const MethodChannel _channel = MethodChannel('remotix/infrared');

  static Future<bool> hasEmitter() async {
    try {
      return await _channel.invokeMethod<bool>('hasIrEmitter') ?? false;
    } on PlatformException {
      return false;
    }
  }

  /// [pattern] is a sequence of alternating on/off durations in
  /// microseconds, starting with "on" - the format Android's
  /// ConsumerIrManager.transmit expects.
  static Future<void> transmit({required int frequencyHz, required List<int> pattern}) async {
    await _channel.invokeMethod('transmit', {
      'frequency': frequencyHz,
      'pattern': pattern,
    });
  }
}
