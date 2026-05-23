import 'dart:typed_data';

import 'package:idb_shim/idb.dart';

import 'blob_descriptor.dart';
import 'blossom_cache.dart';
import 'sha256_hex.dart';

/// A [BlossomCache] backed by [idb_shim], so the same code runs on web
/// (real IndexedDB), native/server (sembast), or pure in-memory (tests).
///
/// The caller provides an [IdbFactory] for their platform:
///
/// ```dart
/// // web
/// final cache = await IdbBlossomCache.open(factory: idbFactoryBrowser);
///
/// // native / server
/// final cache = await IdbBlossomCache.open(factory: idbFactorySembastIo);
///
/// // tests
/// final cache = await IdbBlossomCache.open(factory: newIdbFactoryMemory());
/// ```
class IdbBlossomCache implements BlossomCache {
  static const _defaultDbName = 'blossom_cache';
  static const _metaStore = 'blossom_meta';
  static const _blobStore = 'blossom_blob';
  static const _dbVersion = 2;

  /// Default per-row blob size. Chosen to stay safely under Android's
  /// SQLite CursorWindow limit (~2 MB) when [idb_shim] is backed by sqflite.
  static const defaultChunkSize = 1024 * 1024;

  final IdbFactory factory;
  final String dbName;
  final int chunkSize;
  Database? _db;

  IdbBlossomCache._(this.factory, this.dbName, this.chunkSize);

  /// Opens (or creates) the database backing this cache.
  ///
  /// [chunkSize] caps how many bytes are stored per row in the blob store.
  /// The default ([defaultChunkSize], 1 MB) is safe on Android with a sqflite
  /// backend. On web or backends without per-row caps, a larger value reduces
  /// the number of round-trips for big blobs.
  static Future<IdbBlossomCache> open({
    required IdbFactory factory,
    String dbName = _defaultDbName,
    int chunkSize = defaultChunkSize,
  }) async {
    if (chunkSize <= 0) {
      throw ArgumentError.value(chunkSize, 'chunkSize', 'must be > 0');
    }
    final cache = IdbBlossomCache._(factory, dbName, chunkSize);
    cache._db = await factory.open(
      dbName,
      version: _dbVersion,
      onUpgradeNeeded: (e) {
        final db = e.database;
        if (e.oldVersion == 1) {
          // v1 stored each blob as a single row, incompatible with the chunked
          // layout. Drop both stores so they get recreated empty.
          if (db.objectStoreNames.contains(_metaStore)) {
            db.deleteObjectStore(_metaStore);
          }
          if (db.objectStoreNames.contains(_blobStore)) {
            db.deleteObjectStore(_blobStore);
          }
        }
        if (!db.objectStoreNames.contains(_metaStore)) {
          db.createObjectStore(_metaStore);
        }
        if (!db.objectStoreNames.contains(_blobStore)) {
          db.createObjectStore(_blobStore);
        }
      },
    );
    return cache;
  }

  int _chunkCountFor(int size) =>
      size == 0 ? 0 : (size + chunkSize - 1) ~/ chunkSize;

  String _chunkKey(String sha256, int index) => '$sha256#$index';

  /// Closes the underlying database. Subsequent operations will throw.
  Future<void> close() async {
    _db?.close();
    _db = null;
  }

  Database get _required {
    final db = _db;
    if (db == null) {
      throw StateError('IdbBlossomCache is closed. Re-open it with open().');
    }
    return db;
  }

  @override
  Future<BlobDescriptor> put(
    Uint8List bytes, {
    String? sha256,
    String? type,
    bool pinned = false,
  }) async {
    final key = sha256 ?? sha256Hex(bytes);
    final now = DateTime.now().toUtc();
    final descriptor = BlobDescriptor(
      sha256: key,
      size: bytes.length,
      type: type,
      uploadedAt: now,
      lastAccessedAt: now,
      pinned: pinned,
    );

    final txn = _required.transactionList([
      _metaStore,
      _blobStore,
    ], idbModeReadWrite);

    // Clear chunks from any previous put under the same key: the new blob may
    // have fewer chunks, so stale ones past the new count would otherwise
    // linger.
    final previousMeta = await txn.objectStore(_metaStore).getObject(key);
    if (previousMeta is Map) {
      final previousSize = previousMeta['size'] as int? ?? 0;
      for (var i = 0; i < _chunkCountFor(previousSize); i++) {
        await txn.objectStore(_blobStore).delete(_chunkKey(key, i));
      }
    }

    await txn.objectStore(_metaStore).put(_toMap(descriptor), key);
    final chunkCount = _chunkCountFor(bytes.length);
    for (var i = 0; i < chunkCount; i++) {
      final start = i * chunkSize;
      final end = start + chunkSize > bytes.length
          ? bytes.length
          : start + chunkSize;
      await txn
          .objectStore(_blobStore)
          .put(Uint8List.sublistView(bytes, start, end), _chunkKey(key, i));
    }
    await txn.completed;

    return descriptor;
  }

