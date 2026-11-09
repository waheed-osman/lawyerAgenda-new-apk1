import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import '../data/db.dart';

class DownloadResult {
  final String file; // اسم الملف داخل AppFiles
  final String ext; // pdf | doc | docx
  final int size;
  final String suggestedTitle;
  DownloadResult(this.file, this.ext, this.size, this.suggestedTitle);
}

/// تنزيل ملف PDF/Word من رابط مباشر وحفظه داخل مجلد التطبيق.
/// يرمي [String] برسالة عربية مفهومة عند الفشل.
class Downloader {
  static const maxBytes = 25 * 1024 * 1024;

  static String? _extFromBytes(Uint8List b) {
    if (b.length >= 4 && b[0] == 0x25 && b[1] == 0x50 && b[2] == 0x44 && b[3] == 0x46) return 'pdf'; // %PDF
    if (b.length >= 4 && b[0] == 0x50 && b[1] == 0x4B) return 'docx'; // PK (zip)
    if (b.length >= 4 && b[0] == 0xD0 && b[1] == 0xCF && b[2] == 0x11 && b[3] == 0xE0) return 'doc';
    return null;
  }

  static Future<DownloadResult> fetch(String rawUrl) async {
    var url = rawUrl.trim();
    if (!url.startsWith('http://') && !url.startsWith('https://')) url = 'https://$url';
    final uri = Uri.tryParse(url);
    if (uri == null || uri.host.isEmpty) throw 'الرابط غير صحيح';
    final http.Response r;
    try {
      r = await http.get(uri, headers: {'User-Agent': 'Mozilla/5.0 (Android) LawyerAgenda'}).timeout(const Duration(seconds: 90));
    } on SocketException {
      throw 'لا يوجد اتصال بالإنترنت أو الموقع لا يستجيب';
    } on HttpException {
      throw 'تعذر الاتصال بالموقع';
    } catch (_) {
      throw 'انتهت مهلة التنزيل أو تعذر الاتصال';
    }
    if (r.statusCode != 200) throw 'الموقع رفض التنزيل (رمز ${r.statusCode})';
    final bytes = r.bodyBytes;
    if (bytes.isEmpty) throw 'الملف فارغ';
    if (bytes.length > maxBytes) throw 'الملف أكبر من 25 ميجا';
    final ext = _extFromBytes(bytes);
    if (ext == null) {
      throw 'الرابط لا يشير إلى ملف PDF أو Word مباشر (ربما صفحة ويب). افتح الملف في المتصفح ثم انسخ رابط الملف نفسه، أو نزّله وارفعه من الهاتف';
    }
    final name = '${DateTime.now().microsecondsSinceEpoch}.$ext';
    await AppFiles.resolve(name).writeAsBytes(bytes, flush: true);
    var title = p.basenameWithoutExtension(Uri.decodeComponent(uri.pathSegments.isEmpty ? '' : uri.pathSegments.last));
    if (title.trim().isEmpty) title = uri.host;
    return DownloadResult(name, ext, bytes.length, title);
  }
}
