import 'dart:typed_data';

import 'package:blossom_cache/blossom_cache.dart';
import 'package:idb_shim/idb_client_memory.dart';

// On web, use `idbFactoryBrowser` from `package:idb_shim/idb_browser.dart`.
// On native/server, use `idbFactorySembastIo` from `package:idb_shim/idb_io.dart`.
// In tests or for an ephemeral cache, use `newIdbFactoryMemory()`.

Future<void> main() async {
  final cache = await IdbBlossomCache.open(factory: newIdbFactoryMemory());

  const sha = '2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824';
  final bytes = Uint8List.fromList('hello'.codeUnits);

  final descriptor = await cache.put(sha, bytes, type: 'text/plain');
  print('Stored ${descriptor.sha256} (${descriptor.size} B)');

  final read = await cache.get(sha);
  print('Read back: ${String.fromCharCodes(read!)}');

  await cache.pin(sha);
  print('Pinned: ${(await cache.head(sha))!.pinned}');

  print('All blobs: ${(await cache.list()).length}');

  await cache.close();
}
