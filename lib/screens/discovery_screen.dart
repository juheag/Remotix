import 'dart:async';

import 'package:bonsoir/bonsoir.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/discovered_device.dart';
import 'device_connect_screen.dart';

// The Android TV Remote v2 service (pairing + key injection) advertises
// itself under this mDNS type, separate from generic Chromecast/media
// receivers under `_googlecast._tcp`.
const String _androidTvRemoteServiceType = '_androidtvremote2._tcp';

class DeviceDiscoveryNotifier extends AsyncNotifier<List<DiscoveredDevice>> {
  BonsoirDiscovery? _discovery;
  StreamSubscription<BonsoirDiscoveryEvent>? _subscription;
  final List<DiscoveredDevice> _devices = [];

  @override
  Future<List<DiscoveredDevice>> build() async {
    ref.onDispose(_stopScanning);
    return _startRealScan();
  }

  Future<List<DiscoveredDevice>> _startRealScan() async {
    _devices.clear();

    _discovery = BonsoirDiscovery(type: _androidTvRemoteServiceType);
    await _discovery!.initialize();

    final stream = _discovery!.eventStream;
    if (stream != null) {
      _subscription = stream.listen((event) {
        if (event is BonsoirDiscoveryServiceFoundEvent) {
          event.service.resolve(_discovery!.serviceResolver);
        } else if (event is BonsoirDiscoveryServiceResolvedEvent) {
          final service = event.service;
          final friendlyName = service.name;
          final host = service.hostAddress;
          if (host == null || host.isEmpty) return;

          final exists = _devices.any((d) => d.name == friendlyName);
          if (!exists) {
            _devices.add(
              DiscoveredDevice(
                id: service.name,
                name: friendlyName,
                ipAddress: host,
                brand: 'Google TV / Android TV',
              ),
            );
            state = AsyncValue.data(List.from(_devices));
          }
        }
      });
    }

    await _discovery!.start();

    await Future.delayed(const Duration(seconds: 4));
    return List.from(_devices);
  }

  Future<void> _stopScanning() async {
    await _subscription?.cancel();
    _subscription = null;
    await _discovery?.stop();
    _discovery = null;
  }

  Future<void> refresh() async {
    await _stopScanning();
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() => _startRealScan());
  }
}

final deviceDiscoveryProvider = AsyncNotifierProvider<DeviceDiscoveryNotifier, List<DiscoveredDevice>>(
  () => DeviceDiscoveryNotifier(),
);

Future<void> _showManualIpDialog(BuildContext context) async {
  final controller = TextEditingController();
  final ip = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Conectar por IP'),
      content: TextField(
        controller: controller,
        autofocus: true,
        keyboardType: TextInputType.numberWithOptions(decimal: true),
        decoration: const InputDecoration(hintText: '192.168.1.50', border: OutlineInputBorder()),
        onSubmitted: (value) => Navigator.of(ctx).pop(value.trim()),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancelar')),
        FilledButton(onPressed: () => Navigator.of(ctx).pop(controller.text.trim()), child: const Text('Conectar')),
      ],
    ),
  );

  if (ip == null || ip.isEmpty || !context.mounted) return;

  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => DeviceConnectScreen(
        device: DiscoveredDevice(id: 'manual-$ip', name: 'TV ($ip)', ipAddress: ip, brand: 'IP manual'),
      ),
    ),
  );
}

class DiscoveryScreen extends ConsumerWidget {
  const DiscoveryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final discoveryState = ref.watch(deviceDiscoveryProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Buscando dispositivos'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.read(deviceDiscoveryProvider.notifier).refresh(),
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
                'Dispositivos en la red local',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              const Text(
                'Tu Google TV / Android TV debe estar encendido y en la misma red Wi-Fi.',
                style: TextStyle(fontSize: 13, color: Colors.grey),
              ),
              const SizedBox(height: 20),
              Expanded(
                child: discoveryState.when(
                  loading: () => const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 16),
                        Text(
                          'Buscando Google TV en la red...',
                          style: TextStyle(color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                  error: (err, _) => Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.error_outline, size: 48, color: Colors.redAccent),
                        const SizedBox(height: 12),
                        Text('Error al escanear: $err'),
                        const SizedBox(height: 12),
                        ElevatedButton(
                          onPressed: () => ref.read(deviceDiscoveryProvider.notifier).refresh(),
                          child: const Text('Reintentar'),
                        ),
                      ],
                    ),
                  ),
                  data: (devices) {
                    if (devices.isEmpty) {
                      return Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.tv_off, size: 48, color: Colors.grey),
                            const SizedBox(height: 16),
                            const Text(
                              'No se encontró ningún Google TV.',
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(height: 8),
                            const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 32.0),
                              child: Text(
                                'Verifica que la TV esté encendida y que el móvil no esté en datos móviles ni en red de invitados.',
                                textAlign: TextAlign.center,
                                style: TextStyle(fontSize: 13, color: Colors.grey),
                              ),
                            ),
                            const SizedBox(height: 16),
                            ElevatedButton.icon(
                              onPressed: () => ref.read(deviceDiscoveryProvider.notifier).refresh(),
                              icon: const Icon(Icons.refresh),
                              label: const Text('Buscar de nuevo'),
                            ),
                          ],
                        ),
                      );
                    }

                    return ListView.separated(
                      itemCount: devices.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final device = devices[index];
                        return Card(
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          child: ListTile(
                            leading: const CircleAvatar(
                              backgroundColor: Colors.white10,
                              child: Icon(Icons.tv, color: Colors.white),
                            ),
                            title: Text(device.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                            subtitle: Text('${device.brand} • ${device.ipAddress}'),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(builder: (_) => DeviceConnectScreen(device: device)),
                              );
                            },
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => _showManualIpDialog(context),
                icon: const Icon(Icons.edit),
                label: const Text('Conectar por IP manual'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
