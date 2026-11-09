import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../data/db.dart';
import '../data/models.dart';
import '../services/doc_text.dart';
import '../services/security.dart';
import 'ai_screen.dart';

/// عارض ملفات المكتبة:
/// - PDF: يُعرض داخل التطبيق صفحةً صفحة (مع تكبير).
/// - DOCX: يُعرض النص المستخرج.
/// - DOC (قديم): لا يمكن عرضه داخل التطبيق، يُفتح عبر المشاركة بتطبيق آخر.
class LibraryFileScreen extends StatefulWidget {
  final int id;
  const LibraryFileScreen({super.key, required this.id});
  @override
  State<LibraryFileScreen> createState() => _LibraryFileScreenState();
}

class _LibraryFileScreenState extends State<LibraryFileScreen> {
  static const _maxPages = 80;
  LibraryFile? _f;
  String? _text;
  String? _err;
  bool _loading = true;
  bool _rendering = false;
  bool _capped = false;
  double _zoom = 1;
  final _pages = <Uint8List>[];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final f = await Db.i.libraryFile(widget.id);
    if (f == null) {
      if (mounted) setState(() {
            _err = 'الملف غير موجود';
            _loading = false;
          });
      return;
    }
    final file = AppFiles.resolve(f.file);
    if (!await file.exists()) {
      if (mounted) setState(() {
            _f = f;
            _err = 'ملف البيانات مفقود من الجهاز (قد تكون استعدت نسخة احتياطية قديمة).';
            _loading = false;
          });
      return;
    }
    if (f.ext == 'docx') {
      _text = await DocText.fromDocxFile(file);
      if (_text == null) _err = 'تعذّر قراءة نص الملف. استخدم "مشاركة" لفتحه في تطبيق Word.';
    }
    if (mounted) {
      setState(() {
        _f = f;
        _loading = false;
      });
    }
    if (f.ext == 'pdf') _renderPdf(await file.readAsBytes());
  }

  Future<void> _renderPdf(Uint8List bytes) async {
    if (mounted) setState(() => _rendering = true);
    try {
      var n = 0;
      await for (final page in Printing.raster(bytes, dpi: 110)) {
        final png = await page.toPng();
        if (!mounted) return;
        setState(() => _pages.add(png));
        if (++n >= _maxPages) {
          _capped = true;
          break;
        }
      }
    } catch (_) {
      if (mounted && _pages.isEmpty) {
        setState(() => _err = 'تعذّر عرض الملف داخل التطبيق. استخدم "مشاركة" لفتحه في تطبيق آخر.');
      }
    }
    if (mounted) setState(() => _rendering = false);
  }

  Future<void> _share() async {
    final f = _f;
    if (f == null) return;
    await Security.guard(() => Share.shareXFiles([XFile(AppFiles.resolve(f.file).path)], subject: f.title));
  }

  Widget _body() {
    final f = _f;
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (f == null) return Center(child: Text(_err ?? 'غير موجود'));
    if (f.ext == 'pdf') {
      if (_pages.isEmpty && _err != null) return _message(_err!);
      if (_pages.isEmpty) return const Center(child: CircularProgressIndicator());
      return LayoutBuilder(
        builder: (_, box) => SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: box.maxWidth * _zoom,
            height: box.maxHeight,
            child: ListView.builder(
              padding: const EdgeInsets.all(8),
              itemCount: _pages.length + 1,
              itemBuilder: (_, i) {
                if (i == _pages.length) {
                  return Padding(
                    padding: const EdgeInsets.all(16),
                    child: Center(
                        child: _rendering
                            ? const CircularProgressIndicator()
                            : Text(_capped ? 'عُرضت أول $_maxPages صفحة. استخدم "مشاركة" لفتح الملف كاملًا.' : '— نهاية الملف —',
                                style: const TextStyle(fontSize: 12))),
                  );
                }
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Material(
                    elevation: 2,
                    color: Colors.white,
                    child: Image.memory(_pages[i], fit: BoxFit.fitWidth, gaplessPlayback: true),
                  ),
                );
              },
            ),
          ),
        ),
      );
    }
    if (f.ext == 'docx') {
      if (_text == null) return _message(_err ?? 'لا يوجد نص');
      return ListView(padding: const EdgeInsets.all(16), children: [
        const Text('عرض النص فقط (بدون الصور والجداول والتنسيق). للعرض الكامل استخدم "مشاركة" لفتحه في Word.',
            style: TextStyle(fontSize: 11)),
        const SizedBox(height: 10),
        SelectableText(_text!, style: const TextStyle(fontSize: 16, height: 1.9)),
      ]);
    }
    return _message('ملفات Word القديمة (.doc) لا تُعرض داخل التطبيق.\nاضغط "مشاركة" لفتحه في Word أو WPS أو أي تطبيق آخر.\nللتحليل بالذكاء الاصطناعي احفظه بصيغة docx أو PDF.');
  }

  Widget _message(String m) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.insert_drive_file_outlined, size: 56),
            const SizedBox(height: 12),
            Text(m, textAlign: TextAlign.center, style: const TextStyle(height: 1.7)),
            const SizedBox(height: 16),
            FilledButton.icon(onPressed: _share, icon: const Icon(Icons.open_in_new), label: const Text('مشاركة / فتح بتطبيق آخر')),
          ]),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final f = _f;
    return Scaffold(
      appBar: AppBar(
        title: Text(f?.title ?? 'ملف', style: const TextStyle(fontSize: 17)),
        actions: [
          if (f != null && f.ext == 'pdf') ...[
            IconButton(
              tooltip: 'تصغير',
              icon: const Icon(Icons.zoom_out),
              onPressed: _zoom > 1 ? () => setState(() => _zoom -= 0.5) : null,
            ),
            IconButton(
              tooltip: 'تكبير',
              icon: const Icon(Icons.zoom_in),
              onPressed: _zoom < 3 ? () => setState(() => _zoom += 0.5) : null,
            ),
          ],
          if (f != null && f.ext != 'doc')
            IconButton(
              tooltip: 'تلخيص / تحليل بالذكاء الاصطناعي',
              icon: const Icon(Icons.auto_awesome),
              onPressed: () =>
                  Navigator.push(context, MaterialPageRoute(builder: (_) => AiScreen(libraryFileId: f.id))),
            ),
          if (f != null)
            IconButton(tooltip: 'مشاركة / فتح بتطبيق آخر', icon: const Icon(Icons.share), onPressed: _share),
        ],
      ),
      body: _body(),
    );
  }
}
