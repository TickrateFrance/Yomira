import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart' as w;

/// Discord Rich Presence via the local Discord IPC pipe — pure Dart, no native
/// build. Windows uses the named pipe (\\.\pipe\discord-ipc-N) through win32
/// FFI; Linux/macOS use the Unix domain socket. Desktop only; every call is
/// guarded so a missing/closed Discord never affects the app.
class DiscordPresence {
  DiscordPresence(this._appId);

  final String _appId;
  bool _ready = false;
  DateTime _start = DateTime.now();

  /// Context key (what's being shown) so the elapsed timer resets when you
  /// switch chapter or go from reading to browsing, but NOT on every repeated
  /// browsing() call (those fire on each tab switch).
  String? _ctxKey;
  void _maybeResetTimer(String key) {
    if (key != _ctxKey) {
      _start = DateTime.now();
      _ctxKey = key;
    }
  }

  int _handle = -1; // Windows pipe handle (INVALID_HANDLE_VALUE = -1)
  Socket? _sock; // Unix socket (Linux/macOS)

  static bool get _supported =>
      Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  Future<void> init() async {
    if (!_supported || _appId.trim().isEmpty) return;
    try {
      if (Platform.isWindows) {
        _handle = _openWindowsPipe();
        if (_handle == w.INVALID_HANDLE_VALUE) return;
      } else {
        final path = _findUnixPipe();
        if (path == null) return;
        _sock = await Socket.connect(
          InternetAddress(path, type: InternetAddressType.unix),
          0,
        );
        _sock!.listen((_) {}, onError: (_) {}, cancelOnError: false);
      }
      _ready = true;
      _send(0, {'v': 1, 'client_id': _appId}); // handshake
      browsing();
    } catch (_) {
      _ready = false;
    }
  }

  /// [coverUrl] must be a PUBLIC https image (Discord's proxy can't auth), e.g.
  /// a MangaDex cover. When present it's the big image with the logo as a badge.
  void reading({required String title, String? chapter, String? source, String? coverUrl}) {
    _maybeResetTimer('r:$title:$chapter');
    // Source name intentionally omitted from presence (avoid exposing where
    // scans come from).
    final state = chapter != null ? 'Chapter $chapter' : null;
    final cover = (coverUrl != null && coverUrl.startsWith('http')) ? coverUrl : null;
    _activity(
      details: 'Reading $title',
      state: state,
      largeImage: cover ?? 'logo',
      largeText: title,
      // When large is an external URL, Discord won't render an asset-key small
      // image, so use the public logo URL for the corner bubble.
      smallImage: cover != null ? 'https://yomira.eu/assets/logo.png' : null,
      smallText: cover != null ? 'Yomira' : null,
    );
  }

  void browsing() {
    _maybeResetTimer('b');
    _activity(details: 'Browsing the library');
  }

  void _activity({
    required String details,
    String? state,
    String largeImage = 'logo',
    String largeText = 'Yomira',
    String? smallImage,
    String? smallText,
  }) {
    if (!_ready) return;
    _send(1, {
      'cmd': 'SET_ACTIVITY',
      'args': {
        'pid': 0,
        'activity': {
          'details': details,
          if (state != null) 'state': state,
          'timestamps': {'start': _start.millisecondsSinceEpoch},
          'assets': {
            'large_image': largeImage,
            'large_text': largeText,
            if (smallImage != null) 'small_image': smallImage,
            if (smallText != null) 'small_text': smallText,
          },
          'buttons': [
            {'label': 'Get Yomira', 'url': 'https://yomira.eu'},
          ],
        },
      },
      'nonce': DateTime.now().microsecondsSinceEpoch.toString(),
    });
  }

  // ---- framing ----

  void _send(int op, Map<String, dynamic> json) {
    try {
      final payload = utf8.encode(jsonEncode(json));
      final frame = Uint8List(8 + payload.length);
      final bd = ByteData.sublistView(frame);
      bd.setInt32(0, op, Endian.little);
      bd.setInt32(4, payload.length, Endian.little);
      frame.setRange(8, frame.length, payload);
      if (Platform.isWindows) {
        _writeWindows(frame);
      } else {
        _sock?.add(frame);
      }
    } catch (_) {
      _ready = false;
    }
  }

  // ---- Windows named pipe (win32 FFI) ----

  int _openWindowsPipe() {
    for (var i = 0; i < 10; i++) {
      final name = '\\\\.\\pipe\\discord-ipc-$i';
      final p = name.toNativeUtf16();
      final h = w.CreateFile(
        p,
        w.GENERIC_READ | w.GENERIC_WRITE,
        0,
        nullptr,
        w.OPEN_EXISTING,
        0,
        w.NULL,
      );
      malloc.free(p);
      if (h != w.INVALID_HANDLE_VALUE) return h;
    }
    return w.INVALID_HANDLE_VALUE;
  }

  void _writeWindows(Uint8List data) {
    final buf = malloc<Uint8>(data.length);
    final written = malloc<Uint32>();
    try {
      buf.asTypedList(data.length).setAll(0, data);
      w.WriteFile(_handle, buf.cast(), data.length, written, nullptr);
    } finally {
      malloc.free(buf);
      malloc.free(written);
    }
  }

  // ---- Unix socket discovery ----

  String? _findUnixPipe() {
    final bases = <String>[
      Platform.environment['XDG_RUNTIME_DIR'] ?? '',
      Platform.environment['TMPDIR'] ?? '',
      '/tmp',
    ].where((e) => e.isNotEmpty);
    // Discord, plus Flatpak/Snap sandbox locations.
    final subdirs = ['', 'app/com.discordapp.Discord/', 'snap.discord/'];
    for (final base in bases) {
      for (final sub in subdirs) {
        for (var i = 0; i < 10; i++) {
          final path = '$base/${sub}discord-ipc-$i';
          if (File(path).existsSync()) return path;
        }
      }
    }
    return null;
  }

  void dispose() {
    if (!_ready) return;
    _ready = false;
    try {
      if (Platform.isWindows && _handle != w.INVALID_HANDLE_VALUE) {
        w.CloseHandle(_handle);
      } else {
        _sock?.destroy();
      }
    } catch (_) {}
  }
}
