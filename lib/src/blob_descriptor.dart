/// Metadata describing a blob stored in a [BlossomCache].
///
/// The shape mirrors the descriptor returned by Blossom servers (BUD-02), so
/// it can be serialized over a protocol boundary if needed.
class BlobDescriptor {
  /// The sha256 of the blob's bytes, lowercase hex.
  final String sha256;

  /// Size of the blob in bytes.
  final int size;

  /// MIME type, if known.
  final String? type;

  /// When the blob was added to the cache.
  final DateTime uploadedAt;

  /// When the blob was last read via [BlossomCache.get]. Equal to
  /// [uploadedAt] for blobs that have never been read. Not updated by
  /// [BlossomCache.head], [BlossomCache.pin], or [BlossomCache.unpin].
  final DateTime lastAccessedAt;

  /// When `true`, automatic eviction (e.g. by [BoundedBlossomCache]) must
  /// skip this blob. Manual [BlossomCache.delete] still works regardless.
  final bool pinned;

  BlobDescriptor({
    required this.sha256,
    required this.size,
    required this.uploadedAt,
    DateTime? lastAccessedAt,
    this.type,
    this.pinned = false,
  }) : lastAccessedAt = lastAccessedAt ?? uploadedAt;

  /// JSON shape compatible with Blossom protocol responses. The `accessed`
  /// field is a local extension and not part of the standard Blossom spec.
  Map<String, Object?> toJson() => {
    'sha256': sha256,
    'size': size,
    if (type != null) 'type': type,
    'uploaded': uploadedAt.millisecondsSinceEpoch ~/ 1000,
    'accessed': lastAccessedAt.millisecondsSinceEpoch ~/ 1000,
    if (pinned) 'pinned': true,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BlobDescriptor &&
          sha256 == other.sha256 &&
          size == other.size &&
          type == other.type &&
          uploadedAt == other.uploadedAt &&
          lastAccessedAt == other.lastAccessedAt &&
          pinned == other.pinned;

  @override
  int get hashCode =>
      Object.hash(sha256, size, type, uploadedAt, lastAccessedAt, pinned);

  @override
  String toString() =>
      'BlobDescriptor(sha256: $sha256, size: $size, type: $type, pinned: $pinned)';
}
