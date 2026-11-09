import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/utils.dart';
import '../data/db.dart';
import '../data/models.dart';
import '../services/doc_text.dart';
import '../services/gemini.dart';
import '../services/security.dart';

/// مرفق للمحادثة: نص أو ملف PDF.
class _Ctx {
  final String label;
  final String? text;
  final Uint8List? pdf;
  _Ctx(this.label, {this.text, this.pdf});
}

class _Item {
  final bool user;
  final String text;
  final String? attach;
  final bool error;
  _Item(this.user, this.text, {this.attach, this.error = false});
}

const _quickPrompts = <String>[
  'لخّص هذا المستند في نقاط',
  'حلّل الموقف القانوني للقضية',
  'اقترح أوجه الدفاع والدفوع المناسبة',
  'استخرج الوقائع والمواعيد والمدد المهمة',
  'راجع الصياغة وحسّنها لغويًا وقانونيًا',
];

/// المساعد القانوني الذكي (Gemini): محادثة + تلخيص وتحليل المستندات والمذكرات.
/// يمكن فتحه فارغًا، أو مع ملخص قضية، أو ملف من المكتبة، أو نص مذكرة.
class AiScreen extends StatefulWidget {
  final int? caseId;
  final int? libraryFileId;
  final String? contextText;
  final String? contextLabel;
  const AiScreen({super.key, this.caseId, this.libraryFileId, this.contextText, this.contextLabel});
  @override
  State<AiScreen> createState() => _AiScreenState();
}

