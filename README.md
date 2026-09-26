# Remotix

Control remoto universal hecho en Flutter: convierte el teléfono en un mando
para tu TV, empezando por Google TV / Android TV (Kalley y similares) por
Wi-Fi, con Bluetooth e Infrarrojos como modos adicionales.

## Estado del proyecto

| Modo | Estado |
|---|---|
| Wi-Fi (Android TV Remote v2) | Funcional: descubrimiento por mDNS, emparejamiento por PIN y envío real de teclas (power, volumen, D-pad, home, back, menú). **No probado contra hardware real** - ver advertencia abajo. |
| Bluetooth | Descubre dispositivos BLE cercanos. No envía comandos todavía: cada fabricante usa su propio perfil GATT, así que el control real requeriría integraciones por marca. |
| Infrarrojos | Detecta si el teléfono tiene emisor IR (`ConsumerIrManager`, solo Android) y puede transmitir patrones crudos. No incluye una base de códigos por marca todavía. |

### ⚠️ Advertencia sobre el modo Wi-Fi

La implementación del protocolo Android TV Remote v2 (emparejamiento TLS
mutuo + protobuf hecho a mano, sin `protoc`) se escribió a partir de la
especificación pública y de una implementación de referencia en Python
(https://github.com/tronikos/androidtvremote2), pero **no se pudo compilar
ni probar contra un televisor real** en el entorno donde se desarrolló (sin
Flutter SDK ni hardware disponibles). Antes de confiar en ella:

1. Corre `flutter pub get` y `flutter analyze` para atrapar errores de compilación.
2. Prueba el emparejamiento contra un Google TV/Android TV real en la misma red Wi-Fi.
3. Si algo falla, la lógica del protocolo vive en `lib/services/atv/` - especialmente
   `pairing_secret.dart` (cálculo del secreto SHA-256) y los archivos `*_client.dart`
   (los sockets TLS).

## Cómo funciona el modo Wi-Fi

1. **Descubrimiento** (`lib/screens/discovery_screen.dart`): busca el servicio
   mDNS `_androidtvremote2._tcp` en la red local.
2. **Emparejamiento** (`lib/services/atv/atv_pairing_client.dart`, puerto 6467):
   la app genera un certificado TLS autofirmado propio (una sola vez, se
   guarda en disco), se conecta a la TV, y la TV muestra un código de 6
   dígitos en pantalla. La app calcula un hash SHA-256 a partir de ese
   código y las claves públicas de ambos certificados; si coincide, la TV
   recuerda el certificado del teléfono para siempre.
3. **Control** (`lib/services/atv/atv_remote_client.dart`, puerto 6466): con
   el certificado ya confiado, se abre una conexión persistente que
   responde el *keep-alive* de la TV y envía las teclas que el usuario toca.

## Estructura

```
lib/
  models/            # ConnectionOption, DiscoveredDevice
  services/
    atv/             # Protocolo Android TV Remote v2 (pairing + control)
    infrared/        # Wrapper del canal nativo de IR
  screens/           # UI: selección de modo, descubrimiento, pairing, control
android/.../MainActivity.kt   # Canal de método nativo para ConsumerIrManager
```

## Desarrollo

```bash
flutter pub get
flutter analyze
flutter test
flutter run
```

Requiere un teléfono Android para IR y Bluetooth real (IR no existe en iOS).
El modo Wi-Fi debería funcionar también en iOS, aunque no se ha probado ahí.
