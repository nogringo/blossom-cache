import 'dart:typed_data';

import 'package:idb_shim/idb.dart';

import 'blob_descriptor.dart';
import 'blossom_cache.dart';

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
  static const _dbVersion = 1;

  final IdbFactory factory;
  final String dbName;
  Database? _db;

  IdbBlossomCache._(this.factory, this.dbName);

  /// Opens (or creates) the database backing this cache.
  static Future<IdbBlossomCache> open({
    required IdbFactory factory,
    String dbName = _defaultDbName,
  }) async {
    final cache = IdbBlossomCache._(factory, dbName);
    cache._db = await factory.open(
      dbName,
      version: _dbVersion,
      onUpgradeNeeded: (e) {
        final db = e.database;
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
    String sha256,
    Uint8List bytes, {
    String? type,
    bool pinned = false,
  }) async {
    final now = DateTime.now().toUtc();
    final descriptor = BlobDescriptor(
      sha256: sha256,
      size: bytes.length,
      type: type,
      uploadedAt: now,
      lastAccessedAt: now,
      pinned: pinned,
    );

    final txn = _required.transactionList(
      [_metaStore, _blobStore],
      idbModeReadWrite,
    );
    await txn.objectStore(_metaStore).put(_toMap(descriptor), sha256);
    await txn.objectStore(_blobStore).put(bytes, sha256);
    await txn.completed;

    return descriptor;
  }

  @override
  Future<Uint8List?> get(String sha256) async {
    final txn = _required.transactionList(
      [_metaStore, _blobStore],
      idbModeReadWrite,
    );
    final raw = await txn.objectStore(_blobStore).getObject(sha256);
    final bytes = raw is Uint8List
        ? raw
        : raw is List<int>
            ? Uint8List.fromList(raw)
            : null;

    if (bytes != null) {
      final metaRaw = await txn.objectStore(_metaStore).getObject(sha256);
      if (metaRaw is Map) {
        final updated = Map<String, Object?>.from(metaRaw)
          ..['lastAccessedAt'] =
              DateTime.now().toUtc().millisecondsSinceEpoch;
        await txn.objectStore(_metaStore).put(updated, sha256);
      }
    }
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
    final txn = _required.transactionList(
      [_metaStore, _blobStore],
      idbModeReadWrite,
    );
    final existed =
        (await txn.objectStore(_metaStore).getObject(sha256)) != null;
    await txn.objectStore(_metaStore).delete(sha256);
    await txn.objectStore(_blobStore).delete(sha256);
    await txn.completed;
    return existed;
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
