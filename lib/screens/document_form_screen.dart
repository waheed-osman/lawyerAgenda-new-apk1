import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../core/utils.dart';
import '../core/widgets.dart';
import '../data/db.dart';
import '../data/models.dart';
import '../services/security.dart';
import 'ai_screen.dart';

/// محرر مذكرة / مستند نصي مرتبط بقضية (مسودة دفاع، طعن، ملاحظات عمل...).
class DocumentFormScreen extends StatefulWidget {
  final int caseId;
  final int? docId;
  const DocumentFormScreen({super.key, required this.caseId, this.docId});
  @override
  State<DocumentFormScreen> createState() => _DocumentFormScreenState();
}

class _DocumentFormScreenState extends State<DocumentFormScreen> {
  final _title = TextEditingController();
  final _body = TextEditingController();
  String _cat = docCategories.first;
  CaseDocument? _orig;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    if (widget.docId != null) {
      final d = await Db.i.document(widget.docId!);
      if (d != null) {
        _orig = d;
        _title.text = d.title;
        _body.text = d.body;
        _cat = docCategories.contains(d.category) ? d.category : docCategories.last;
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save() async {
    if (_title.text.trim().isEmpty) {
      toast(context, 'اكتب عنوانًا للمذكرة');
      return;
    }
    final d = _orig ?? CaseDocument(caseId: widget.caseId);
    d
      ..title = _title.text.trim()
      ..category = _cat
      ..body = _body.text;
    await Db.i.saveDocument(d);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.docId == null ? 'مذكرة جديدة' : 'تعديل المذكرة'),
        actions: [
          IconButton(
            tooltip: 'تلخيص / مراجعة بالذكاء الاصطناعي',
            icon: const Icon(Icons.auto_awesome),
            onPressed: () {
              if (_body.text.trim().isEmpty) {
                toast(context, 'اكتب نص المذكرة أولًا');
                return;
              }
              Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => AiScreen(
                          contextText: _body.text,
                          contextLabel: _title.text.trim().isEmpty ? 'مذكرة' : _title.text.trim())));
            },
          ),
          IconButton(
            tooltip: 'نسخ النص',
            icon: const Icon(Icons.copy),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: _body.text));
              toast(context, 'تم نسخ النص');
            },
          ),
          IconButton(
            tooltip: 'مشاركة',
            icon: const Icon(Icons.share),
            onPressed: () => Security.guard(() => Share.share(_body.text, subject: _title.text)),
          ),
          if (_orig != null)
            IconButton(
              tooltip: 'حذف',
              icon: const Icon(Icons.delete_outline),
              onPressed: () async {
                if (await confirm(context, 'حذف هذه المذكرة؟', ok: 'حذف')) {
                  await Db.i.deleteDocument(_orig!.id!);
                  if (mounted) Navigator.pop(context);
                }
              },
            ),
          IconButton(tooltip: 'حفظ', icon: const Icon(Icons.check), onPressed: _save),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(padding: const EdgeInsets.all(16), children: [
              tf(_title, 'عنوان المذكرة / المستند', required: true),
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: DropdownButtonFormField<String>(
                  value: _cat,
                  decoration: dec('التصنيف'),
                  items: [for (final c in docCategories) DropdownMenuItem(value: c, child: Text(c))],
                  onChanged: (v) => setState(() => _cat = v!),
                ),
              ),
              TextField(
                controller: _body,
                minLines: 16,
                maxLines: null,
                keyboardType: TextInputType.multiline,
                decoration: dec('النص'),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(onPressed: _save, icon: const Icon(Icons.save), label: const Text('حفظ')),
            ]),
    );
  }
}
