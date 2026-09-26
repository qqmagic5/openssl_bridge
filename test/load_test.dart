import 'dart:ffi';

import 'package:test/test.dart';

import 'package:ffi/ffi.dart';
import 'package:openssl_bridge/api.g.dart' as lib;

void main() async {
  test('loads native library', () {
    final versionPtr = lib.OpenSSL_version(0);

    expect(versionPtr, isNot(nullptr));

    final versionString = versionPtr.cast<Utf8>().toDartString();

    expect(versionString, isNotEmpty);
    expect(versionString, contains('OpenSSL'));
  });
}
