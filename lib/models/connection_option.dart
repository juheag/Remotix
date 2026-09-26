import 'package:flutter/material.dart';

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
