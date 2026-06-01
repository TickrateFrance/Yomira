import 'config.dart';

/// Reader display mode.
enum ReaderMode { verticalContinuous, horizontalPaged }

/// Persisted reader preferences.
class ReaderSettings {
  const ReaderSettings({
    this.mode = ReaderMode.verticalContinuous,
    this.quality = ReaderQuality.data,
    this.pageWidth = 800,
    this.showNsfw = false,
  });

  final ReaderMode mode;
  final ReaderQuality quality;

  /// Whether 18+ (NSFW) Suwayomi sources are shown. Off by default.
  final bool showNsfw;

  /// Max content width (logical px) for reader pages. On screens wider than
  /// this, pages are centered with black side bars; on phones (narrower than
  /// this) it has no effect. Range enforced by the UI.
  final double pageWidth;

  /// Minimum / maximum selectable page width.
  static const double minWidth = 480;
  static const double maxWidth = 1600;

  ReaderSettings copyWith({
    ReaderMode? mode,
    ReaderQuality? quality,
    double? pageWidth,
    bool? showNsfw,
  }) =>
      ReaderSettings(
        mode: mode ?? this.mode,
        quality: quality ?? this.quality,
        pageWidth: pageWidth ?? this.pageWidth,
        showNsfw: showNsfw ?? this.showNsfw,
      );

  Map<String, dynamic> toJson() => {
        'mode': mode.index,
        'quality': quality.index,
        'pageWidth': pageWidth,
        'showNsfw': showNsfw,
      };

  factory ReaderSettings.fromJson(Map<String, dynamic> j) {
    ReaderMode mode = ReaderMode.verticalContinuous;
    ReaderQuality quality = ReaderQuality.data;
    final mi = j['mode'];
    final qi = j['quality'];
    if (mi is int && mi >= 0 && mi < ReaderMode.values.length) {
      mode = ReaderMode.values[mi];
    }
    if (qi is int && qi >= 0 && qi < ReaderQuality.values.length) {
      quality = ReaderQuality.values[qi];
    }
    final pw = (j['pageWidth'] as num?)?.toDouble() ?? 800;
    return ReaderSettings(
      mode: mode,
      quality: quality,
      pageWidth: pw.clamp(minWidth, maxWidth),
      showNsfw: (j['showNsfw'] as bool?) ?? false,
    );
  }
}
