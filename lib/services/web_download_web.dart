import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// Starts a normal browser download for [bytes].
void downloadBytes(String fileName, List<int> bytes) {
  final data = Uint8List.fromList(bytes);
  final blob = web.Blob([data.toJS].toJS);
  final url = web.URL.createObjectURL(blob);
  final link = web.document.createElement('a') as web.HTMLAnchorElement
    ..href = url
    ..download = fileName;
  web.document.body?.append(link);
  link.click();
  link.remove();
  web.URL.revokeObjectURL(url);
}
