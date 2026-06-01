import 'package:isar/isar.dart';
import 'package:path_provider/path_provider.dart';

import 'models/local_models.dart';

/// Opens and exposes the Isar instance. Call [open] once at startup.
class LocalDb {
  LocalDb(this.isar);

  final Isar isar;

  static Future<LocalDb> open() async {
    final dir = await getApplicationDocumentsDirectory();
    final isar = await Isar.open(
      [
        CachedMangaSchema,
        LocalProgressSchema,
        LocalLibrarySchema,
        LocalHistorySchema,
        DownloadedChapterSchema,
      ],
      directory: dir.path,
      name: 'tappreader',
    );
    return LocalDb(isar);
  }
}
