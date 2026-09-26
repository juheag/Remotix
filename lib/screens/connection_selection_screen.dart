import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/connection_option.dart';
import 'bluetooth_screen.dart';
import 'discovery_screen.dart';
import 'infrared_screen.dart';

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
      description: 'Busca dispositivos Bluetooth cercanos compatibles con BLE.',
      icon: Icons.bluetooth,
      isAvailable: true,
    ),
    ConnectionOption(
      type: ConnectionType.infrared,
      title: 'Infrarrojos (IR)',
      description: isInfraredAvailable
          ? 'Control tradicional para televisores y aires acondicionados. Requiere emisor IR en el teléfono.'
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

final selectedConnectionProvider = NotifierProvider<SelectedConnectionNotifier, ConnectionType?>(
  () => SelectedConnectionNotifier(),
);

class ConnectionSelectionScreen extends ConsumerWidget {
  const ConnectionSelectionScreen({super.key});

  Future<void> _handleContinue(BuildContext context, ConnectionType type) async {
    switch (type) {
      case ConnectionType.wifi:
        final connectivityResult = await Connectivity().checkConnectivity();
        final hasWifi = connectivityResult.contains(ConnectivityResult.wifi);

        if (!hasWifi && context.mounted) {
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Wi-Fi Desconectado'),
              content: const Text(
                'Tu teléfono no está conectado a ninguna red Wi-Fi. '
                'Conéctate a la misma red que tu televisor para encontrarlo.',
              ),
              actions: [
                TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Aceptar')),
              ],
            ),
          );
          return;
        }

        if (context.mounted) {
          Navigator.of(context).push(MaterialPageRoute(builder: (_) => const DiscoveryScreen()));
        }
        break;
      case ConnectionType.bluetooth:
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => const BluetoothScreen()));
        break;
      case ConnectionType.infrared:
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => const InfraredScreen()));
        break;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final options = ref.watch(connectionOptionsProvider);
    final selectedType = ref.watch(selectedConnectionProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Remotix'), centerTitle: true),
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
                          color: isSelected ? Theme.of(context).colorScheme.primary : Colors.transparent,
                          width: 2,
                        ),
                      ),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        leading: CircleAvatar(
                          radius: 24,
                          backgroundColor: option.isAvailable
                              ? (isSelected ? Theme.of(context).colorScheme.primary : Colors.white10)
                              : Colors.red.withAlpha(40),
                          child: Icon(
                            option.icon,
                            color: option.isAvailable ? (isSelected ? Colors.white : Colors.white70) : Colors.redAccent,
                          ),
                        ),
                        title: Text(
                          option.title,
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: option.isAvailable ? Colors.white : Colors.white38,
                          ),
                        ),
                        subtitle: Text(
                          option.description,
                          style: TextStyle(fontSize: 12, color: option.isAvailable ? Colors.white70 : Colors.white30),
                        ),
                        trailing: option.isAvailable
                            ? (isSelected
                                ? const Icon(Icons.check_circle, color: Colors.deepPurpleAccent)
                                : const Icon(Icons.circle_outlined, color: Colors.grey))
                            : const Icon(Icons.block, color: Colors.redAccent),
                        onTap: () {
                          if (option.isAvailable) {
                            ref.read(selectedConnectionProvider.notifier).select(option.type);
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
                  onPressed: selectedType != null ? () => _handleContinue(context, selectedType) : null,
                  icon: const Icon(Icons.arrow_forward),
                  label: const Text('Continuar', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