class _AiScreenState extends State<AiScreen> {
  final _ctrl = TextEditingController();
  final _scroll = ScrollController();
  final _items = <_Item>[];
  final _history = <AiMsg>[];
  _Ctx? _ctx;
  bool _sending = false;
  bool _hasKey = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _init());
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    final hasKey = (await Gemini.apiKey()).isNotEmpty;
    if (mounted) setState(() => _hasKey = hasKey);
    if (widget.caseId != null) {
      final t = await _caseSummary(widget.caseId!);
      if (t.isNotEmpty && mounted) setState(() => _ctx = _Ctx('ملخص القضية', text: t));
    } else if (widget.libraryFileId != null) {
      final f = await Db.i.libraryFile(widget.libraryFileId!);
      if (f != null && mounted) await _attachFile(AppFiles.resolve(f.file), f.title, f.ext);
    } else if (widget.contextText != null && widget.contextText!.trim().isNotEmpty) {
      if (mounted) setState(() => _ctx = _Ctx(widget.contextLabel ?? 'نص مرفق', text: widget.contextText));
    }
  }

  // ---------- تجميع بيانات القضية كنص ----------
  Future<String> _caseSummary(int caseId) async {
    final c = await Db.i.legalCase(caseId);
    if (c == null) return '';
    final sessions = await Db.i.sessions(caseId: caseId);
    final hist = await Db.i.history(caseId);
    final docs = await Db.i.documents(caseId);
    final b = StringBuffer()
      ..writeln('بيانات القضية:')
      ..writeln('- الرقم: ${caseLabel(c.number, c.year)}')
      ..writeln('- النوع: ${c.type} | الحالة: ${caseStatuses[c.status] ?? c.status}')
      ..writeln('- المحكمة: ${c.court} | الدائرة: ${c.circuit}')
      ..writeln('- الموكل: ${c.clientName} (${c.clientRole}) | الخصم: ${c.opponent}');
    if (c.title.trim().isNotEmpty) b.writeln('- الموضوع: ${c.title}');
    if (c.notes.trim().isNotEmpty) b.writeln('- ملاحظات: ${c.notes}');
    if (sessions.isNotEmpty) {
      b.writeln('\nالجلسات:');
      for (final s in sessions) {
        b.writeln('- ${fmtShort(s.date)} (${sessionTypes[s.type] ?? s.type})'
            '${s.decision.trim().isEmpty ? '' : ' | القرار: ${s.decision}'}'
            '${s.notes.trim().isEmpty ? '' : ' | ملاحظات: ${s.notes}'}');
      }
    }
    if (hist.isNotEmpty) {
      b.writeln('\nسجل القضية:');
      for (final h in hist) {
        b.writeln('- ${fmtShort(h.date)}: ${h.text}');
      }
    }
    if (docs.isNotEmpty) {
      b.writeln('\nالمذكرات المدوّنة (عناوين فقط): ${docs.map((d) => d.title).join('، ')}');
    }
    return b.toString();
  }

  // ---------- المرفقات ----------
  Future<T?> _pick<T>(String title, List<T> items, String Function(T) label, {String Function(T)? sub}) {
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.7),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Padding(padding: const EdgeInsets.all(14), child: Text(title, style: const TextStyle(fontWeight: FontWeight.bold))),
            Flexible(
              child: items.isEmpty
                  ? const Padding(padding: EdgeInsets.all(24), child: Text('لا توجد عناصر'))
                  : ListView(shrinkWrap: true, children: [
                      for (final x in items)
                        ListTile(
                          title: Text(label(x)),
                          subtitle: sub == null ? null : Text(sub(x)),
                          onTap: () => Navigator.pop(ctx, x),
                        ),
                    ]),
            ),
          ]),
        ),
      ),
    );
  }

  Future<LegalCase?> _pickCase() async => _pick<LegalCase>(
        'اختر القضية',
        await Db.i.cases(),
        (c) => caseLabel(c.number, c.year),
        sub: (c) => [c.clientName, c.court].where((e) => e.isNotEmpty).join(' • '),
      );

  Future<void> _attachCase() async {
    final c = await _pickCase();
    if (c == null) return;
    final t = await _caseSummary(c.id!);
    if (mounted) setState(() => _ctx = _Ctx('ملخص ${caseLabel(c.number, c.year)}', text: t));
  }

  Future<void> _attachMemo() async {
    final c = await _pickCase();
    if (c == null) return;
    final docs = await Db.i.documents(c.id!);
    if (!mounted) return;
    final d = await _pick<CaseDocument>('اختر المذكرة', docs, (d) => d.title, sub: (d) => d.category);
    if (d != null && mounted) setState(() => _ctx = _Ctx('مذكرة: ${d.title}', text: d.body));
  }

  Future<void> _attachTemplate() async {
    final list = await Db.i.templates();
    if (!mounted) return;
    final t = await _pick<LegalTemplate>('اختر النموذج', list, (t) => t.title, sub: (t) => t.category);
    if (t != null && mounted) setState(() => _ctx = _Ctx('نموذج: ${t.title}', text: t.body));
  }

  Future<void> _attachLibraryFile() async {
    final all = await Db.i.libraryFiles();
    if (!mounted) return;
    final f = await _pick<LibraryFile>('ملفات المكتبة', all, (f) => f.title, sub: (f) => f.ext.toUpperCase());
    if (f != null && mounted) await _attachFile(AppFiles.resolve(f.file), f.title, f.ext);
  }

  Future<void> _attachFromPhone() async {
    final res = await Security.guard(() => FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: ['pdf', 'docx', 'doc'],
        ));
    final path = res?.files.single.path;
    if (path == null || !mounted) return;
    await _attachFile(File(path), res!.files.single.name, DocText.extOf(path));
  }

  Future<void> _attachFile(File f, String label, String ext) async {
    if (ext == 'pdf') {
      if (await f.length() > 15 * 1024 * 1024) {
        if (mounted) toast(context, 'ملف PDF كبير (أكثر من 15 ميجا). استخدم ملفًا أصغر.');
        return;
      }
      if (await Gemini.redactEnabled() && mounted) {
        final ok = await confirm(
            context, 'ملفات PDF تُرسل كما هي إلى Google ولا يمكن حجب البيانات الشخصية داخلها تلقائيًا. هل تريد المتابعة؟',
            ok: 'متابعة');
        if (!ok) return;
      }
      final bytes = await f.readAsBytes();
      if (mounted) setState(() => _ctx = _Ctx(label, pdf: bytes));
    } else if (ext == 'docx') {
      final t = await DocText.fromDocxFile(f);
      if (!mounted) return;
      if (t == null) {
        toast(context, 'تعذّر قراءة النص من الملف. جرّب حفظه بصيغة PDF.');
      } else {
        setState(() => _ctx = _Ctx(label, text: t));
      }
    } else {
      toast(context, 'ملفات Word القديمة (.doc) غير مدعومة للتحليل. احفظها بصيغة docx أو PDF.');
    }
  }

  void _attachMenu() {
    Widget tile(IconData i, String t, VoidCallback f) => ListTile(
          leading: Icon(i),
          title: Text(t),
          onTap: () {
            Navigator.pop(context);
            f();
          },
        );
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            tile(Icons.gavel, 'ملخص بيانات قضية', _attachCase),
            tile(Icons.article_outlined, 'مذكرة من قضية', _attachMemo),
            tile(Icons.folder_copy_outlined, 'ملف من المكتبة (PDF / Word)', _attachLibraryFile),
            tile(Icons.upload_file, 'ملف من الهاتف (PDF / Word)', _attachFromPhone),
            tile(Icons.description_outlined, 'نموذج قانوني', _attachTemplate),
          ]),
        ),
      ),
    );
  }

  // ---------- الإرسال ----------
  Future<bool> _ensureConsent() async {
    if (await Gemini.consented()) return true;
    if (!mounted) return false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تنبيه خصوصية'),
        content: const SingleChildScrollView(
          child: Text(
            'عند استخدام المساعد يُرسل نص سؤالك والمستندات المرفقة عبر الإنترنت إلى خوادم Google (Gemini). '
            'وفق شروط Google قد يُستخدم المحتوى في الخطة المجانية لتحسين خدماتها.\n\n'
            'بقية التطبيق يعمل بدون إنترنت وبياناتك الأخرى لا تغادر جهازك.\n\n'
            'يحجب التطبيق تلقائيًا الأرقام القومية والهواتف والبريد وأسماء الموكلين والخصوم المسجلة في التطبيق '
            '(يمكن إيقاف ذلك من الإعدادات). ملفات PDF تُرسل كما هي.\n\n'
            'تجنّب إرسال أسرار شديدة الحساسية، وراجع كل ما يكتبه المساعد قبل الاعتماد عليه.',
            style: TextStyle(height: 1.6),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('موافق ومتابعة')),
        ],
      ),
    );
    if (ok == true) await Gemini.setConsented(true);
    return ok == true;
  }

  void _toEnd() => WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) {
          _scroll.animateTo(_scroll.position.maxScrollExtent + 200,
              duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
        }
      });

  Future<void> _send([String? preset]) async {
    if (_sending) return;
    final typed = (preset ?? _ctrl.text).trim();
    if (typed.isEmpty && _ctx == null) return;
    if ((await Gemini.apiKey()).isEmpty) {
      if (!mounted) return;
      await showAiSettings(context);
      final has = (await Gemini.apiKey()).isNotEmpty;
      if (mounted) setState(() => _hasKey = has);
      return;
    }
    if (!await _ensureConsent()) return;
    final ctx = _ctx;
    final prompt = typed.isEmpty ? 'لخّص هذا المستند في نقاط.' : typed;
    setState(() {
      _sending = true;
      _items.removeWhere((i) => i.error);
    });
    try {
      final redact = await Gemini.redactEnabled();
      final parts = <AiPart>[];
      if (ctx?.text != null) {
        var t = ctx!.text!;
        if (t.length > 300000) t = '${t.substring(0, 300000)}\n...(اقتُطع النص لطوله)';
        if (redact) t = await Redactor.apply(t);
        parts.add(AiPart.text('المستند المرفق (${ctx.label}):\n$t'));
      }
      if (ctx?.pdf != null) parts.add(AiPart.file(ctx!.pdf!, 'application/pdf'));
      parts.add(AiPart.text(redact ? await Redactor.apply(prompt) : prompt));
      _history.add(AiMsg(true, parts));
      if (mounted) {
        setState(() {
          _items.add(_Item(true, prompt, attach: ctx?.label));
          _ctx = null;
          if (preset == null) _ctrl.clear();
        });
      }
      _toEnd();
      try {
        final reply = await Gemini.generate(_history);
        _history.add(AiMsg(false, [AiPart.text(reply)]));
        if (mounted) setState(() => _items.add(_Item(false, reply)));
      } catch (e) {
        _history.removeLast(); // تراجع: لتبقى المحادثة سليمة ويمكن إعادة المحاولة
        final msg = e is AiException ? e.message : 'خطأ غير متوقع: $e';
        if (mounted) {
          setState(() {
            _items.removeLast();
            _ctx = ctx;
            if (preset == null) _ctrl.text = typed;
            _items.add(_Item(false, msg, error: true));
          });
        }
      }
    } finally {
      if (mounted) setState(() => _sending = false);
      _toEnd();
    }
  }

  void _quick(String prompt) {
    if (_ctx != null || _history.isNotEmpty) {
      _send(prompt);
    } else {
      _ctrl.text = '$prompt:\n\n';
      _ctrl.selection = TextSelection.collapsed(offset: _ctrl.text.length);
      toast(context, 'الصق النص بعد العنوان ثم أرسل، أو أرفق مستندًا بزر المشبك');
    }
  }

  // ---------- أفعال على الرد ----------
  Future<void> _saveAsMemo(String text) async {
    int? caseId = widget.caseId;
    if (caseId == null) {
      final c = await _pickCase();
      if (c == null) return;
      caseId = c.id;
    }
    await Db.i.saveDocument(CaseDocument(
      caseId: caseId!,
      title: 'مسودة المساعد الذكي - ${fmtShort(DateTime.now())}',
      category: 'ملاحظات عمل',
      body: _plain(text),
    ));
    if (mounted) toast(context, 'تم الحفظ في مذكرات القضية (راجعه قبل الاعتماد)');
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final empty = _items.isEmpty;
    return Scaffold(
      appBar: AppBar(
        title: const Text('المساعد القانوني الذكي'),
        actions: [
          if (!empty)
            IconButton(
              tooltip: 'محادثة جديدة',
              icon: const Icon(Icons.delete_sweep_outlined),
              onPressed: () => setState(() {
                _items.clear();
                _history.clear();
                _ctx = null;
              }),
            ),
          IconButton(
            tooltip: 'إعدادات المساعد',
            icon: const Icon(Icons.tune),
            onPressed: () async {
              await showAiSettings(context);
              final has = (await Gemini.apiKey()).isNotEmpty;
              if (mounted) setState(() => _hasKey = has);
            },
          ),
        ],
      ),
      body: Column(children: [
        if (!_hasKey)
          Card(
            margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            color: cs.tertiaryContainer,
            child: ListTile(
              leading: const Icon(Icons.key),
              title: const Text('المساعد غير مُفعّل بعد'),
              subtitle: const Text('أدخل مفتاح Gemini المجاني مرة واحدة'),
              trailing: FilledButton(
                onPressed: () async {
                  await showAiSettings(context);
                  final has = (await Gemini.apiKey()).isNotEmpty;
                  if (mounted) setState(() => _hasKey = has);
                },
                child: const Text('إعداد'),
              ),
            ),
          ),
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 6, 16, 2),
          child: Text('أداة مساعدة قد تخطئ. راجع أي مادة قانونية أو حكم قبل الاعتماد عليه.',
              style: TextStyle(fontSize: 11), textAlign: TextAlign.center),
        ),
        Expanded(
          child: empty
              ? ListView(padding: const EdgeInsets.all(20), children: [
                  const SizedBox(height: 20),
                  Icon(Icons.auto_awesome, size: 56, color: cs.primary),
                  const SizedBox(height: 12),
                  const Text('كيف أساعدك اليوم؟',
                      textAlign: TextAlign.center, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  const Text('أرفق مستندًا أو مذكرة أو قضية بزر المشبك، أو اكتب سؤالك مباشرة.',
                      textAlign: TextAlign.center),
                  const SizedBox(height: 20),
                  Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.center, children: [
                    for (final q in _quickPrompts) ActionChip(label: Text(q), onPressed: () => _quick(q)),
                  ]),
                ])
              : ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                  itemCount: _items.length + (_sending ? 1 : 0),
                  itemBuilder: (_, i) {
                    if (i == _items.length) {
                      return const Align(
                        alignment: AlignmentDirectional.centerEnd,
                        child: Padding(
                          padding: EdgeInsets.all(12),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                            SizedBox(width: 10),
                            Text('جارٍ التحليل...'),
                          ]),
                        ),
                      );
                    }
                    return _bubble(_items[i], cs);
                  },
                ),
        ),
        if (_ctx != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: InputChip(
                avatar: Icon(_ctx!.pdf != null ? Icons.picture_as_pdf : Icons.attach_file, size: 18),
                label: Text(_ctx!.label, overflow: TextOverflow.ellipsis),
                onDeleted: () => setState(() => _ctx = null),
              ),
            ),
          ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
            child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              IconButton(tooltip: 'إرفاق', icon: const Icon(Icons.attach_file), onPressed: _sending ? null : _attachMenu),
              Expanded(
                child: TextField(
                  controller: _ctrl,
                  minLines: 1,
                  maxLines: 6,
                  textInputAction: TextInputAction.newline,
                  decoration: const InputDecoration(hintText: 'اكتب سؤالك أو الصق نصًا...', isDense: true),
                ),
              ),
              IconButton.filled(
                tooltip: 'إرسال',
                icon: const Icon(Icons.send),
                onPressed: _sending ? null : () => _send(),
              ),
            ]),
          ),
        ),
      ]),
    );
  }

  Widget _bubble(_Item it, ColorScheme cs) {
    final base = TextStyle(fontSize: 15, height: 1.7, color: it.error ? cs.onErrorContainer : cs.onSurface);
    return Align(
      alignment: it.user ? AlignmentDirectional.centerStart : AlignmentDirectional.centerEnd,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.9),
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
        decoration: BoxDecoration(
          color: it.error ? cs.errorContainer : (it.user ? cs.primaryContainer : cs.surfaceContainerHighest),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          if (it.attach != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.attach_file, size: 15),
                const SizedBox(width: 4),
                Flexible(child: Text(it.attach!, style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis)),
              ]),
            ),
          if (it.user || it.error) SelectableText(it.text, style: base) else SelectableText.rich(_md(it.text, base)),
          if (!it.user && !it.error)
            Row(mainAxisSize: MainAxisSize.min, children: [
              IconButton(
                tooltip: 'نسخ',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.copy, size: 18),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: _plain(it.text)));
                  toast(context, 'تم النسخ');
                },
              ),
              IconButton(
                tooltip: 'مشاركة',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.share, size: 18),
                onPressed: () => Security.guard(() => Share.share(_plain(it.text))),
              ),
              IconButton(
                tooltip: 'حفظ كمذكرة في قضية',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.note_add_outlined, size: 18),
                onPressed: () => _saveAsMemo(it.text),
              ),
            ]),
        ]),
      ),
    );
  }
}

