import 'dart:typed_data';

import 'package:blossom_cache/blossom_cache.dart';
import 'package:idb_shim/idb_client_memory.dart';
import 'package:test/test.dart';

Future<BoundedBlossomCache> _open(int maxSize) async {
  final inner = await IdbBlossomCache.open(factory: newIdbFactoryMemory());
  return BoundedBlossomCache(inner: inner, maxSize: maxSize);
}

const _shaA =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _shaB =
    'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
const _shaC =
    'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc';
const _shaD =
    'dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd';

Uint8List _bytes(int size, [int fill = 0]) =>
    Uint8List(size)..fillRange(0, size, fill);

void main() {
  group('BoundedBlossomCache', () {
    test('puts under the limit pass through unchanged', () async {
      final cache = await _open(100);
      await cache.put(_shaA, _bytes(30));
      await cache.put(_shaB, _bytes(40));
      expect((await cache.list()).map((d) => d.sha256).toSet(),
          {_shaA, _shaB});
    });

    test('evicts LRU when limit would be exceeded', () async {
      final cache = await _open(100);
      await cache.put(_shaA, _bytes(40));
      await Future.delayed(const Duration(milliseconds: 5));
      await cache.put(_shaB, _bytes(40));
      await Future.delayed(const Duration(milliseconds: 5));

      // Touch A so B becomes the LRU.
      await cache.get(_shaA);
      await Future.delayed(const Duration(milliseconds: 5));

      // Inserting C (40 B) would push total to 120 > 100. B is the LRU.
      await cache.put(_shaC, _bytes(40));

      expect(await cache.head(_shaA), isNotNull);
      expect(await cache.head(_shaB), isNull, reason: 'B was LRU');
      expect(await cache.head(_shaC), isNotNull);
    });

    test('evicts multiple blobs if one is not enough', () async {
      final cache = await _open(100);
      await cache.put(_shaA, _bytes(30));
      await Future.delayed(const Duration(milliseconds: 5));
      await cache.put(_shaB, _bytes(30));
      await Future.delayed(const Duration(milliseconds: 5));
      await cache.put(_shaC, _bytes(30));
      await Future.delayed(const Duration(milliseconds: 5));

      // Insert D (60 B): current total 90, future would be 150, must free 50.
      // LRU order: A, B, C. Evicting A frees 30, B frees another 30 → enough.
      await cache.put(_shaD, _bytes(60));

      expect(await cache.head(_shaA), isNull);
      expect(await cache.head(_shaB), isNull);
      expect(await cache.head(_shaC), isNotNull);
      expect(await cache.head(_shaD), isNotNull);
    });

    test('pinned blobs are not evicted', () async {
      final cache = await _open(100);
      await cache.put(_shaA, _bytes(40), pinned: true);
      await Future.delayed(const Duration(milliseconds: 5));
      await cache.put(_shaB, _bytes(40));
      await Future.delayed(const Duration(milliseconds: 5));

      await cache.put(_shaC, _bytes(40));

      expect(await cache.head(_shaA), isNotNull, reason: 'A is pinned');
      expect(await cache.head(_shaB), isNull, reason: 'B was LRU non-pinned');
      expect(await cache.head(_shaC), isNotNull);
    });

    test('throws when blob alone exceeds maxSize', () async {
      final cache = await _open(50);
      await expectLater(
        cache.put(_shaA, _bytes(100)),
        throwsA(isA<BlossomCacheOverflowException>()),
      );
      expect(await cache.list(), isEmpty);
    });

    test('throws when all remaining blobs are pinned and cannot fit', () async {
      final cache = await _open(100);
      await cache.put(_shaA, _bytes(40), pinned: true);
      await cache.put(_shaB, _bytes(40), pinned: true);

      await expectLater(
        cache.put(_shaC, _bytes(40)),
        throwsA(isA<BlossomCacheOverflowException>()),
      );

      // No state mutated: A and B still there, C absent.
      expect(await cache.head(_shaA), isNotNull);
      expect(await cache.head(_shaB), isNotNull);
      expect(await cache.head(_shaC), isNull);
    });

    test('re-put same key uses delta size (no spurious eviction)', () async {
      final cache = await _open(100);
      await cache.put(_shaA, _bytes(40));
      await Future.delayed(const Duration(milliseconds: 5));
      await cache.put(_shaB, _bytes(40));

      // Re-put A with smaller bytes; future total = 80 - 40 + 20 = 60, no eviction.
      await cache.put(_shaA, _bytes(20));

      expect(await cache.head(_shaA), isNotNull);
      expect(await cache.head(_shaB), isNotNull);
      expect((await cache.head(_shaA))!.size, 20);
    });

    test('re-put same key larger triggers eviction of others', () async {
      final cache = await _open(100);
      await cache.put(_shaA, _bytes(40));
      await Future.delayed(const Duration(milliseconds: 5));
      await cache.put(_shaB, _bytes(40));
      await Future.delayed(const Duration(milliseconds: 5));

      // Re-put A with bigger payload; future total = 80 - 40 + 90 = 130 > 100.
      // Must free 30. Only B is evictable (40 B) → enough.
      await cache.put(_shaA, _bytes(90));

      expect((await cache.head(_shaA))!.size, 90);
      expect(await cache.head(_shaB), isNull);
    });

    test('maxSize <= 0 is rejected', () async {
      final inner = await IdbBlossomCache.open(factory: newIdbFactoryMemory());
      expect(
        () => BoundedBlossomCache(inner: inner, maxSize: 0),
        throwsArgumentError,
      );
      expect(
        () => BoundedBlossomCache(inner: inner, maxSize: -1),
        throwsArgumentError,
      );
    });
  });
}
