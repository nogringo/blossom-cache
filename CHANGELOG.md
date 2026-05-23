## 0.2.0

- **Breaking:** `BlossomCache.put` now takes `bytes` as the only positional
  argument; the hash moves to an optional `sha256:` named parameter. When
  omitted, the cache computes the sha256 from the bytes via `package:crypto`.
  Migration: `cache.put(sha, bytes)` → `cache.put(bytes, sha256: sha)`, or drop
  the `sha256:` argument entirely to let the cache hash it.
- Add `crypto: ^3.0.7` dependency.

## 0.1.0

- Initial version.