  @override
  Future<Uint8List?> get(String sha256) async {
    final txn = _required.transactionList([
      _metaStore,
      _blobStore,
    ], idbModeReadWrite);
    final metaRaw = await txn.objectStore(_metaStore).getObject(sha256);
    if (metaRaw is! Map) {
      await txn.completed;
      return null;
    }

    final size = metaRaw['size'] as int? ?? 0;
    final chunkCount = _chunkCountFor(size);
    final bytes = Uint8List(size);
    var offset = 0;
    for (var i = 0; i < chunkCount; i++) {
      final raw = await txn
          .objectStore(_blobStore)
          .getObject(_chunkKey(sha256, i));
      final chunk = raw is Uint8List
          ? raw
          : raw is List<int>
          ? Uint8List.fromList(raw)
          : null;
      if (chunk == null) {
        await txn.completed;
        return null;
      }
      bytes.setRange(offset, offset + chunk.length, chunk);
      offset += chunk.length;
    }

    final updated = Map<String, Object?>.from(metaRaw)
      ..['lastAccessedAt'] = DateTime.now().toUtc().millisecondsSinceEpoch;
    await txn.objectStore(_metaStore).put(updated, sha256);

    await txn.completed;
    return bytes;
  }

  @override
  Future<BlobDescriptor?> head(String sha256) async {
    final txn = _required.transaction(_metaStore, idbModeReadOnly);
    final raw = await txn.objectStore(_metaStore).getObject(sha256);
    await txn.completed;
    if (raw is! Map) return null;
    return _fromMap(Map<String, Object?>.from(raw));
  }

  @override
  Future<bool> delete(String sha256) async {
    final txn = _required.transactionList([
      _metaStore,
      _blobStore,
    ], idbModeReadWrite);
    final metaRaw = await txn.objectStore(_metaStore).getObject(sha256);
    if (metaRaw is! Map) {
      await txn.completed;
      return false;
    }
    final size = metaRaw['size'] as int? ?? 0;
    await txn.objectStore(_metaStore).delete(sha256);
    for (var i = 0; i < _chunkCountFor(size); i++) {
      await txn.objectStore(_blobStore).delete(_chunkKey(sha256, i));
    }
    await txn.completed;
    return true;
  }

  @override
  Future<bool> pin(String sha256) => _setPinned(sha256, true);

  @override
  Future<bool> unpin(String sha256) => _setPinned(sha256, false);

  Future<bool> _setPinned(String sha256, bool value) async {
    final txn = _required.transaction(_metaStore, idbModeReadWrite);
    final raw = await txn.objectStore(_metaStore).getObject(sha256);
    if (raw is! Map) {
      await txn.completed;
      return false;
    }
    final current = raw['pinned'] == true;
    if (current == value) {
      await txn.completed;
      return false;
    }
    final updated = Map<String, Object?>.from(raw)..['pinned'] = value;
    await txn.objectStore(_metaStore).put(updated, sha256);
    await txn.completed;
    return true;
  }

  @override
  Future<List<BlobDescriptor>> list() async {
    final txn = _required.transaction(_metaStore, idbModeReadOnly);
    final all = await txn.objectStore(_metaStore).getAll();
    await txn.completed;
    return all
        .whereType<Map>()
        .map((m) => _fromMap(Map<String, Object?>.from(m)))
        .toList(growable: false);
  }

  static Map<String, Object?> _toMap(BlobDescriptor d) => {
    'sha256': d.sha256,
    'size': d.size,
    'type': d.type,
    'uploadedAt': d.uploadedAt.millisecondsSinceEpoch,
    'lastAccessedAt': d.lastAccessedAt.millisecondsSinceEpoch,
    'pinned': d.pinned,
  };

  static BlobDescriptor _fromMap(Map<String, Object?> m) => BlobDescriptor(
    sha256: m['sha256'] as String,
    size: m['size'] as int,
    type: m['type'] as String?,
    uploadedAt: DateTime.fromMillisecondsSinceEpoch(
      m['uploadedAt'] as int,
      isUtc: true,
    ),
    lastAccessedAt: m['lastAccessedAt'] is int
        ? DateTime.fromMillisecondsSinceEpoch(
            m['lastAccessedAt'] as int,
            isUtc: true,
          )
        : null,
    pinned: m['pinned'] as bool? ?? false,
  );
}
