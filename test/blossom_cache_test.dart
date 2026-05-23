import 'dart:typed_data';

import 'package:blossom_cache/blossom_cache.dart';
import 'package:idb_shim/idb_client_memory.dart';
import 'package:test/test.dart';

Future<IdbBlossomCache> _open() =>
    IdbBlossomCache.open(factory: newIdbFactoryMemory());

const _sha1 =
    '2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824';
const _sha2 =
    '486ea46224d1bb4fb680f34f7c9ad96a8f24ec88be73ea8e5a6c65260e9cb8a7';

Uint8List _bytes(List<int> v) => Uint8List.fromList(v);

void main() {
  group('IdbBlossomCache', () {
    test('put then get returns the bytes', () async {
      final cache = await _open();
      await cache.put(
        _bytes([1, 2, 3]),
        sha256: _sha1,
        type: 'application/octet-stream',
      );
      expect(await cache.get(_sha1), equals(_bytes([1, 2, 3])));
      await cache.close();
    });

    test('get on missing key returns null', () async {
      final cache = await _open();
      expect(await cache.get(_sha1), isNull);
      await cache.close();
    });

    test('head returns descriptor without loading bytes', () async {
      final cache = await _open();
      await cache.put(_bytes([1, 2, 3]), sha256: _sha1, type: 'image/png');
      final d = await cache.head(_sha1);
      expect(d, isNotNull);
      expect(d!.sha256, _sha1);
      expect(d.size, 3);
      expect(d.type, 'image/png');
      expect(d.pinned, isFalse);
      await cache.close();
    });

    test('head on missing key returns null', () async {
      final cache = await _open();
      expect(await cache.head(_sha1), isNull);
      await cache.close();
    });

    test('delete returns true the first time, false after', () async {
      final cache = await _open();
      await cache.put(_bytes([9]), sha256: _sha1);
      expect(await cache.delete(_sha1), isTrue);
      expect(await cache.delete(_sha1), isFalse);
      expect(await cache.get(_sha1), isNull);
      expect(await cache.head(_sha1), isNull);
      await cache.close();
    });

    test('list returns every descriptor', () async {
      final cache = await _open();
      await cache.put(_bytes([1]), sha256: _sha1);
      await cache.put(_bytes([2, 2]), sha256: _sha2);
      final all = await cache.list();
      expect(all.map((d) => d.sha256).toSet(), {_sha1, _sha2});
      await cache.close();
    });

    test('get updates lastAccessedAt; head does not', () async {
      final cache = await _open();
      await cache.put(_bytes([1, 2, 3]), sha256: _sha1);
      final before = (await cache.head(_sha1))!.lastAccessedAt;

      await Future.delayed(const Duration(milliseconds: 5));
      await cache.head(_sha1);
      final afterHead = (await cache.head(_sha1))!.lastAccessedAt;
      expect(
        afterHead,
        equals(before),
        reason: 'head must not update lastAccessedAt',
      );

      await Future.delayed(const Duration(milliseconds: 5));
      await cache.get(_sha1);
      final afterGet = (await cache.head(_sha1))!.lastAccessedAt;
      expect(
        afterGet.isAfter(before),
        isTrue,
        reason: 'get must update lastAccessedAt',
      );

      await cache.close();
    });

    test('pin/unpin toggle the flag and report state changes', () async {
      final cache = await _open();
      await cache.put(_bytes([1]), sha256: _sha1);

      expect(await cache.pin(_sha1), isTrue);
      expect((await cache.head(_sha1))!.pinned, isTrue);
      expect(await cache.pin(_sha1), isFalse, reason: 'no-op repin');

      expect(await cache.unpin(_sha1), isTrue);
      expect((await cache.head(_sha1))!.pinned, isFalse);
      expect(await cache.unpin(_sha1), isFalse, reason: 'no-op reunpin');

      await cache.close();
    });

    test('pin/unpin on missing key returns false', () async {
      final cache = await _open();
      expect(await cache.pin(_sha1), isFalse);
      expect(await cache.unpin(_sha1), isFalse);
      await cache.close();
    });

    test('delete ignores pinned flag (manual delete works)', () async {
      final cache = await _open();
      await cache.put(_bytes([1]), sha256: _sha1, pinned: true);
      expect(await cache.delete(_sha1), isTrue);
      expect(await cache.head(_sha1), isNull);
      await cache.close();
    });

    test('put overwrites and refreshes uploadedAt', () async {
      final cache = await _open();
      await cache.put(_bytes([1]), sha256: _sha1);
      final first = (await cache.head(_sha1))!.uploadedAt;
      await Future.delayed(const Duration(milliseconds: 5));
      await cache.put(_bytes([1, 2]), sha256: _sha1);
      final second = (await cache.head(_sha1))!;
      expect(second.size, 2);
      expect(second.uploadedAt.isAfter(first), isTrue);
      await cache.close();
    });

    test('put without sha256 computes the hash from the bytes', () async {
      final cache = await _open();
      // sha256('hello') == _sha1.
      final bytes = Uint8List.fromList('hello'.codeUnits);

      final descriptor = await cache.put(bytes);

      expect(descriptor.sha256, _sha1);
      expect(await cache.get(_sha1), equals(bytes));
      await cache.close();
    });
  });
}
