import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';

import '../core/utils.dart';
import '../core/widgets.dart';
import '../data/db.dart';
import '../data/models.dart';
import '../features/courts_directory/presentation/courts_screen.dart';
import '../features/links/links_screen.dart';
import '../services/downloader.dart';
import '../services/security.dart';
import 'ai_screen.dart';
import 'library_file_screen.dart';

/// المكتبة القانونية: تبويب "النماذج" (نصوص قابلة للتعديل) وتبويب "الملفات" (PDF / Word من الهاتف).
class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});
  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this)..addListener(_onTab);
  String _q = '';
  String? _cat;
  bool _uploading = false;

  void _onTab() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  /// يرفع ملفات PDF / Word من ذاكرة الهاتف أو التنزيلات أو المتصفح (عبر منتقي ملفات النظام).
  Future<void> _upload() async {
    final res = await Security.guard(() => FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: const ['pdf', 'doc', 'docx'],
          allowMultiple: true,
        ));
    if (res == null || res.files.isEmpty) return;
    setState(() => _uploading = true);
    var ok = 0, skipped = 0;
    for (final f in res.files) {
      final path = f.path;
      if (path == null) {
        skipped++;
        continue;
      }
      final ext = p.extension(path).replaceFirst('.', '').toLowerCase();
      final size = await File(path).length();
      if (!const ['pdf', 'doc', 'docx'].contains(ext) || size > 25 * 1024 * 1024) {
        skipped++;
        continue;
      }
      final name = await AppFiles.saveCopy(path);
      await Db.i.saveLibraryFile(LibraryFile(
        title: p.basenameWithoutExtension(f.name),
        category: _cat ?? 'أخرى',
        file: name,
        ext: ext,
        size: size,
      ));
      ok++;
    }
    if (!mounted) return;
    setState(() => _uploading = false);
    toast(context, skipped == 0 ? 'تم رفع $ok ملف' : 'تم رفع $ok ملف، وتجاهل $skipped (النوع غير مدعوم أو أكبر من 25 ميجا)');
  }

  /// رفع ملف من رابط مباشر (PDF / Word).
  Future<void> _fromUrl() async {
    final url = TextEditingController();
    final title = TextEditingController();
    final ref = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('إضافة ملف من رابط'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
                controller: url,
                keyboardType: TextInputType.url,
                textDirection: TextDirection.ltr,
                decoration: dec('رابط الملف (PDF أو Word مباشر)', icon: Icons.link)),
            const SizedBox(height: 10),
            TextField(controller: title, decoration: dec('العنوان (اختياري)')),
            const SizedBox(height: 10),
            TextField(controller: ref, decoration: dec('رقم الطعن / المرجع (اختياري)')),
            const SizedBox(height: 8),
            Text('يحتاج إنترنت أثناء التنزيل فقط، ثم يُحفظ الملف على الهاتف ويعمل بدون إنترنت.',
                style: TextStyle(fontSize: 12, color: Theme.of(ctx).colorScheme.outline)),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('تنزيل')),
        ],
      ),
    );
    if (ok != true || url.text.trim().isEmpty) return;
    setState(() => _uploading = true);
    try {
      final r = await Downloader.fetch(url.text);
      await Db.i.saveLibraryFile(LibraryFile(
        title: title.text.trim().isEmpty ? r.suggestedTitle : title.text.trim(),
        category: _cat ?? 'أخرى',
        ref: ref.text.trim(),
        file: r.file,
        ext: r.ext,
        size: r.size,
      ));
      if (mounted) toast(context, 'تم تنزيل الملف وحفظه في المكتبة');
    } catch (e) {
      if (mounted) toast(context, e.toString());
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  void _addFileMenu() {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.phone_android),
            title: const Text('رفع من الهاتف'),
            onTap: () {
              Navigator.pop(ctx);
              _upload();
            },
          ),
          ListTile(
            leading: const Icon(Icons.link),
            title: const Text('إضافة من رابط موقع'),
            onTap: () {
              Navigator.pop(ctx);
              _fromUrl();
            },
          ),
        ]),
      ),
    );
  }

  Future<void> _editFile(LibraryFile f) async {
    final title = TextEditingController(text: f.title);
    final note = TextEditingController(text: f.note);
    final ref = TextEditingController(text: f.ref);
    final principle = TextEditingController(text: f.principle);
    var cat = templateCategories.contains(f.category) ? f.category : templateCategories.last;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: const Text('بيانات الملف'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: title, decoration: dec('العنوان')),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                value: cat,
                decoration: dec('التصنيف'),
                items: [for (final c in templateCategories) DropdownMenuItem(value: c, child: Text(c))],
                onChanged: (v) => setS(() => cat = v!),
              ),
              const SizedBox(height: 10),
              TextField(controller: ref, decoration: dec('رقم الطعن / المرجع (مثال: طعن 1234 لسنة 80 ق)')),
              const SizedBox(height: 10),
              TextField(controller: principle, decoration: dec('المبدأ / ملخص الحكم'), maxLines: 4, minLines: 1),
              const SizedBox(height: 10),
              TextField(controller: note, decoration: dec('ملاحظات'), maxLines: 3, minLines: 1),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('حفظ')),
          ],
        ),
      ),
    );
    if (ok != true || title.text.trim().isEmpty) return;
    f
      ..title = title.text.trim()
      ..category = cat
      ..ref = ref.text.trim()
      ..principle = principle.text.trim()
      ..note = note.text.trim();
    await Db.i.saveLibraryFile(f);
  }

  Future<void> _fileAction(String a, LibraryFile f) async {
    switch (a) {
      case 'view':
        Navigator.push(context, MaterialPageRoute(builder: (_) => LibraryFileScreen(id: f.id!)));
        break;
      case 'ai':
        Navigator.push(context, MaterialPageRoute(builder: (_) => AiScreen(libraryFileId: f.id)));
        break;
      case 'share':
        await Security.guard(() => Share.shareXFiles([XFile(AppFiles.resolve(f.file).path)], subject: f.title));
        break;
      case 'edit':
        await _editFile(f);
        break;
      case 'delete':
        if (await confirm(context, 'حذف هذا الملف من المكتبة؟', ok: 'حذف')) await Db.i.deleteLibraryFile(f);
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final onFiles = _tabs.index == 1;
    return Scaffold(
      appBar: AppBar(
        title: const Text('المكتبة القانونية'),
        actions: [
          IconButton(
            tooltip: 'الروابط السريعة',
            icon: const Icon(Icons.link),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const LinksScreen())),
          ),
          IconButton(
            tooltip: 'دليل المحاكم',
            icon: const Icon(Icons.account_balance),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CourtsScreen())),
          ),
          IconButton(
            tooltip: 'المساعد الذكي',
            icon: const Icon(Icons.auto_awesome),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AiScreen())),
          ),
        ],
        bottom: TabBar(controller: _tabs, tabs: const [Tab(text: 'النماذج'), Tab(text: 'الملفات')]),
      ),
      floatingActionButton: onFiles
          ? FloatingActionButton.extended(
              onPressed: _uploading ? null : _addFileMenu,
              icon: _uploading
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.upload_file),
              label: const Text('إضافة ملف'),
            )
          : FloatingActionButton.extended(
              onPressed: () =>
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const TemplateFormScreen())),
              icon: const Icon(Icons.add),
              label: const Text('نموذج'),
            ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: TextField(
            decoration: InputDecoration(
                hintText: onFiles ? 'ابحث في العناوين والمبادئ وأرقام الطعون...' : 'ابحث في العناوين والنصوص...',
                prefixIcon: const Icon(Icons.search),
                isDense: true),
            onChanged: (v) => setState(() => _q = v),
          ),
        ),
        SizedBox(
          height: 48,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                child: ChoiceChip(
                    label: const Text('الكل'), selected: _cat == null, onSelected: (_) => setState(() => _cat = null)),
              ),
              for (final c in templateCategories)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                  child: ChoiceChip(
                      label: Text(c), selected: _cat == c, onSelected: (_) => setState(() => _cat = c)),
                ),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(controller: _tabs, children: [_templatesList(), _filesList()]),
        ),
      ]),
    );
  }

  Widget _templatesList() => Live<List<LegalTemplate>>(
        load: () => Db.i.templates(q: _q, category: _cat),
        builder: (c, list) => list.isEmpty
            ? const EmptyState(icon: Icons.menu_book_outlined, text: 'لا توجد نماذج')
            : ListView.builder(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 88),
                itemCount: list.length,
                itemBuilder: (_, i) => Card(
                  child: ListTile(
                    leading: const Icon(Icons.description_outlined),
                    title: Text(list[i].title),
                    subtitle: Text(list[i].category),
                    trailing: const Icon(Icons.chevron_left),
                    onTap: () => Navigator.push(
                        c, MaterialPageRoute(builder: (_) => TemplateViewScreen(id: list[i].id!))),
                  ),
                ),
              ),
      );

  Widget _filesList() => Live<List<LibraryFile>>(
        load: () => Db.i.libraryFiles(q: _q, category: _cat),
        builder: (c, list) => list.isEmpty
            ? const EmptyState(
                icon: Icons.upload_file,
                text: 'لا توجد ملفات بعد.\nاضغط "رفع ملف" لإضافة PDF أو Word من هاتفك.')
            : ListView.builder(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 88),
                itemCount: list.length,
                itemBuilder: (_, i) {
                  final f = list[i];
                  final isPdf = f.ext == 'pdf';
                  return Card(
                    child: ListTile(
                      leading: Icon(isPdf ? Icons.picture_as_pdf : Icons.description,
                          color: isPdf ? const Color(0xFFD64545) : const Color(0xFF1E88E5), size: 32),
                      title: Text(f.title, maxLines: 2, overflow: TextOverflow.ellipsis),
                      subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        if (f.ref.isNotEmpty) Text(f.ref, style: const TextStyle(fontWeight: FontWeight.w600)),
                        if (f.principle.isNotEmpty) Text(f.principle, maxLines: 2, overflow: TextOverflow.ellipsis),
                        Text([
                          f.ext.toUpperCase(),
                          fmtBytes(f.size),
                          fmtShort(DateTime.fromMillisecondsSinceEpoch(f.createdAt)),
                          f.category,
                        ].join(' • ')),
                      ]),
                      onTap: () => _fileAction('view', f),
                      trailing: PopupMenuButton<String>(
                        onSelected: (a) => _fileAction(a, f),
                        itemBuilder: (_) => [
                          const PopupMenuItem(value: 'view', child: Text('عرض')),
                          if (f.ext != 'doc') const PopupMenuItem(value: 'ai', child: Text('تلخيص / تحليل بالذكاء الاصطناعي')),
                          const PopupMenuItem(value: 'share', child: Text('مشاركة / فتح بتطبيق آخر')),
                          const PopupMenuItem(value: 'edit', child: Text('تعديل البيانات')),
                          const PopupMenuItem(value: 'delete', child: Text('حذف')),
                        ],
                      ),
                    ),
                  );
                },
              ),
      );
}

