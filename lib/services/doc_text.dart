import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';

/// استخراج النص من ملفات Word الحديثة (.docx) محليًا بدون إنترنت.
/// ملف .docx هو أرشيف ZIP يحوي word/document.xml.
class DocText {
  static String extOf(String path) {
    final i = path.lastIndexOf('.');
    return i < 0 ? '' : path.substring(i + 1).toLowerCase();
  }

  static final _token = RegExp(
    r'<w:t(?:\s[^>]*)?>(.*?)</w:t>|<w:tab\s*/>|<w:br\s*/?>|<w:cr\s*/>|</w:p>',
    dotAll: true,
  );

  static String _unescape(String s) => s
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&apos;', "'")
      .replaceAll('&amp;', '&');

  /// يعيد null إذا لم يكن الملف docx صالحًا.
  static String? fromDocxBytes(Uint8List bytes) {
    try {
      final archive = ZipDecoder().decodeBytes(bytes);
      final entry = archive.findFile('word/document.xml');
      if (entry == null) return null;
      final xml = utf8.decode(entry.content as List<int>, allowMalformed: true);
      final out = StringBuffer();
      for (final m in _token.allMatches(xml)) {
        final tag = m.group(0)!;
        if (tag.startsWith('<w:t>') || tag.startsWith('<w:t ')) {
          out.write(_unescape(m.group(1) ?? ''));
        } else if (tag.startsWith('<w:tab')) {
          out.write('\t');
        } else {
          out.write('\n'); // نهاية فقرة أو سطر جديد
        }
      }
      final text = out.toString().replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
      return text.isEmpty ? null : text;
    } catch (_) {
      return null;
    }
  }

  static Future<String?> fromDocxFile(File f) async => fromDocxBytes(await f.readAsBytes());
}
