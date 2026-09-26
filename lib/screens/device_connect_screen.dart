// Bridges DiscoveryScreen and RemoteControlScreen: makes sure the TV
// trusts this app's certificate (pairing with a PIN if it doesn't yet),
// then opens the real control connection.
import 'package:flutter/material.dart';

import '../models/discovered_device.dart';
import '../services/atv/atv_identity.dart';
import '../services/atv/atv_pairing_client.dart';
import '../services/atv/atv_remote_client.dart';
import 'remote_control_screen.dart';

enum _ConnectPhase { connecting, waitingForPin, error }

class DeviceConnectScreen extends StatefulWidget {
  final DiscoveredDevice device;

  const DeviceConnectScreen({super.key, required this.device});

  @override
  State<DeviceConnectScreen> createState() => _DeviceConnectScreenState();
}

class _DeviceConnectScreenState extends State<DeviceConnectScreen> {
  _ConnectPhase _phase = _ConnectPhase.connecting;
  String? _errorMessage;
  AtvPairingClient? _pairingClient;
  final _pinController = TextEditingController();
  bool _submittingPin = false;

  @override
  void initState() {
    super.initState();
    _attemptConnect();
  }

  @override
  void dispose() {
    _pairingClient?.dispose();
    _pinController.dispose();
    super.dispose();
  }

  Future<void> _attemptConnect() async {
    setState(() {
      _phase = _ConnectPhase.connecting;
      _errorMessage = null;
    });

    try {
      final identity = await AtvIdentity.loadOrCreate();
      final client = AtvRemoteClient(host: widget.device.ipAddress, identity: identity);
      await client.connect();
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => RemoteControlScreen(device: widget.device, client: client),
        ),
      );
    } on Object {
      // The TV likely doesn't trust our certificate yet - try pairing.
      await _startPairing();
    }
  }

  Future<void> _startPairing() async {
    try {
      final identity = await AtvIdentity.loadOrCreate();
      final pairingClient = AtvPairingClient(host: widget.device.ipAddress, identity: identity);
      await pairingClient.startPairing();
      if (!mounted) return;
      setState(() {
        _pairingClient = pairingClient;
        _phase = _ConnectPhase.waitingForPin;
      });
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = _ConnectPhase.error;
        _errorMessage = e.toString();
      });
    }
  }

  Future<void> _submitPin() async {
    final client = _pairingClient;
    if (client == null || _pinController.text.trim().length != 6) return;

    setState(() => _submittingPin = true);
    try {
      await client.finishPairing(_pinController.text.trim());
      await client.dispose();
      _pairingClient = null;
      if (!mounted) return;
      await _attemptConnect();
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _submittingPin = false;
        _errorMessage = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.device.name), centerTitle: true),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Center(child: _buildBody()),
        ),
      ),
    );
  }

  Widget _buildBody() {
    switch (_phase) {
      case _ConnectPhase.connecting:
        return const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Conectando con la TV...'),
          ],
        );
      case _ConnectPhase.waitingForPin:
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(Icons.pin, size: 48, color: Colors.deepPurpleAccent),
            const SizedBox(height: 16),
            const Text(
              'Ingresa el código de 6 caracteres que aparece en tu TV',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _pinController,
              textAlign: TextAlign.center,
              maxLength: 6,
              textCapitalization: TextCapitalization.characters,
              style: const TextStyle(fontSize: 24, letterSpacing: 8),
              decoration: const InputDecoration(counterText: '', border: OutlineInputBorder()),
              onSubmitted: (_) => _submitPin(),
            ),
            if (_errorMessage != null) ...[
              const SizedBox(height: 8),
              Text(_errorMessage!, style: const TextStyle(color: Colors.redAccent), textAlign: TextAlign.center),
            ],
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _submittingPin ? null : _submitPin,
              child: _submittingPin
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Emparejar'),
            ),
          ],
        );
      case _ConnectPhase.error:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.redAccent),
            const SizedBox(height: 12),
            Text(_errorMessage ?? 'No se pudo conectar.', textAlign: TextAlign.center),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: _attemptConnect, child: const Text('Reintentar')),
          ],
        );
    }
  }
}
