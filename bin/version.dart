import 'package:ffi/ffi.dart';

import 'package:openssl_bridge/index.dart' as lib;

void main() {
  print(lib.OpenSSL_version(0).cast<Utf8>().toDartString());
}
