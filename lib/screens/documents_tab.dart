import 'package:flutter/material.dart';

import '../core/utils.dart';
import '../core/widgets.dart';
import '../data/db.dart';
import '../data/models.dart';
import 'document_form_screen.dart';

/// تبويب "المذكرات" داخل شاشة القضية: قائمة مصنّفة وقابلة للبحث.
class CaseDocumentsTab extends StatefulWidget {
  final int caseId;
  const CaseDocumentsTab({super.key, required this.caseId});
  @override
  State<CaseDocumentsTab> createState() => _CaseDocumentsTabState();
}

class _CaseDocumentsTabState extends State<CaseDocumentsTab> {
  String _q = '';
  String? _cat;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.push(
            context, MaterialPageRoute(builder: (_) => DocumentFormScreen(caseId: widget.caseId))),
        icon: const Icon(Icons.post_add),
        label: const Text('مذكرة'),
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: TextField(
            decoration: const InputDecoration(
                hintText: 'بحث في المذكرات...', prefixIcon: Icon(Icons.search), isDense: true),
            onChanged: (v) => setState(() => _q = v),
          ),
        ),
        SizedBox(
          height: 48,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                child: ChoiceChip(
                    label: const Text('الكل'), selected: _cat == null, onSelected: (_) => setState(() => _cat = null)),
              ),
              for (final c in docCategories)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                  child: ChoiceChip(label: Text(c), selected: _cat == c, onSelected: (_) => setState(() => _cat = c)),
                ),
            ],
          ),
        ),
        Expanded(
          child: Live<List<CaseDocument>>(
            load: () => Db.i.documents(widget.caseId, category: _cat, q: _q),
            builder: (c, list) => list.isEmpty
                ? const EmptyState(icon: Icons.description_outlined, text: 'لا توجد مذكرات بعد.\nاضغط "مذكرة" لتدوين مسودة دفاع أو طعن.')
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 88),
                    itemCount: list.length,
                    itemBuilder: (_, i) {
                      final d = list[i];
                      return Card(
                        child: ListTile(
                          leading: const Icon(Icons.article_outlined),
                          title: Text(d.title),
                          subtitle: Text(
                            '${d.category} • ${fmtShort(DateTime.fromMillisecondsSinceEpoch(d.updatedAt))}'
                            '${d.body.trim().isEmpty ? '' : '\n${d.body.trim()}'}',
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                          ),
                          isThreeLine: d.body.trim().isNotEmpty,
                          onTap: () => Navigator.push(
                              c,
                              MaterialPageRoute(
                                  builder: (_) => DocumentFormScreen(caseId: widget.caseId, docId: d.id))),
                        ),
                      );
                    },
                  ),
          ),
        ),
      ]),
    );
  }
}
