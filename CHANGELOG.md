## 0.4.0

- Add `BlossomCache.clearAllLocalData()`, which wipes every blob and its
  metadata (pinned ones included) and leaves the cache usable. On
  `IdbBlossomCache` it clears both object stores in a single transaction, so
  it also reclaims any orphaned chunk.
- **Breaking (implementers only):** custom `BlossomCache` implementations must
  now provide `clearAllLocalData`. Callers of the built-in caches are
  unaffected.

## 0.3.0

- Fix Android `CursorWindow` ~2 MB row limit when `idb_shim` is backed by
  sqflite: `IdbBlossomCache` now stores blobs as fixed-size chunks instead of
  a single row, so blobs larger than ~2 MB round-trip correctly on Android.
- Add `chunkSize` parameter to `IdbBlossomCache.open()` (default 1 MB). Raise
  it on web for fewer round-trips, lower it for constrained devices.
- **Breaking (on-disk):** database schema bumped to version 2. Caches written
  by 0.2.0 and earlier are dropped on first open with this version; the API is
  unchanged.

## 0.2.0

- **Breaking:** `BlossomCache.put` now takes `bytes` as the only positional
  argument; the hash moves to an optional `sha256:` named parameter. When
  omitted, the cache computes the sha256 from the bytes via `package:crypto`.
  Migration: `cache.put(sha, bytes)` → `cache.put(bytes, sha256: sha)`, or drop
  the `sha256:` argument entirely to let the cache hash it.
- Add `crypto: ^3.0.7` dependency.

## 0.1.0

- Initial version.
