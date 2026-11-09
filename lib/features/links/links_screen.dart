import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/utils.dart';
import '../../core/widgets.dart';
import '../../data/db.dart';

const linkCategories = ['المحاكم والجهات الرسمية', 'منصات التواصل الاجتماعي والعمل', 'أخرى'];

class LinkItem {
  int? id;
  String title, url, category, note;
  LinkItem({this.id, this.title = '', this.url = '', this.category = 'أخرى', this.note = ''});
  factory LinkItem.fromMap(Map<String, Object?> m) => LinkItem(
        id: m['id'] as int?,
        title: (m['title'] ?? '').toString(),
        url: (m['url'] ?? '').toString(),
        category: (m['category'] ?? 'أخرى').toString(),
        note: (m['note'] ?? '').toString(),
      );
  Map<String, Object?> toMap() => {
        'id': id,
        'title': title,
        'url': url,
        'category': category,
        'note': note,
        'created_at': DateTime.now().millisecondsSinceEpoch,
      };
  Uri? get uri {
    var u = url.trim();
    if (u.isEmpty) return null;
    if (!u.startsWith('http://') && !u.startsWith('https://')) u = 'https://$u';
    final p = Uri.tryParse(u);
    return (p == null || p.host.isEmpty) ? null : p;
  }
}

class LinksRepo {
  static Future<List<LinkItem>> list({String? q}) async {
    final d = await Db.i.db;
    final hasQ = q != null && q.trim().isNotEmpty;
    final l = '%${q?.trim()}%';
    final r = await d.query('links',
        where: hasQ ? '(title LIKE ? OR url LIKE ? OR note LIKE ?)' : null,
        whereArgs: hasQ ? [l, l, l] : null,
        orderBy: 'category, title COLLATE NOCASE');
    return r.map(LinkItem.fromMap).toList();
  }

  static Future<void> save(LinkItem i) async {
    final d = await Db.i.db;
    final m = i.toMap();
    if (i.id == null) {
      m.remove('id');
      await d.insert('links', m);
    } else {
      await d.update('links', m, where: 'id=?', whereArgs: [i.id]);
    }
    Db.i.changed();
  }

  static Future<void> delete(int id) async {
    final d = await Db.i.db;
    await d.delete('links', where: 'id=?', whereArgs: [id]);
    Db.i.changed();
  }
}

/// روابط سريعة: المحاكم والجهات الرسمية، وحسابات التواصل والعمل. الفتح بمتصفح الهاتف.
class LinksScreen extends StatefulWidget {
  const LinksScreen({super.key});
  @override
  State<LinksScreen> createState() => _LinksScreenState();
}

class _LinksScreenState extends State<LinksScreen> {
  String _q = '';

  Future<void> _open(LinkItem i) async {
    final u = i.uri;
    if (u == null) {
      toast(context, 'الرابط غير صحيح');
      return;
    }
    try {
      final ok = await launchUrl(u, mode: LaunchMode.externalApplication);
      if (!ok && mounted) toast(context, 'تعذّر فتح الرابط');
    } catch (_) {
      if (mounted) toast(context, 'تعذّر فتح الرابط');
    }
  }

  Future<void> _edit([LinkItem? item]) async {
    final i = item ?? LinkItem(category: linkCategories.first);
    final title = TextEditingController(text: i.title);
    final url = TextEditingController(text: i.url);
    final note = TextEditingController(text: i.note);
    var cat = linkCategories.contains(i.category) ? i.category : linkCategories.last;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: Text(item == null ? 'رابط جديد' : 'تعديل الرابط'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: title, decoration: dec('اسم الجهة / المنصة')),
              const SizedBox(height: 10),
              TextField(
                  controller: url,
                  keyboardType: TextInputType.url,
                  textDirection: TextDirection.ltr,
                  decoration: dec('الرابط (URL)', icon: Icons.link)),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                value: cat,
                isExpanded: true,
                decoration: dec('التصنيف'),
                items: [for (final c in linkCategories) DropdownMenuItem(value: c, child: Text(c))],
                onChanged: (v) => setS(() => cat = v!),
              ),
              const SizedBox(height: 10),
              TextField(controller: note, decoration: dec('ملاحظات (اختياري)'), maxLines: 2, minLines: 1),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('حفظ')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    if (title.text.trim().isEmpty || url.text.trim().isEmpty) {
      if (mounted) toast(context, 'اكتب الاسم والرابط');
      return;
    }
    i
      ..title = title.text.trim()
      ..url = url.text.trim()
      ..category = cat
      ..note = note.text.trim();
    await LinksRepo.save(i);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('الروابط السريعة')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(),
        icon: const Icon(Icons.add_link),
        label: const Text('رابط'),
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: TextField(
            decoration: const InputDecoration(hintText: 'بحث...', prefixIcon: Icon(Icons.search), isDense: true),
            onChanged: (v) => setState(() => _q = v),
          ),
        ),
        Expanded(
          child: Live<List<LinkItem>>(
            load: () => LinksRepo.list(q: _q),
            builder: (c, list) {
              if (list.isEmpty) return const EmptyState(icon: Icons.link_off, text: 'لا توجد روابط');
              final cats = <String>[
                ...linkCategories.where((k) => list.any((x) => x.category == k)),
                ...list.map((x) => x.category).where((k) => !linkCategories.contains(k)).toSet(),
              ];
              return ListView(padding: const EdgeInsets.fromLTRB(12, 4, 12, 88), children: [
                for (final k in cats) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 12, 4, 4),
                    child: Text(k, style: TextStyle(fontWeight: FontWeight.w700, color: Theme.of(c).colorScheme.primary)),
                  ),
                  for (final i in list.where((x) => x.category == k))
                    Card(
                      child: ListTile(
                        leading: const Icon(Icons.public),
                        title: Text(i.title),
                        subtitle: Text(i.note.isEmpty ? i.url : '${i.url}\n${i.note}',
                            maxLines: 2, overflow: TextOverflow.ellipsis, textDirection: TextDirection.ltr),
                        isThreeLine: i.note.isNotEmpty,
                        onTap: () => _open(i),
                        trailing: PopupMenuButton<String>(
                          onSelected: (a) async {
                            if (a == 'open') {
                              _open(i);
                            } else if (a == 'edit') {
                              _edit(i);
                            } else if (a == 'delete' && await confirm(c, 'حذف هذا الرابط؟', ok: 'حذف')) {
                              await LinksRepo.delete(i.id!);
                            }
                          },
                          itemBuilder: (_) => const [
                            PopupMenuItem(value: 'open', child: Text('فتح')),
                            PopupMenuItem(value: 'edit', child: Text('تعديل')),
                            PopupMenuItem(value: 'delete', child: Text('حذف')),
                          ],
                        ),
                      ),
                    ),
                ],
              ]);
            },
          ),
        ),
      ]),
    );
  }
}
