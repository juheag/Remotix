import 'package:flutter/material.dart';

import '../models/discovered_device.dart';
import '../services/atv/atv_key_code.dart';
import '../services/atv/atv_remote_client.dart';

class RemoteControlScreen extends StatefulWidget {
  final DiscoveredDevice device;
  final AtvRemoteClient client;

  const RemoteControlScreen({super.key, required this.device, required this.client});

  @override
  State<RemoteControlScreen> createState() => _RemoteControlScreenState();
}

class _RemoteControlScreenState extends State<RemoteControlScreen> {
  bool _connected = true;
  bool? _isTvOn;
  String? _lastError;

  @override
  void initState() {
    super.initState();
    widget.client.connectionState.listen((state) {
      if (!mounted) return;
      setState(() => _connected = state == AtvConnectionState.connected);
    });
    widget.client.isTvOn.listen((on) {
      if (!mounted) return;
      setState(() => _isTvOn = on);
    });
    widget.client.errors.listen((message) {
      if (!mounted) return;
      setState(() => _lastError = message);
    });
  }

  @override
  void dispose() {
    widget.client.dispose();
    super.dispose();
  }

  void _send(AtvKeyCode key) {
    if (!_connected) return;
    widget.client.sendKey(key);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.device.name),
        centerTitle: true,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16.0),
            child: Center(
              child: Icon(
                _connected ? Icons.wifi : Icons.wifi_off,
                color: _connected ? Colors.greenAccent : Colors.redAccent,
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            children: [
              if (!_connected)
                const Padding(
                  padding: EdgeInsets.only(bottom: 12),
                  child: Text('Conexión perdida con la TV.', style: TextStyle(color: Colors.redAccent)),
                ),
              if (_lastError != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(_lastError!, style: const TextStyle(color: Colors.orangeAccent), textAlign: TextAlign.center),
                ),
              _powerRow(),
              const SizedBox(height: 24),
              Expanded(child: Center(child: _dPad())),
              const SizedBox(height: 24),
              _bottomRow(),
              const SizedBox(height: 16),
              _volumeRow(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _powerRow() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          _isTvOn == null ? 'Estado desconocido' : (_isTvOn! ? 'TV encendida' : 'TV apagada'),
          style: const TextStyle(color: Colors.grey),
        ),
        IconButton.filledTonal(
          iconSize: 32,
          icon: const Icon(Icons.power_settings_new),
          color: Colors.redAccent,
          onPressed: () => _send(AtvKeyCode.power),
        ),
      ],
    );
  }

  Widget _dPad() {
    Widget arrow(IconData icon, AtvKeyCode key) => IconButton.filledTonal(
          iconSize: 32,
          icon: Icon(icon),
          onPressed: () => _send(key),
        );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        arrow(Icons.keyboard_arrow_up, AtvKeyCode.dpadUp),
        const SizedBox(height: 8),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            arrow(Icons.keyboard_arrow_left, AtvKeyCode.dpadLeft),
            const SizedBox(width: 8),
            FilledButton(
              style: FilledButton.styleFrom(shape: const CircleBorder(), padding: const EdgeInsets.all(24)),
              onPressed: () => _send(AtvKeyCode.dpadCenter),
              child: const Text('OK'),
            ),
            const SizedBox(width: 8),
            arrow(Icons.keyboard_arrow_right, AtvKeyCode.dpadRight),
          ],
        ),
        const SizedBox(height: 8),
        arrow(Icons.keyboard_arrow_down, AtvKeyCode.dpadDown),
      ],
    );
  }

  Widget _bottomRow() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        IconButton.filledTonal(icon: const Icon(Icons.arrow_back), onPressed: () => _send(AtvKeyCode.back)),
        IconButton.filledTonal(icon: const Icon(Icons.home), onPressed: () => _send(AtvKeyCode.home)),
        IconButton.filledTonal(icon: const Icon(Icons.menu), onPressed: () => _send(AtvKeyCode.menu)),
      ],
    );
  }

  Widget _volumeRow() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton.filledTonal(icon: const Icon(Icons.volume_down), onPressed: () => _send(AtvKeyCode.volumeDown)),
        const SizedBox(width: 16),
        IconButton.filledTonal(icon: const Icon(Icons.volume_off), onPressed: () => _send(AtvKeyCode.volumeMute)),
        const SizedBox(width: 16),
        IconButton.filledTonal(icon: const Icon(Icons.volume_up), onPressed: () => _send(AtvKeyCode.volumeUp)),
      ],
    );
  }
}