// ---------- عرض بسيط لتنسيق Markdown الذي يرجعه الموديل ----------
TextSpan _md(String text, TextStyle base) {
  final spans = <InlineSpan>[];
  final lines = text.split('\n');
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i];
    var style = base;
    final h = RegExp(r'^\s*#{1,6}\s+(.*)$').firstMatch(line);
    if (h != null) {
      line = h.group(1)!;
      style = base.copyWith(fontWeight: FontWeight.bold, fontSize: (base.fontSize ?? 15) + 2);
    }
    line = line.replaceFirstMapped(RegExp(r'^(\s*)[*\-]\s+'), (m) => '${m.group(1)}• ');
    var last = 0;
    for (final m in RegExp(r'\*\*(.+?)\*\*').allMatches(line)) {
      if (m.start > last) spans.add(TextSpan(text: line.substring(last, m.start), style: style));
      spans.add(TextSpan(text: m.group(1), style: style.copyWith(fontWeight: FontWeight.bold)));
      last = m.end;
    }
    if (last < line.length) spans.add(TextSpan(text: line.substring(last), style: style));
    if (i < lines.length - 1) spans.add(TextSpan(text: '\n', style: style));
  }
  return TextSpan(children: spans, style: base);
}

String _plain(String t) => t
    .replaceAll('**', '')
    .replaceAllMapped(RegExp(r'^\s*#{1,6}\s+', multiLine: true), (_) => '')
    .replaceAllMapped(RegExp(r'^(\s*)[*\-]\s+', multiLine: true), (m) => '${m.group(1)}• ');

