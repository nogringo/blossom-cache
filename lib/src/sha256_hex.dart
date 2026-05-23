import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// Returns the lowercase hex sha256 of [bytes]. Used as a fallback when the
/// caller does not supply a precomputed hash to `put`.
String sha256Hex(Uint8List bytes) => sha256.convert(bytes).toString();
