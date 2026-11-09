import 'package:flutter/material.dart';

import '../core/grouped_cases.dart';
import '../core/utils.dart';
import '../core/widgets.dart';
import '../data/db.dart';
import '../data/models.dart';
import 'case_detail_screen.dart';
import '../services/export.dart';
import 'case_form_screen.dart';

class CasesScreen extends StatefulWidget {
  final String? initialStatus;
  const CasesScreen({super.key, this.initialStatus});
  @override
  State<CasesScreen> createState() => _CasesScreenState();
}

class _CasesScreenState extends State<CasesScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  final _search = TextEditingController();
  String _q = '';
  String? _type;
  bool _grouped = false;

  static const _keys = <String?>[null, 'active', 'postponed', 'won', 'lost'];

  @override
  void initState() {
    super.initState();
    final idx = _keys.indexOf(widget.initialStatus);
    _tabs = TabController(length: _keys.length, vsync: this, initialIndex: idx < 0 ? 0 : idx);
  }

  @override
  void dispose() {
    _tabs.dispose();
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('القضايا'),
        actions: [
          IconButton(
            tooltip: _grouped ? 'عرض كقائمة عادية' : 'تجميع حسب الموكل',
            icon: Icon(_grouped ? Icons.view_list : Icons.account_tree_outlined),
            onPressed: () => setState(() => _grouped = !_grouped),
          ),
          IconButton(
            tooltip: 'تصدير القائمة الحالية (PDF / نص)',
            icon: const Icon(Icons.picture_as_pdf_outlined),
            onPressed: () => Export.menu(context, () async {
              final k = _keys[_tabs.index];
              final list = await Db.i.cases(status: k, q: _q, type: _type);
              final name = k == null ? 'كل القضايا' : 'القضايا ${caseStatuses[k]}';
              return Export.casesList(list, 'قائمة $name');
            }),
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: const [
            Tab(text: 'الكل'),
            Tab(text: 'جارية'),
            Tab(text: 'مؤجلة'),
            Tab(text: 'مكتسبة'),
            Tab(text: 'خاسرة'),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: 'قضية جديدة',
        onPressed: () =>
            Navigator.push(context, MaterialPageRoute(builder: (_) => const CaseFormScreen())),
        child: const Icon(Icons.add),
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: Row(children: [
            Expanded(
              child: TextField(
                controller: _search,
                decoration: InputDecoration(
                  hintText: 'بحث: رقم، موكل، خصم، محكمة...',
                  prefixIcon: const Icon(Icons.search),
                  isDense: true,
                  suffixIcon: _q.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => setState(() {
                            _search.clear();
                            _q = '';
                          })),
                ),
                onChanged: (v) => setState(() => _q = v),
              ),
            ),
            const SizedBox(width: 8),
            PopupMenuButton<String?>(
              tooltip: 'تصفية بالنوع',
              icon: Icon(_type == null ? Icons.filter_list : Icons.filter_alt),
              onSelected: (v) => setState(() => _type = v == '' ? null : v),
              itemBuilder: (_) => [
                const PopupMenuItem(value: '', child: Text('كل الأنواع')),
                for (final t in caseTypes) PopupMenuItem(value: t, child: Text(t)),
              ],
            ),
          ]),
        ),
        if (_type != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: InputChip(label: Text('النوع: $_type'), onDeleted: () => setState(() => _type = null)),
            ),
          ),
        Expanded(
          child: TabBarView(
            controller: _tabs,
            children: [
              for (final k in _keys)
                Live<List<LegalCase>>(
                  load: () => Db.i.cases(status: k, q: _q, type: _type),
                  builder: (c, list) => list.isEmpty
                      ? const EmptyState(icon: Icons.folder_off_outlined, text: 'لا توجد قضايا')
                      : _grouped
                          ? groupedCasesList(list,
                              onOpen: (x) => Navigator.push(
                                  c, MaterialPageRoute(builder: (_) => CaseDetailScreen(caseId: x.id!))))
                          : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(12, 4, 12, 88),
                          itemCount: list.length,
                          itemBuilder: (_, i) => CaseCard(
                            c: list[i],
                            onTap: () => Navigator.push(
                                c, MaterialPageRoute(builder: (_) => CaseDetailScreen(caseId: list[i].id!))),
                          ),
                        ),
                ),
            ],
          ),
        ),
      ]),
    );
  }
}
