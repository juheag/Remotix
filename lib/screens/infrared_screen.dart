import 'package:flutter/material.dart';

import '../services/infrared/infrared_service.dart';

// A generic 38 kHz test burst (not tied to any TV brand) used only to prove
// the phone's IR emitter physically fires - point the phone at another
// phone's camera (IR is visible to camera sensors) to see it flash.
const int _testFrequencyHz = 38000;
final List<int> _testPattern = [600, 550, 600, 16500];

class InfraredScreen extends StatefulWidget {
  const InfraredScreen({super.key});

  @override
  State<InfraredScreen> createState() => _InfraredScreenState();
}

class _InfraredScreenState extends State<InfraredScreen> {
  bool? _hasEmitter;
  String? _error;

  @override
  void initState() {
    super.initState();
    _checkEmitter();
  }

  Future<void> _checkEmitter() async {
    final has = await InfraredService.hasEmitter();
    if (!mounted) return;
    setState(() => _hasEmitter = has);
  }

  Future<void> _sendTestPulse() async {
    setState(() => _error = null);
    try {
      await InfraredService.transmit(frequencyHz: _testFrequencyHz, pattern: _testPattern);
    } on Object catch (e) {
      setState(() => _error = 'No se pudo transmitir: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Infrarrojos'), centerTitle: true),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Emisor infrarrojo', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              if (_hasEmitter == null)
                const Center(child: CircularProgressIndicator())
              else if (!_hasEmitter!)
                const Text(
                  'Este teléfono no tiene un emisor infrarrojo integrado. '
                  'La mayoría de los teléfonos modernos ya no incluyen uno.',
                  style: TextStyle(color: Colors.orangeAccent),
                )
              else ...[
                const Text(
                  'Se detectó un emisor infrarrojo en este dispositivo. '
                  'Los códigos específicos por marca de TV aún no están implementados; '
                  'este botón solo confirma que el hardware puede transmitir.',
                  style: TextStyle(color: Colors.grey),
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: _sendTestPulse,
                  icon: const Icon(Icons.settings_remote),
                  label: const Text('Enviar pulso de prueba'),
                ),
              ],
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(_error!, style: const TextStyle(color: Colors.redAccent)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
