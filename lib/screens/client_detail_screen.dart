import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/utils.dart';
import '../core/widgets.dart';
import '../data/db.dart';
import '../data/models.dart';
import 'case_detail_screen.dart';
import 'case_form_screen.dart';
import '../services/export.dart';
import 'client_form_screen.dart';
import 'finance_dialog.dart';

class ClientDetailScreen extends StatelessWidget {
  final int clientId;
  const ClientDetailScreen({super.key, required this.clientId});

  @override
  Widget build(BuildContext context) {
    return Live<Client?>(
      load: () => Db.i.client(clientId),
      builder: (c, cl) {
        if (cl == null) {
          return Scaffold(appBar: AppBar(), body: const EmptyState(icon: Icons.person_off, text: 'الموكل غير موجود'));
        }
        return DefaultTabController(
          length: 3,
          child: Scaffold(
            appBar: AppBar(
              title: Text(cl.name, style: const TextStyle(fontSize: 18)),
              actions: [
                IconButton(
                  tooltip: 'كشف حساب (PDF / نص)',
                  icon: const Icon(Icons.picture_as_pdf_outlined),
                  onPressed: () => Export.menu(c, () => Export.clientReport(clientId)),
                ),
                IconButton(
                  tooltip: 'تعديل',
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: () => Navigator.push(
                      c, MaterialPageRoute(builder: (_) => ClientFormScreen(clientId: clientId))),
                ),
                IconButton(
                  tooltip: 'حذف',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () async {
                    if (await confirm(
                        c, 'سيتم حذف الموكل وحساباته المالية. القضايا المرتبطة ستبقى بدون موكل. متابعة؟',
                        ok: 'حذف')) {
                      await Db.i.deleteClient(clientId);
                      if (c.mounted) Navigator.pop(c);
                    }
                  },
                ),
              ],
              bottom: const TabBar(tabs: [Tab(text: 'البيانات'), Tab(text: 'القضايا'), Tab(text: 'الحسابات')]),
            ),
            body: TabBarView(children: [
              _InfoTab(cl: cl),
              _CasesTab(clientId: clientId),
              _AccountTab(clientId: clientId),
            ]),
          ),
        );
      },
    );
  }
}


/// يفتح رابطًا خارجيًا (اتصال / واتساب / بريد). يتجاهل الفشل مع رسالة.
Future<void> _open(BuildContext context, Uri uri) async {
  try {
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) toast(context, 'تعذّر فتح التطبيق المناسب');
  } catch (_) {
    if (context.mounted) toast(context, 'تعذّر فتح التطبيق المناسب');
  }
}

/// يحوّل رقمًا محليًا مصريًا (01xxxxxxxxx) إلى صيغة دولية لواتساب.
String _waNumber(String raw) {
  var d = raw.replaceAll(RegExp(r'[^0-9]'), '');
  if (d.startsWith('00')) d = d.substring(2);
  if (d.startsWith('0')) d = '20${d.substring(1)}';
  return d;
}

class _InfoTab extends StatelessWidget {
  final Client cl;
  const _InfoTab({required this.cl});
  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(16), children: [
        if (cl.phone.trim().isNotEmpty || cl.email.trim().isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Wrap(spacing: 8, runSpacing: 8, children: [
              if (cl.phone.trim().isNotEmpty)
                FilledButton.icon(
                  onPressed: () => _open(context, Uri(scheme: 'tel', path: cl.phone.trim())),
                  icon: const Icon(Icons.call),
                  label: const Text('اتصال'),
                ),
              if (cl.phone.trim().isNotEmpty)
                OutlinedButton.icon(
                  onPressed: () => _open(context, Uri.parse('https://wa.me/${_waNumber(cl.phone)}')),
                  icon: const Icon(Icons.chat),
                  label: const Text('واتساب'),
                ),
              if (cl.email.trim().isNotEmpty)
                OutlinedButton.icon(
                  onPressed: () => _open(context, Uri(scheme: 'mailto', path: cl.email.trim())),
                  icon: const Icon(Icons.email_outlined),
                  label: const Text('بريد'),
                ),
            ]),
          ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(children: [
              InfoRow('الاسم', cl.name),
              InfoRow('الهاتف', cl.phone, onTap: () {
                Clipboard.setData(ClipboardData(text: cl.phone));
                toast(context, 'تم نسخ الرقم');
              }),
              InfoRow('البريد', cl.email),
              InfoRow('العنوان', cl.address),
              InfoRow('الرقم القومي', cl.nationalId),
              InfoRow('ملاحظات', cl.notes),
            ]),
          ),
        ),
      ]);
}