// ---------- إعدادات المساعد ----------
Future<void> showAiSettings(BuildContext context) =>
    showDialog<void>(context: context, builder: (_) => const _AiSettingsDialog());

class _AiSettingsDialog extends StatefulWidget {
  const _AiSettingsDialog();
  @override
  State<_AiSettingsDialog> createState() => _AiSettingsDialogState();
}

class _AiSettingsDialogState extends State<_AiSettingsDialog> {
  final _key = TextEditingController();
  final _model = TextEditingController();
  bool _redact = true;
  bool _show = false;
  bool _busy = false;
  String? _status;
  bool _ok = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    _key.text = await Gemini.apiKey();
    _model.text = await Gemini.model();
    _redact = await Gemini.redactEnabled();
    if (mounted) setState(() {});
  }

  Future<void> _saveAll() async {
    await Gemini.setApiKey(_key.text);
    await Gemini.setModel(_model.text);
    await Gemini.setRedact(_redact);
  }

  Future<void> _test() async {
    setState(() {
      _busy = true;
      _status = null;
    });
    await _saveAll();
    try {
      final r = await Gemini.generate([
        AiMsg(true, [const AiPart.text('أجب بكلمة واحدة فقط: تم')])
      ]);
      _ok = true;
      _status = 'نجح الاتصال ✓  (${r.length > 40 ? r.substring(0, 40) : r})';
    } catch (e) {
      _ok = false;
      _status = e is AiException ? e.message : '$e';
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _models() async {
    setState(() {
      _busy = true;
      _status = null;
    });
    try {
      final list = await Gemini.listModels(_key.text);
      if (!mounted) return;
      setState(() => _busy = false);
      final m = await showModalBottomSheet<String>(
        context: context,
        builder: (ctx) => SafeArea(
          child: list.isEmpty
              ? const Padding(padding: EdgeInsets.all(24), child: Text('لا توجد موديلات متاحة'))
              : ListView(shrinkWrap: true, children: [
                  for (final n in list) ListTile(title: Text(n), onTap: () => Navigator.pop(ctx, n)),
                ]),
        ),
      );
      if (m != null) _model.text = m;
    } catch (e) {
      _ok = false;
      _status = e is AiException ? e.message : '$e';
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('إعدادات المساعد الذكي'),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text(
              '1) افتح صفحة المفتاح بحساب Google الخاص بك.\n2) اضغط Create API key وانسخ المفتاح.\n3) الصقه هنا. الخطة المجانية تكفي للاستخدام الشخصي.',
              style: TextStyle(fontSize: 12, height: 1.6)),
          TextButton.icon(
            onPressed: () => launchUrl(Uri.parse('https://aistudio.google.com/apikey'),
                mode: LaunchMode.externalApplication),
            icon: const Icon(Icons.open_in_new, size: 18),
            label: const Text('فتح صفحة المفتاح'),
          ),
          TextField(
            controller: _key,
            obscureText: !_show,
            autocorrect: false,
            enableSuggestions: false,
            textDirection: TextDirection.ltr,
            decoration: InputDecoration(
              labelText: 'مفتاح Gemini API',
              helperText: 'يُحفظ على هذا الجهاز فقط',
              suffixIcon: IconButton(
                icon: Icon(_show ? Icons.visibility_off : Icons.visibility),
                onPressed: () => setState(() => _show = !_show),
              ),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _model,
            autocorrect: false,
            textDirection: TextDirection.ltr,
            decoration: const InputDecoration(labelText: 'الموديل', helperText: 'الافتراضي: gemini-flash-latest'),
          ),
          Wrap(spacing: 8, children: [
            TextButton(onPressed: _busy ? null : _models, child: const Text('الموديلات المتاحة')),
            TextButton(onPressed: _busy ? null : _test, child: const Text('اختبار الاتصال')),
          ]),
          if (_busy) const LinearProgressIndicator(),
          if (_status != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(_status!,
                  style: TextStyle(fontSize: 12, color: _ok ? Colors.green.shade700 : Theme.of(context).colorScheme.error)),
            ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('حجب البيانات الشخصية قبل الإرسال'),
            subtitle: const Text('الأرقام القومية والهواتف والبريد وأسماء الموكلين والخصوم المسجلة', style: TextStyle(fontSize: 11)),
            value: _redact,
            onChanged: (v) => setState(() => _redact = v),
          ),
        ]),
      ),
      actions: [
        TextButton(
          onPressed: () async {
            _key.clear();
            await Gemini.setApiKey('');
            if (mounted) setState(() => _status = 'تم حذف المفتاح من الجهاز');
          },
          child: const Text('حذف المفتاح'),
        ),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('إغلاق')),
        FilledButton(
          onPressed: () async {
            await _saveAll();
            if (context.mounted) Navigator.pop(context);
          },
          child: const Text('حفظ'),
        ),
      ],
    );
  }
}
