// Real BLE scanning for nearby devices. There is no universal Bluetooth
// remote-control protocol that works across TV brands the way the Android
// TV Remote v2 protocol does over Wi-Fi (each vendor uses its own GATT
// profile), so this screen currently scans and lists devices rather than
// controlling one - that would need a per-brand integration.
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

class BluetoothScreen extends StatefulWidget {
  const BluetoothScreen({super.key});

  @override
  State<BluetoothScreen> createState() => _BluetoothScreenState();
}

class _BluetoothScreenState extends State<BluetoothScreen> {
  StreamSubscription<List<ScanResult>>? _scanSubscription;
  List<ScanResult> _results = [];
  bool _scanning = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _startScan();
  }

  @override
  void dispose() {
    _scanSubscription?.cancel();
    FlutterBluePlus.stopScan();
    super.dispose();
  }

  Future<void> _startScan() async {
    setState(() {
      _error = null;
      _results = [];
    });

    if (Platform.isAndroid) {
      final statuses = await [
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
        Permission.locationWhenInUse,
      ].request();
      final denied = statuses.values.any((s) => s.isDenied || s.isPermanentlyDenied);
      if (denied) {
        setState(() => _error = 'Se necesitan permisos de Bluetooth/ubicación para buscar dispositivos.');
        return;
      }
    }

    final supported = await FlutterBluePlus.isSupported;
    if (!supported) {
      setState(() => _error = 'Este dispositivo no tiene soporte Bluetooth LE.');
      return;
    }

    _scanSubscription = FlutterBluePlus.scanResults.listen((results) {
      if (!mounted) return;
      setState(() => _results = results);
    });

    setState(() => _scanning = true);
    try {
      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 10));
    } on Object catch (e) {
      setState(() => _error = 'No se pudo iniciar el escaneo: $e');
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Dispositivos Bluetooth'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _scanning ? null : _startScan,
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Dispositivos BLE cercanos',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              const Text(
                'El control por Bluetooth aún no envía comandos: cada TV usa su propio '
                'protocolo. Por ahora esta pantalla solo descubre dispositivos cercanos.',
                style: TextStyle(fontSize: 13, color: Colors.grey),
              ),
              const SizedBox(height: 20),
              if (_scanning) const LinearProgressIndicator(),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(_error!, style: const TextStyle(color: Colors.redAccent)),
                ),
              Expanded(
                child: _results.isEmpty && !_scanning
                    ? const Center(child: Text('No se encontraron dispositivos.', style: TextStyle(color: Colors.grey)))
                    : ListView.separated(
                        itemCount: _results.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final result = _results[index];
                          final name = result.advertisementData.advName.isNotEmpty
                              ? result.advertisementData.advName
                              : (result.device.platformName.isNotEmpty ? result.device.platformName : 'Dispositivo desconocido');
                          return Card(
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            child: ListTile(
                              leading: const CircleAvatar(
                                backgroundColor: Colors.white10,
                                child: Icon(Icons.bluetooth, color: Colors.white),
                              ),
                              title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
                              subtitle: Text('${result.device.remoteId.str} • RSSI ${result.rssi} dBm'),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
