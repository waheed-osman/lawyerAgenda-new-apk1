import 'package:flutter/material.dart';

import '../features/delegation/delegation_screen.dart';
import '../core/utils.dart';
import '../core/widgets.dart';
import '../data/db.dart';
import '../data/models.dart';
import 'attachments_view.dart';
import 'ai_screen.dart';
import 'case_form_screen.dart';
import '../services/export.dart';
import 'client_detail_screen.dart';
import 'documents_tab.dart';
import 'finance_dialog.dart';
import 'session_form_screen.dart';

class CaseDetailScreen extends StatelessWidget {
  final int caseId;
  const CaseDetailScreen({super.key, required this.caseId});

  @override
  Widget build(BuildContext context) {
    return Live<LegalCase?>(
      load: () => Db.i.legalCase(caseId),
      builder: (c, cs) {
        if (cs == null) {
          return Scaffold(appBar: AppBar(), body: const EmptyState(icon: Icons.folder_off, text: 'القضية غير موجودة'));
        }
        return DefaultTabController(
          length: 5,
          child: Scaffold(
            appBar: AppBar(
              title: Text(caseLabel(cs.number, cs.year), style: const TextStyle(fontSize: 18)),
              actions: [
                IconButton(
                  tooltip: 'اسأل المساعد الذكي عن القضية',
                  icon: const Icon(Icons.auto_awesome),
                  onPressed: () =>
                      Navigator.push(c, MaterialPageRoute(builder: (_) => AiScreen(caseId: caseId))),
                ),
                IconButton(
                  tooltip: 'نموذج إنابة (طباعة / واتساب)',
                  icon: const Icon(Icons.assignment_ind_outlined),
                  onPressed: () => Navigator.push(
                      c, MaterialPageRoute(builder: (_) => DelegationScreen(caseId: caseId))),
                ),
                IconButton(
                  tooltip: 'تقرير القضية (PDF / نص)',
                  icon: const Icon(Icons.picture_as_pdf_outlined),
                  onPressed: () => Export.menu(c, () => Export.caseReport(caseId)),
                ),
                IconButton(
                  tooltip: 'تعديل',
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: () => Navigator.push(
                      c, MaterialPageRoute(builder: (_) => CaseFormScreen(caseId: caseId))),
                ),
                IconButton(
                  tooltip: 'حذف',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () async {
                    if (await confirm(c, 'سيتم حذف القضية وجلساتها ومرفقاتها نهائيًا. متابعة؟', ok: 'حذف')) {
                      await Db.i.deleteCase(caseId);
                      if (c.mounted) Navigator.pop(c);
                    }
                  },
                ),
              ],
              bottom: const TabBar(isScrollable: true, tabAlignment: TabAlignment.start, tabs: [
                Tab(text: 'البيانات'),
                Tab(text: 'الجلسات'),
                Tab(text: 'المذكرات'),
                Tab(text: 'السجل'),
                Tab(text: 'المستندات'),
              ]),
            ),
            body: TabBarView(children: [
              _InfoTab(cs: cs),
              _SessionsTab(caseId: caseId),
              CaseDocumentsTab(caseId: caseId),
              _HistoryTab(caseId: caseId),
              ListView(padding: const EdgeInsets.all(16), children: [AttachmentsView(caseId: caseId)]),
            ]),
          ),
        );
      },
    );
  }
}

class _InfoTab extends StatelessWidget {
  final LegalCase cs;
  const _InfoTab({required this.cs});

  @override
  Widget build(BuildContext context) {
    return ListView(padding: const EdgeInsets.all(16), children: [
      Wrap(spacing: 8, children: [
        for (final e in caseStatuses.entries)
          ChoiceChip(
            label: Text(e.value),
            selected: cs.status == e.key,
            selectedColor: statusColor(e.key).withOpacity(.25),
            onSelected: (_) => Db.i.setCaseStatus(cs.id!, e.key),
          ),
      ]),
      const SizedBox(height: 12),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(children: [
            InfoRow('رقم القضية', '${cs.number} لسنة ${cs.year}'),
            InfoRow('المحكمة', cs.court),
            InfoRow('الدائرة', cs.circuit),
            InfoRow('النوع', cs.type),
            InfoRow('الموضوع', cs.title),
            InfoRow('الموكل', cs.clientName,
                onTap: cs.clientId == null
                    ? null
                    : () => Navigator.push(context,
                        MaterialPageRoute(builder: (_) => ClientDetailScreen(clientId: cs.clientId!)))),
            InfoRow('صفة الموكل', cs.clientRole),
            InfoRow('الخصم', cs.opponent),
          ]),
        ),
      ),
      if (cs.clientId != null) _CaseFinance(cs: cs),
      if (cs.notes.trim().isNotEmpty) ...[
        const SectionTitle('ملاحظات'),
        Card(child: Padding(padding: const EdgeInsets.all(14), child: SizedBox(width: double.infinity, child: Text(cs.notes)))),
      ],
    ]);
  }
}