class TemplateViewScreen extends StatelessWidget {
  final int id;
  const TemplateViewScreen({super.key, required this.id});

  Future<LegalTemplate?> _load() async {
    final all = await Db.i.templates();
    for (final t in all) {
      if (t.id == id) return t;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Live<LegalTemplate?>(
      load: _load,
      builder: (c, t) {
        if (t == null) return Scaffold(appBar: AppBar(), body: const EmptyState(icon: Icons.description, text: 'غير موجود'));
        return Scaffold(
          appBar: AppBar(
            title: Text(t.title, style: const TextStyle(fontSize: 17)),
            actions: [
              IconButton(
                tooltip: 'نسخ',
                icon: const Icon(Icons.copy),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: t.body));
                  toast(c, 'تم نسخ النموذج');
                },
              ),
              IconButton(
                tooltip: 'مشاركة',
                icon: const Icon(Icons.share),
                onPressed: () => Security.guard(() => Share.share(t.body, subject: t.title)),
              ),
              IconButton(
                tooltip: 'تعديل',
                icon: const Icon(Icons.edit_outlined),
                onPressed: () => Navigator.push(
                    c, MaterialPageRoute(builder: (_) => TemplateFormScreen(template: t))),
              ),
              IconButton(
                tooltip: 'حذف',
                icon: const Icon(Icons.delete_outline),
                onPressed: () async {
                  if (await confirm(c, 'حذف هذا النموذج؟', ok: 'حذف')) {
                    await Db.i.deleteTemplate(t.id!);
                    if (c.mounted) Navigator.pop(c);
                  }
                },
              ),
            ],
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
              child: SelectableText(t.body, style: const TextStyle(fontSize: 16, height: 1.8)),
            ),
          ),
        );
      },
    );
  }
}

