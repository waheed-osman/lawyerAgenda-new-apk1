import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'db.dart';

/// JSON backup / restore. Attachment images and library files (PDF/Word) are
/// embedded as base64 so that a single file contains everything.
class Backup {
  static const _tables = [
    'clients', 'cases', 'sessions', 'history', 'attachments', 'payments', 'templates',
    'documents', 'appointments', // أُضيفت في الإصدار 2
    'library_files', // أُضيفت في الإصدار 3 (النسخ القديمة بدونها تُستعاد عادي)
    'courts', // أُضيفت في الإصدار 4
    'links' // أُضيفت في الإصدار 5
  ];

  /// الجداول التي يشير عمود file فيها لملف داخل مجلد التطبيق، فيُضمَّن في النسخة base64.
  static const _fileTables = {'attachments', 'library_files'};

  /// Creates the backup file in a temp folder and returns it.
  static Future<File> export() async {
    final d = await Db.i.db;
    final tables = <String, Object?>{};
    for (final t in _tables) {
      final rows = await d.query(t);
      if (_fileTables.contains(t)) {
        final out = <Map<String, Object?>>[];
        for (final r in rows) {
          final m = Map<String, Object?>.from(r);
          final f = AppFiles.resolve(m['file'] as String);
          m['data'] = await f.exists() ? base64Encode(await f.readAsBytes()) : null;
          out.add(m);
        }
        tables[t] = out;
      } else {
        tables[t] = rows;
      }
    }
    final data = {
      'app': 'lawyer_agenda',
      'version': 5,
      'created': DateTime.now().toIso8601String(),
      'tables': tables,
    };
    final tmp = await getTemporaryDirectory();
    final n = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    final name = 'agenda_backup_${n.year}${two(n.month)}${two(n.day)}_${two(n.hour)}${two(n.minute)}.json';
    final file = File(p.join(tmp.path, name));
    await file.writeAsString(jsonEncode(data));
    return file;
  }

  /// Replaces ALL current data with the content of [file].
  static Future<void> restore(File file) async {
    final decoded = jsonDecode(await file.readAsString());
    if (decoded is! Map || decoded['app'] != 'lawyer_agenda' || decoded['tables'] is! Map) {
      throw const FormatException('ملف النسخة الاحتياطية غير صالح');
    }
    final tables = decoded['tables'] as Map;
    final d = await Db.i.db;

    // clear old attachment files
    if (await AppFiles.dir.exists()) {
      await for (final e in AppFiles.dir.list()) {
        try {
          if (e is File) await e.delete();
        } catch (_) {}
      }
    }

    await d.transaction((txn) async {
      for (final t in _tables.reversed) {
        await txn.delete(t);
      }
      for (final t in _tables) {
        final rows = (tables[t] as List?) ?? const [];
        for (final r in rows) {
          final m = Map<String, Object?>.from(r as Map);
          if (_fileTables.contains(t)) {
            final data = m.remove('data') as String?;
            if (data != null) {
              await AppFiles.resolve(m['file'] as String).writeAsBytes(base64Decode(data));
            }
          }
          await txn.insert(t, m);
        }
      }
    });
    Db.i.changed();
  }
}
