import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:bonsoir/bonsoir.dart';

enum ConnectionType { wifi, bluetooth, infrared }

class ConnectionOption {
  final ConnectionType type;
  final String title;
  final String description;
  final IconData icon;
  final bool isAvailable;

  const ConnectionOption({
    required this.type,
    required this.title,
    required this.description,
    required this.icon,
    required this.isAvailable,
  });
}

class DiscoveredDevice {
  final String id;
  final String name;
  final String ipAddress;
  final String brand;

  const DiscoveredDevice({
    required this.id,
    required this.name,
    required this.ipAddress,
    required this.brand,
  });
}

final connectionOptionsProvider = Provider<List<ConnectionOption>>((ref) {
  final isInfraredAvailable = !Platform.isIOS;

  return [
    const ConnectionOption(
      type: ConnectionType.wifi,
      title: 'Wi-Fi (Red Local)',
      description: 'Ideal para Smart TVs (Kalley, Google TV, LG, Samsung, Roku).',
      icon: Icons.wifi,
      isAvailable: true,
    ),
    const ConnectionOption(
      type: ConnectionType.bluetooth,
      title: 'Bluetooth',
      description: 'Conexión directa punto a punto para dispositivos compatibles con BLE.',
      icon: Icons.bluetooth,
      isAvailable: true,
    ),
    ConnectionOption(
      type: ConnectionType.infrared,
      title: 'Infrarrojos (IR)',
      description: isInfraredAvailable
          ? 'Control tradicional para televisores y aires acondicionados.'
          : 'No disponible nativamente en iPhone. Requiere accesorio externo.',
      icon: Icons.settings_remote,
      isAvailable: isInfraredAvailable,
    ),
  ];
});

class SelectedConnectionNotifier extends Notifier<ConnectionType?> {
  @override
  ConnectionType? build() => ConnectionType.wifi;

  void select(ConnectionType type) {
    state = type;
  }
}

final selectedConnectionProvider =
    NotifierProvider<SelectedConnectionNotifier, ConnectionType?>(
  () => SelectedConnectionNotifier(),
);

class DeviceDiscoveryNotifier extends AsyncNotifier<List<DiscoveredDevice>> {
  BonsoirDiscovery? _discovery;
  StreamSubscription<BonsoirDiscoveryEvent>? _subscription;
  final List<DiscoveredDevice> _devices = [];

  @override
  Future<List<DiscoveredDevice>> build() async {
    ref.onDispose(() {
      _stopScanning();
    });
    return _startRealScan();
  }

  Future<List<DiscoveredDevice>> _startRealScan() async {
    _devices.clear();

    const String type = '_googlecast._tcp';
    _discovery = BonsoirDiscovery(type: type);

    final stream = _discovery!.eventStream;
    if (stream != null) {
      _subscription = stream.listen((event) {
        if (event is BonsoirDiscoveryServiceFoundEvent) {
          event.service.resolve(_discovery!.serviceResolver);
        } else if (event is BonsoirDiscoveryServiceResolvedEvent) {
          final service = event.service;
          final friendlyName = service.name;
          final json = service.toJson();
          final host = (json['host'] ?? json['ip'] ?? json['address'] ?? 'Red local').toString();

          final exists = _devices.any((d) => d.name == friendlyName);
          if (!exists) {
            _devices.add(
              DiscoveredDevice(
                id: service.name,
                name: friendlyName,
                ipAddress: host,
                brand: 'Google TV / Kalley',
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

final deviceDiscoveryProvider =
    AsyncNotifierProvider<DeviceDiscoveryNotifier, List<DiscoveredDevice>>(
  () => DeviceDiscoveryNotifier(),
);

void main() {
  runApp(const MyApp());
}

class RemotixApp extends StatelessWidget {
  const RemotixApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Remotix',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepPurple,
          brightness: Brightness.dark,
        ),
      ),
      home: const ConnectionSelectionScreen(),
    );
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const ProviderScope(
      child: RemotixApp(),
    );
  }
}

class ConnectionSelectionScreen extends ConsumerWidget {
  const ConnectionSelectionScreen({super.key});

  Future<void> _handleContinue(BuildContext context, ConnectionType type) async {
    if (type == ConnectionType.wifi) {
      final connectivityResult = await Connectivity().checkConnectivity();
      final hasWifi = connectivityResult.contains(ConnectivityResult.wifi);

      if (!hasWifi && context.mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Wi-Fi Desconectado'),
            content: const Text(
              'Tu teléfono no está conectado a ninguna red Wi-Fi. '
              'Conéctate a la misma red que tu televisor Kalley para encontrarlo.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Aceptar'),
              ),
            ],
          ),
        );
        return;
      }

      if (context.mounted) {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const DiscoveryScreen()),
        );
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Modo ${type.name.toUpperCase()} en preparación.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final options = ref.watch(connectionOptionsProvider);
    final selectedType = ref.watch(selectedConnectionProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Remotix'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Selecciona el método de control',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'Elige cómo deseas enlazar Remotix con tu televisor.',
                style: TextStyle(fontSize: 14, color: Colors.grey),
              ),
              const SizedBox(height: 24),
              Expanded(
                child: ListView.separated(
                  itemCount: options.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final option = options[index];
                    final isSelected = selectedType == option.type;

                    return Card(
                      elevation: isSelected ? 4 : 1,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: BorderSide(
                          color: isSelected
                              ? Theme.of(context).colorScheme.primary
                              : Colors.transparent,
                          width: 2,
                        ),
                      ),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        leading: CircleAvatar(
                          radius: 24,
                          backgroundColor: option.isAvailable
                              ? (isSelected
                                  ? Theme.of(context).colorScheme.primary
                                  : Colors.white10)
                              : Colors.red.withAlpha(40),
                          child: Icon(
                            option.icon,
                            color: option.isAvailable
                                ? (isSelected ? Colors.white : Colors.white70)
                                : Colors.redAccent,
                          ),
                        ),
                        title: Text(
                          option.title,
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: option.isAvailable
                                ? Colors.white
                                : Colors.white38,
                          ),
                        ),
                        subtitle: Text(
                          option.description,
                          style: TextStyle(
                            fontSize: 12,
                            color: option.isAvailable
                                ? Colors.white70
                                : Colors.white30,
                          ),
                        ),
                        trailing: option.isAvailable
                            ? (isSelected
                                ? const Icon(Icons.check_circle,
                                    color: Colors.deepPurpleAccent)
                                : const Icon(Icons.circle_outlined,
                                    color: Colors.grey))
                            : const Icon(Icons.block, color: Colors.redAccent),
                        onTap: () {
                          if (option.isAvailable) {
                            ref
                                .read(selectedConnectionProvider.notifier)
                                .select(option.type);
                          }
                        },
                      ),
                    );
                  },
                ),
              ),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton.icon(
                  onPressed: selectedType != null
                      ? () => _handleContinue(context, selectedType)
                      : null,
                  icon: const Icon(Icons.arrow_forward),
                  label: const Text(
                    'Continuar',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
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
                'Tu televisor Kalley debe estar encendido y en la misma red Wi-Fi.',
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
                          onPressed: () =>
                              ref.read(deviceDiscoveryProvider.notifier).refresh(),
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
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final device = devices[index];
                        return Card(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: ListTile(
                            leading: const CircleAvatar(
                              backgroundColor: Colors.white10,
                              child: Icon(Icons.tv, color: Colors.white),
                            ),
                            title: Text(
                              device.name,
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            subtitle: Text('${device.brand} • ${device.ipAddress}'),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Conectando a ${device.name}...'),
                                ),
                              );
                            },
                          ),
                        );
                      },
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
