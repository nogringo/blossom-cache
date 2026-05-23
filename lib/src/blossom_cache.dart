import 'dart:typed_data';

import 'blob_descriptor.dart';

/// A local, network-free Blossom blob store.
///
/// Blobs are addressed by their sha256 hash. The caller may supply the hash
/// (cheap when it is already known, e.g. from a Blossom server response) or
/// let the cache compute it.
///
/// Implementations may be backed by memory, disk, IndexedDB, or anything else.
/// All operations are asynchronous so the same interface fits sync and async
/// backends uniformly.
abstract class BlossomCache {
  /// Stores [bytes] and returns the descriptor.
  ///
  /// If [sha256] is `null` the cache computes it from [bytes]; otherwise the
  /// supplied value is used as-is and is not verified.
  ///
  /// Putting the same key twice overwrites the previous bytes and refreshes
  /// the descriptor's [BlobDescriptor.uploadedAt].
  ///
  /// When [pinned] is `true`, the blob is excluded from automatic eviction
  /// (e.g. by [BoundedBlossomCache]). Manual [delete] still removes it.
  Future<BlobDescriptor> put(
    Uint8List bytes, {
    String? sha256,
    String? type,
    bool pinned = false,
  });

  /// Returns the bytes for [sha256], or `null` if absent.
  ///
  /// On a successful hit, implementations MUST update the blob's
  /// [BlobDescriptor.lastAccessedAt] to the current time so that LRU-based
  /// eviction can rely on it.
  Future<Uint8List?> get(String sha256);

  /// Returns the descriptor for [sha256] without loading the bytes, or `null`
  /// if absent. Equivalent to a Blossom HEAD request.
  Future<BlobDescriptor?> head(String sha256);

  /// Removes the blob with [sha256]. Returns `true` if it existed. Manual
  /// deletion ignores [BlobDescriptor.pinned].
  Future<bool> delete(String sha256);

  /// Marks the blob as pinned so automatic eviction will skip it. Returns
  /// `true` if the state actually changed, `false` if the blob was already
  /// pinned or does not exist.
  Future<bool> pin(String sha256);

  /// Clears the pinned flag on the blob. Returns `true` if the state actually
  /// changed, `false` if the blob was not pinned or does not exist.
  Future<bool> unpin(String sha256);

  /// Lists every blob descriptor currently held by the cache.
  Future<List<BlobDescriptor>> list();
}
