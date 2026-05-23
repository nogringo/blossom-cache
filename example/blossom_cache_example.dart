import 'dart:typed_data';

import 'package:blossom_cache/blossom_cache.dart';
import 'package:idb_shim/idb_client_memory.dart';

// On web, use `idbFactoryBrowser` from `package:idb_shim/idb_browser.dart`.
// On native/server, use `idbFactorySembastIo` from `package:idb_shim/idb_io.dart`.
// In tests or for an ephemeral cache, use `newIdbFactoryMemory()`.

Future<void> main() async {
  final cache = await IdbBlossomCache.open(factory: newIdbFactoryMemory());

  final bytes = Uint8List.fromList('hello'.codeUnits);

  // Omit `sha256:` to have the cache compute it from the bytes.
  final descriptor = await cache.put(bytes, type: 'text/plain');
  final sha = descriptor.sha256;
  print('Stored $sha (${descriptor.size} B)');

  final read = await cache.get(sha);
  print('Read back: ${String.fromCharCodes(read!)}');

  await cache.pin(sha);
  print('Pinned: ${(await cache.head(sha))!.pinned}');

  print('All blobs: ${(await cache.list()).length}');

  await cache.close();
}
