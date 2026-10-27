import 'dart:convert';
import 'dart:io';

import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../db/app_db.dart';

/// Saves files the user asked for (reports, backups).
///  - Android: opens the share sheet (save to Drive, WhatsApp, Files...).
///  - Windows: saves into the Downloads folder and opens it.
class FileOut {
  static Future<String> save(String fileName, List<int> bytes) async {
    Directory dir;
    if (Platform.isAndroid || Platform.isIOS) {
      dir = await getTemporaryDirectory();
    } else {
      dir = await getDownloadsDirectory() ??
          await getApplicationDocumentsDirectory();
    }
    await dir.create(recursive: true);
    final file = File(p.join(dir.path, fileName));
    await file.writeAsBytes(bytes, flush: true);

    if (Platform.isAndroid || Platform.isIOS) {
      await Share.shareXFiles([XFile(file.path)]);
    } else if (Platform.isWindows) {
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
