import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/local/background_store.dart';

/// User-customizable app background: a solid color OR a local image (one at a
/// time). Both null = default theme background.
class BackgroundSettings {
  const BackgroundSettings({this.colorValue, this.imagePath});

  /// Packed 0xAARRGGBB color, or null for none.
  final int? colorValue;

  /// Absolute path to a local image copied into the app's documents dir.
  final String? imagePath;

  bool get isDefault => colorValue == null && imagePath == null;

  Map<String, dynamic> toJson() => {'color': colorValue, 'image': imagePath};

  factory BackgroundSettings.fromJson(Map<String, dynamic> j) => BackgroundSettings(
        colorValue: j['color'] as int?,
        imagePath: j['image'] as String?,
      );
}

/// Holds + persists the background choice.
class BackgroundController extends StateNotifier<BackgroundSettings> {
  BackgroundController(this._store, BackgroundSettings initial) : super(initial);

  final BackgroundStore _store;

  Future<void> setColor(int argb) async {
    state = BackgroundSettings(colorValue: argb); // a color clears any image
    await _store.save(state);
  }

  Future<void> setImage(String path) async {
    state = BackgroundSettings(imagePath: path); // an image clears any color
    await _store.save(state);
  }

  Future<void> reset() async {
    state = const BackgroundSettings();
    await _store.save(state);
  }
}
