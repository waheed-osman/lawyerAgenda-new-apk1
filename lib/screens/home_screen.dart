import 'package:flutter/material.dart';

import '../core/utils.dart';
import '../core/widgets.dart';
import '../data/db.dart';
import '../data/models.dart';
import '../services/export.dart';
import 'ai_screen.dart';
import 'appointment_form_screen.dart';
import 'case_detail_screen.dart';
import 'case_form_screen.dart';
import 'cases_screen.dart';
import 'session_form_screen.dart';
import 'settings_screen.dart';

class _HomeData {
  final Map<String, int> counts;
  final Map<String, double> money;
  final List<CaseSession> today, upcoming, overdue;
  final List<Appointment> appts; // اليوم + 7 أيام
  _HomeData(this.counts, this.money, this.today, this.upcoming, this.overdue, this.appts);
}

/// لوحة التحكم: ملخص اليوم، المواعيد الهامة، القضايا النشطة، والموقف المالي.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  Future<_HomeData> _load() async {
    final t = dayStart(DateTime.now());
    return _HomeData(
      await Db.i.counts(),
      await Db.i.overallTotals(),
      await Db.i.sessions(from: t, to: addDays(t, 1)),
      await Db.i.sessions(from: addDays(t, 1), to: addDays(t, 8)),
      await Db.i.sessions(to: t, overdueNoDecision: true, desc: true, limit: 20),
      await Db.i.appointments(from: t, to: addDays(t, 8)),
    );
  }

  void _openSession(BuildContext c, CaseSession s) => Navigator.push(
      c, MaterialPageRoute(builder: (_) => SessionFormScreen(caseId: s.caseId, sessionId: s.id)));

  void _openCase(BuildContext c, CaseSession s) =>
      Navigator.push(c, MaterialPageRoute(builder: (_) => CaseDetailScreen(caseId: s.caseId)));

  Widget _sessions(BuildContext c, List<CaseSession> l, {bool showDate = true}) => Column(
        children: l
            .map((s) => SessionTile(
                  s: s,
                  showDate: showDate,
                  onTap: () => _openSession(c, s),
                  onOpenCase: () => _openCase(c, s),
                ))
            .toList(),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('أجندة المحامي'),
        actions: [
          IconButton(
            tooltip: 'المساعد القانوني الذكي',
            icon: const Icon(Icons.auto_awesome),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AiScreen())),
          ),
          IconButton(
            tooltip: 'تصدير أجندة الأسبوع القادم',
            icon: const Icon(Icons.ios_share),
            onPressed: () {
              final t = dayStart(DateTime.now());
              Export.menu(context, () => Export.agenda(t, addDays(t, 8), 'أجندة الأيام الثمانية القادمة'));
            },
          ),
          IconButton(
            tooltip: 'الإعدادات',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () =>
                Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen())),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () =>
            Navigator.push(context, MaterialPageRoute(builder: (_) => const CaseFormScreen())),
        icon: const Icon(Icons.add),
        label: const Text('قضية جديدة'),
      ),
      body: Live<_HomeData>(
        load: _load,
        builder: (c, d) {
          final t = dayStart(DateTime.now());
          final tomorrow = addDays(t, 1);
          final todayAppts = d.appts.where((a) => dayStart(a.date) == t).toList();
          final nextAppts = d.appts.where((a) => dayStart(a.date) != t).toList();
          final tomorrowCount = d.upcoming.where((s) => dayStart(s.date) == tomorrow).length +
              nextAppts.where((a) => dayStart(a.date) == tomorrow).length;
          final todayCount = d.today.length + todayAppts.length;
          final remaining = (d.money['fee'] ?? 0) - (d.money['payment'] ?? 0);
          final active = (d.counts['active'] ?? 0) + (d.counts['postponed'] ?? 0);
          final cs = Theme.of(c).colorScheme;

          // الشاشة تتمركز بعرض أقصى مناسب للأجهزة اللوحية / الوضع الأفقي.
          return Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 820),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 96),
                children: [
                  Padding(
                    padding: const EdgeInsets.all(4),
                    child: Text(fmtDate(DateTime.now()), style: Theme.of(c).textTheme.titleSmall),
                  ),
                  // تنبيه داخل التطبيق بالمواعيد القريبة
                  if (todayCount + tomorrowCount > 0)
                    Card(
                      color: cs.tertiaryContainer,
                      child: ListTile(
                        leading: Icon(Icons.notifications_active, color: cs.onTertiaryContainer),
                        title: Text(
                          [
                            if (todayCount > 0) 'اليوم: $todayCount ${todayCount == 1 ? 'جلسة/موعد' : 'جلسات ومواعيد'}',
                            if (tomorrowCount > 0) 'غدًا: $tomorrowCount',
                          ].join('  •  '),
                          style: TextStyle(fontWeight: FontWeight.bold, color: cs.onTertiaryContainer),
                        ),
                      ),
                    ),
                  const SizedBox(height: 4),
                  Row(children: [
                    for (final e in caseStatuses.entries)
                      Expanded(
                        child: Card(
                          child: InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: () => Navigator.push(
                                c, MaterialPageRoute(builder: (_) => CasesScreen(initialStatus: e.key))),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              child: Column(children: [
                                Text('${d.counts[e.key] ?? 0}',
                                    style: TextStyle(
                                        fontSize: 24, fontWeight: FontWeight.bold, color: statusColor(e.key))),
                                const SizedBox(height: 2),
                                Text(e.value, style: const TextStyle(fontSize: 12)),
                              ]),
                            ),
                          ),
                        ),
                      ),
                  ]),
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.account_balance_wallet_outlined),
                      title: Text('المتبقي من الأتعاب: ${fmtMoney(remaining)}'),
                      subtitle: Text('قضايا نشطة ومؤجلة: $active'),
                    ),
                  ),
                  SectionTitle('جلسات اليوم (${d.today.length})'),
                  if (d.today.isEmpty)
                    const Padding(padding: EdgeInsets.all(12), child: Text('لا توجد جلسات اليوم'))
                  else
                    _sessions(c, d.today, showDate: false),
                  if (todayAppts.isNotEmpty) ...[
                    const SectionTitle('مواعيد اليوم'),
                    for (final a in todayAppts)
                      AppointmentTile(
                        a: a,
                        showDate: false,
                        onTap: () => Navigator.push(
                            c, MaterialPageRoute(builder: (_) => AppointmentFormScreen(appointmentId: a.id))),
                      ),
                  ],
                  if (d.overdue.isNotEmpty) ...[
                    const SectionTitle('جلسات سابقة بدون قرار مسجّل'),
                    _sessions(c, d.overdue),
                  ],
                  SectionTitle('جلسات عاجلة - الأيام السبعة القادمة (${d.upcoming.length})'),
                  if (d.upcoming.isEmpty)
                    const Padding(padding: EdgeInsets.all(12), child: Text('لا توجد جلسات قادمة خلال أسبوع'))
                  else
                    _sessions(c, d.upcoming),
                  SectionTitle('مواعيد هامة قادمة (${nextAppts.length})',
                      trailing: TextButton.icon(
                        onPressed: () => Navigator.push(
                            c, MaterialPageRoute(builder: (_) => const AppointmentFormScreen())),
                        icon: const Icon(Icons.add),
                        label: const Text('موعد / ميعاد'),
                      )),
                  if (nextAppts.isEmpty)
                    const Padding(padding: EdgeInsets.all(12), child: Text('لا توجد مواعيد قادمة'))
                  else
                    for (final a in nextAppts)
                      AppointmentTile(
                        a: a,
                        onTap: () => Navigator.push(
                            c, MaterialPageRoute(builder: (_) => AppointmentFormScreen(appointmentId: a.id))),
                      ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
