/// Thrown when a [BoundedBlossomCache] cannot accommodate a `put`.
///
/// Two cases:
///   * The blob itself is larger than `maxSize`.
///   * The cache is full and every remaining blob is pinned.
class BlossomCacheOverflowException implements Exception {
  /// Human-readable cause.
  final String message;

  /// Size of the blob the caller tried to insert, in bytes.
  final int requestedBytes;

  /// Configured maximum size of the cache, in bytes.
  final int maxSize;

  const BlossomCacheOverflowException(
    this.message, {
    required this.requestedBytes,
    required this.maxSize,
  });

  @override
  String toString() =>
      'BlossomCacheOverflowException: $message (requested $requestedBytes B, max $maxSize B)';
}
