# blossom_cache

A network-free local [Blossom](https://github.com/hzrd149/blossom) blob store
for Dart. Same code runs on web, native, and server.

Blobs are addressed by their sha256 hash. The cache itself does not compute or
verify the hash — it is a key/value store that happens to use sha256 as the
key namespace. The caller is responsible for hashing, which lets web apps use
fast `crypto.subtle.digest` instead of a slower pure-Dart implementation.

## Install

```yaml
dependencies:
  blossom_cache: ^0.1.0
  idb_shim: ^2.9.2
```

## Usage

Pick the [`IdbFactory`](https://pub.dev/packages/idb_shim) for your target,
then open the cache:

```dart
import 'dart:typed_data';
import 'package:blossom_cache/blossom_cache.dart';

// Web
import 'package:idb_shim/idb_browser.dart';
final cache = await IdbBlossomCache.open(factory: idbFactoryBrowser);

// Native / server (persistent on disk via sembast)
import 'package:idb_shim/idb_io.dart';
final cache = await IdbBlossomCache.open(factory: idbFactorySembastIo);

// Tests / ephemeral
import 'package:idb_shim/idb_client_memory.dart';
final cache = await IdbBlossomCache.open(factory: newIdbFactoryMemory());
```

Then:

```dart
final sha = '...'; // caller-supplied sha256 hex

await cache.put(sha, bytes, type: 'image/png');
final read = await cache.get(sha);    // Uint8List? — updates lastAccessedAt
final meta = await cache.head(sha);   // BlobDescriptor? — metadata only
final all  = await cache.list();      // List<BlobDescriptor>
await cache.delete(sha);              // bool — manual delete

await cache.pin(sha);                 // protect from future auto-eviction
await cache.unpin(sha);
```

## Pinning

Each blob has a `pinned` flag. A future `BoundedBlossomCache` decorator will
evict by LRU when the cache exceeds a size limit, skipping pinned blobs.
Manual `delete` ignores the flag and always removes the blob.

```dart
// Avatar — evictable
await cache.put(sha, avatarBytes, type: 'image/png');

// Important file — never auto-evicted
await cache.put(sha, fileBytes, type: 'application/pdf', pinned: true);
```

## Custom backends

`BlossomCache` is an abstract class. Implement it against any storage you like
(disk, OPFS, S3, …). The interface is intentionally small: `put`, `get`,
`head`, `delete`, `pin`, `unpin`, `list`.
