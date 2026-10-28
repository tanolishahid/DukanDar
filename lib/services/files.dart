import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../db/app_db.dart';
import 'web_download_stub.dart'
    if (dart.library.js_interop) 'web_download_web.dart';

/// Saves files the user asked for (reports, backups).
///  - Android: opens the share sheet (save to Drive, WhatsApp, Files...).
///  - Windows: saves into the Downloads folder and opens it.
///  - Web (browser): downloads the file through the browser.
class FileOut {
  static bool get _isPhone =>
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;

  static Future<String> save(String fileName, List<int> bytes) async {
    if (kIsWeb) {
      downloadBytes(fileName, bytes);
      return '$fileName (see your browser downloads)';
    }

    Directory dir;
    if (_isPhone) {
      dir = await getTemporaryDirectory();
    } else {
      dir = await getDownloadsDirectory() ??
          await getApplicationDocumentsDirectory();
    }
    await dir.create(recursive: true);
    final file = File(p.join(dir.path, fileName));
    await file.writeAsBytes(bytes, flush: true);

    if (_isPhone) {
      await Share.shareXFiles([XFile(file.path)]);
    } else if (defaultTargetPlatform == TargetPlatform.windows) {
      try {
        await Process.run('explorer.exe', ['/select,', file.path]);
      } catch (_) {}
    }
    return file.path;
  }

  /// A full copy of all shop data as one file.
  static Future<String> backupNow() async {
    final data = await AppDb.instance.exportAll();
    final stamp = DateFormat('yyyyMMdd_HHmm').format(DateTime.now());
    final text = const JsonEncoder.withIndent('  ').convert(data);
    return save('dukandar_backup_$stamp.json', utf8.encode(text));
  }
}
