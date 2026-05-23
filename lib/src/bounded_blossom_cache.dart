import 'dart:typed_data';

import 'blob_descriptor.dart';
import 'blossom_cache.dart';
import 'blossom_cache_exception.dart';
import 'sha256_hex.dart';

/// A [BlossomCache] that caps the total stored size and evicts blobs in LRU
/// order (`lastAccessedAt` ascending) when a `put` would exceed [maxSize].
///
/// Blobs flagged as [BlobDescriptor.pinned] are skipped during eviction. If
/// the cache cannot make enough room (single blob too large, or every
/// non-pinned blob put together still isn't enough), `put` throws
/// [BlossomCacheOverflowException] and the cache is left unchanged.
///
/// Not concurrency-safe: it is assumed that calls into the same instance are
/// serialised by the caller. Every `put` reads the full inner descriptor list
/// to compute current usage, so this decorator scales linearly with blob
/// count. Fine for a few thousand blobs, slow past that.
class BoundedBlossomCache implements BlossomCache {
  /// The wrapped cache. Do not call its methods directly; bypassing the
  /// decorator skips eviction accounting.
  final BlossomCache inner;

  /// Maximum total size, in bytes, of all stored blobs.
  final int maxSize;

  BoundedBlossomCache({required this.inner, required this.maxSize}) {
    if (maxSize <= 0) {
      throw ArgumentError.value(maxSize, 'maxSize', 'must be > 0');
    }
  }

  @override
  Future<BlobDescriptor> put(
    Uint8List bytes, {
    String? sha256,
    String? type,
    bool pinned = false,
  }) async {
    if (bytes.length > maxSize) {
      throw BlossomCacheOverflowException(
        'Blob alone exceeds maxSize',
        requestedBytes: bytes.length,
        maxSize: maxSize,
      );
    }

    final key = sha256 ?? sha256Hex(bytes);
    final all = await inner.list();
    final existing = all.where((d) => d.sha256 == key).firstOrNull;
    final existingSize = existing?.size ?? 0;
    final currentTotal = all.fold<int>(0, (s, d) => s + d.size);
    final futureTotal = currentTotal - existingSize + bytes.length;

    if (futureTotal > maxSize) {
      final mustFree = futureTotal - maxSize;
      final evictable = all.where((d) => !d.pinned && d.sha256 != key).toList()
        ..sort((a, b) => a.lastAccessedAt.compareTo(b.lastAccessedAt));

      var freed = 0;
      for (final d in evictable) {
        if (freed >= mustFree) break;
        if (await inner.delete(d.sha256)) freed += d.size;
      }

      if (freed < mustFree) {
        throw BlossomCacheOverflowException(
          'Cannot make room: pinned blobs prevent eviction',
          requestedBytes: bytes.length,
          maxSize: maxSize,
        );
      }
    }

    return inner.put(bytes, sha256: key, type: type, pinned: pinned);
  }

  @override
  Future<Uint8List?> get(String sha256) => inner.get(sha256);

  @override
  Future<BlobDescriptor?> head(String sha256) => inner.head(sha256);

  @override
  Future<bool> delete(String sha256) => inner.delete(sha256);

  @override
  Future<bool> pin(String sha256) => inner.pin(sha256);

  @override
  Future<bool> unpin(String sha256) => inner.unpin(sha256);

  @override
  Future<List<BlobDescriptor>> list() => inner.list();
}
