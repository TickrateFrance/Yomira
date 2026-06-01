// Minimal smoke test. The full app requires an open Isar instance and secure
// storage, so we keep this as a placeholder unit test rather than booting the
// whole widget tree. Add integration tests under integration_test/ for that.
import 'package:flutter_test/flutter_test.dart';

import 'package:tappreader/core/config.dart';

void main() {
  test('reader quality maps to MangaDex path segments', () {
    expect(ReaderQuality.data.pathSegment, 'data');
    expect(ReaderQuality.dataSaver.pathSegment, 'data-saver');
  });
}