class _SessionsTab extends StatelessWidget {
  final int caseId;
  const _SessionsTab({required this.caseId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.push(
            context, MaterialPageRoute(builder: (_) => SessionFormScreen(caseId: caseId))),
        icon: const Icon(Icons.add),
        label: const Text('جلسة'),
      ),
      body: Live<List<CaseSession>>(
        load: () => Db.i.sessions(caseId: caseId, desc: true),
        builder: (c, list) => list.isEmpty
            ? const EmptyState(icon: Icons.event_busy, text: 'لا توجد جلسات مسجلة لهذه القضية')
            : ListView(padding: const EdgeInsets.fromLTRB(12, 8, 12, 88), children: [
                for (final s in list)
                  SessionTile(
                    s: s,
                    onTap: () => Navigator.push(c,
                        MaterialPageRoute(builder: (_) => SessionFormScreen(caseId: caseId, sessionId: s.id))),
                  ),
              ]),
      ),
    );
  }
}

class _Entry {
  final DateTime date;
  final String text;
  final String tag;
  final HistoryEntry? note;
  _Entry(this.date, this.text, this.tag, this.note);
}

class _HistoryTab extends StatelessWidget {
  final int caseId;
  const _HistoryTab({required this.caseId});

  Future<List<_Entry>> _load() async {
    final notes = await Db.i.history(caseId);
    final sessions = await Db.i.sessions(caseId: caseId);
    final all = <_Entry>[
      for (final n in notes) _Entry(n.date, n.text, 'ملاحظة', n),
      for (final s in sessions)
        if (s.decision.trim().isNotEmpty)
          _Entry(s.date, s.decision, 'قرار جلسة (${sessionTypes[s.type] ?? ''})', null),
    ];
    all.sort((a, b) => b.date.compareTo(a.date));
    return all;
  }

  Future<void> _add(BuildContext context) async {
    final ctrl = TextEditingController();
    var date = dayStart(DateTime.now());
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: const Text('إضافة للسجل'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextButton.icon(
              icon: const Icon(Icons.event),
              label: Text(fmtShort(date)),
              onPressed: () async {
                final d = await pickDate(ctx, date);
                if (d != null) setS(() => date = dayStart(d));
              },
            ),
            TextField(controller: ctrl, maxLines: 5, decoration: dec('النص')),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
            FilledButton(
              onPressed: () async {
                if (ctrl.text.trim().isNotEmpty) {
                  await Db.i.saveHistory(HistoryEntry(caseId: caseId, date: date, text: ctrl.text.trim()));
                }
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text('حفظ'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _add(context),
        icon: const Icon(Icons.note_add_outlined),
        label: const Text('ملاحظة'),
      ),
      body: Live<List<_Entry>>(
        load: _load,
        builder: (c, list) => list.isEmpty
            ? const EmptyState(icon: Icons.history, text: 'لا يوجد سجل بعد')
            : ListView.builder(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 88),
                itemCount: list.length,
                itemBuilder: (_, i) {
                  final e = list[i];
                  return Card(
                    child: ListTile(
                      title: Text(e.text),
                      subtitle: Text('${fmtShort(e.date)} • ${e.tag}'),
                      trailing: e.note == null
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.delete_outline),
                              onPressed: () async {
                                if (await confirm(c, 'حذف هذه الملاحظة؟', ok: 'حذف')) {
                                  await Db.i.deleteHistory(e.note!.id!);
                                }
                              },
                            ),
                    ),
                  );
                },
              ),
      ),
    );
  }
}


/// الموقف المالي للقضية (أتعاب / أمانات / مصروفات) مع زر تسجيل حركة.
class _CaseFinance extends StatelessWidget {
  final LegalCase cs;
  const _CaseFinance({required this.cs});

  @override
  Widget build(BuildContext context) {
    return Live<Map<String, double>>(
      load: () => Db.i.caseTotals(cs.id!),
      builder: (c, t) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SectionTitle(
          'الموقف المالي للقضية',
          trailing: TextButton.icon(
            onPressed: () {
              showModalBottomSheet<void>(
                context: c,
                builder: (ctx) => SafeArea(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    for (final e in moneyKinds.entries)
                      ListTile(
                        title: Text(e.value),
                        onTap: () {
                          Navigator.pop(ctx);
                          showPaymentDialog(c,
                              clientId: cs.clientId!, kind: e.key, cases: [cs], caseId: cs.id);
                        },
                      ),
                  ]),
                ),
              );
            },
            icon: const Icon(Icons.add),
            label: const Text('حركة'),
          ),
        ),
        FinanceStats(t),
      ]),
    );
  }
}