class _CasesTab extends StatelessWidget {
  final int clientId;
  const _CasesTab({required this.clientId});
  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.transparent,
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => Navigator.push(
              context, MaterialPageRoute(builder: (_) => CaseFormScreen(clientId: clientId))),
          icon: const Icon(Icons.add),
          label: const Text('قضية'),
        ),
        body: Live<List<LegalCase>>(
          load: () => Db.i.cases(clientId: clientId),
          builder: (c, list) => list.isEmpty
              ? const EmptyState(icon: Icons.folder_open, text: 'لا توجد قضايا لهذا الموكل')
              : ListView(padding: const EdgeInsets.fromLTRB(12, 8, 12, 88), children: [
                  for (final x in list)
                    CaseCard(
                      c: x,
                      onTap: () => Navigator.push(
                          c, MaterialPageRoute(builder: (_) => CaseDetailScreen(caseId: x.id!))),
                    ),
                ]),
        ),
      );
}

class _AccountData {
  final List<Payment> items;
  final Map<String, double> totals;
  final List<LegalCase> cases;
  _AccountData(this.items, this.totals, this.cases);
}

/// تبويب الحسابات: ست بطاقات إجمالية + تفصيل لكل قضية + سجل الحركات.
class _AccountTab extends StatelessWidget {
  final int clientId;
  const _AccountTab({required this.clientId});

  Future<_AccountData> _load() async => _AccountData(
        await Db.i.payments(clientId),
        await Db.i.clientTotals(clientId),
        await Db.i.cases(clientId: clientId),
      );

  /// قائمة اختيار نوع الحركة ثم نافذة التسجيل.
  void _pickKind(BuildContext context, List<LegalCase> cases) {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          for (final e in moneyKinds.entries)
            ListTile(
              leading: Icon(_kindIcon(e.key)),
              title: Text(e.value),
              onTap: () {
                Navigator.pop(ctx);
                showPaymentDialog(context, clientId: clientId, kind: e.key, cases: cases);
              },
            ),
        ]),
      ),
    );
  }

  IconData _kindIcon(String k) {
    switch (k) {
      case 'fee':
        return Icons.request_quote_outlined;
      case 'payment':
        return Icons.arrow_downward;
      case 'deposit':
        return Icons.savings_outlined;
    }
    return Icons.receipt_long_outlined;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async => _pickKind(context, await Db.i.cases(clientId: clientId)),
        icon: const Icon(Icons.add),
        label: const Text('حركة مالية'),
      ),
      body: Live<_AccountData>(
        load: _load,
        builder: (c, d) {
          // تجميع الحركات حسب القضية للتفصيل
          final byCase = <int, List<Payment>>{};
          for (final p in d.items) {
            if (p.caseId != null) byCase.putIfAbsent(p.caseId!, () => []).add(p);
          }
          return ListView(padding: const EdgeInsets.fromLTRB(12, 8, 12, 96), children: [
            FinanceStats(d.totals),
            const Padding(
              padding: EdgeInsets.fromLTRB(4, 0, 4, 4),
              child: Text('رصيد الأمانات = الأمانات المستلمة − المصروفات القضائية',
                  style: TextStyle(fontSize: 11)),
            ),
            if (byCase.isNotEmpty) ...[
              const SectionTitle('تفصيل حسب القضية'),
              for (final cs in d.cases.where((x) => byCase.containsKey(x.id)))
                Builder(builder: (_) {
                  double sum(String k) => byCase[cs.id]!.where((p) => p.kind == k).fold(0.0, (a, p) => a + p.amount);
                  final fee = sum('fee'), paid = sum('payment'), dep = sum('deposit'), exp = sum('expense');
                  return Card(
                    child: ListTile(
                      title: Text(caseLabel(cs.number, cs.year)),
                      subtitle: Text('أتعاب ${fmtMoney(fee)} • مدفوع ${fmtMoney(paid)} • متبقي ${fmtMoney(fee - paid)}\n'
                          'أمانات ${fmtMoney(dep)} • مصروفات ${fmtMoney(exp)} • رصيد ${fmtMoney(dep - exp)}'),
                      isThreeLine: true,
                      onTap: () => Navigator.push(
                          c, MaterialPageRoute(builder: (_) => CaseDetailScreen(caseId: cs.id!))),
                    ),
                  );
                }),
            ],
            const SectionTitle('سجل الحركات'),
            if (d.items.isEmpty)
              const Padding(padding: EdgeInsets.all(16), child: Text('لا توجد حركات مالية'))
            else
              for (final p in d.items)
                Card(
                  child: ListTile(
                    leading: Icon(_kindIcon(p.kind)),
                    title: Text('${moneyKinds[p.kind] ?? p.kind}: ${fmtMoney(p.amount)}'),
                    subtitle: Text([fmtShort(p.date), p.caseLabelText, p.note].where((e) => e.isNotEmpty).join(' • ')),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () async {
                        if (await confirm(c, 'حذف هذه الحركة؟', ok: 'حذف')) await Db.i.deletePayment(p.id!);
                      },
                    ),
                  ),
                ),
          ]);
        },
      ),
    );
  }
}