class TemplateFormScreen extends StatefulWidget {
  final LegalTemplate? template;
  const TemplateFormScreen({super.key, this.template});
  @override
  State<TemplateFormScreen> createState() => _TemplateFormScreenState();
}

class _TemplateFormScreenState extends State<TemplateFormScreen> {
  final _form = GlobalKey<FormState>();
  late final _title = TextEditingController(text: widget.template?.title ?? '');
  late final _body = TextEditingController(text: widget.template?.body ?? '');
  late String _cat = templateCategories.contains(widget.template?.category)
      ? widget.template!.category
      : templateCategories.last;

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final t = widget.template ?? LegalTemplate();
    t
      ..title = _title.text.trim()
      ..category = _cat
      ..body = _body.text;
    await Db.i.saveTemplate(t);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.template == null ? 'نموذج جديد' : 'تعديل النموذج'),
        actions: [IconButton(onPressed: _save, icon: const Icon(Icons.check), tooltip: 'حفظ')],
      ),
      body: Form(
        key: _form,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          tf(_title, 'عنوان النموذج', required: true),
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: DropdownButtonFormField<String>(
              value: _cat,
              decoration: dec('التصنيف'),
              items: [for (final c in templateCategories) DropdownMenuItem(value: c, child: Text(c))],
              onChanged: (v) => setState(() => _cat = v!),
            ),
          ),
          TextFormField(
            controller: _body,
            minLines: 14,
            maxLines: null,
            decoration: dec('نص النموذج'),
            validator: (v) => (v == null || v.trim().isEmpty) ? 'مطلوب' : null,
          ),
          const SizedBox(height: 16),
          FilledButton.icon(onPressed: _save, icon: const Icon(Icons.save), label: const Text('حفظ')),
        ]),
      ),
    );
  }
}
