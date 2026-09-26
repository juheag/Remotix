// Subset of RemoteKeyCode from remotemessage.proto (Android TV Remote
// protocol v2). Values are the exact enum numbers Google TV expects on the
// wire - see https://github.com/tronikos/androidtvremote2.
enum AtvKeyCode {
  home(3),
  back(4),
  dpadUp(19),
  dpadDown(20),
  dpadLeft(21),
  dpadRight(22),
  dpadCenter(23),
  volumeUp(24),
  volumeDown(25),
  power(26),
  enter(66),
  menu(82),
  search(84),
  mediaPlayPause(85),
  volumeMute(164),
  settings(176);

  final int wireValue;
  const AtvKeyCode(this.wireValue);
}

/// RemoteDirection from remotemessage.proto.
enum AtvKeyDirection {
  shortPress(3),
  startLong(1),
  endLong(2);

  final int wireValue;
  const AtvKeyDirection(this.wireValue);
}

/// Feature bitmask from RemoteConfigure.code1 (see remote.py `Feature`).
class AtvFeature {
  static const int ping = 1 << 0;
  static const int key = 1 << 1;
  static const int ime = 1 << 2;
  static const int voice = 1 << 3;
  static const int power = 1 << 5;
  static const int volume = 1 << 6;
  static const int appLink = 1 << 9;

  static const int supportedByClient = ping | key | power | volume | appLink;
}
