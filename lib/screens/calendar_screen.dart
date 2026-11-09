import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';

import '../core/utils.dart';
import '../core/widgets.dart';
import '../data/db.dart';
import '../data/models.dart';
import '../services/export.dart';
import 'appointment_form_screen.dart';
import 'case_detail_screen.dart';
import 'session_form_screen.dart';

class _CalData {
  final List<CaseSession> sessions;
  final List<Appointment> appts;
  _CalData(this.sessions, this.appts);
}

/// الأجندة: تقويم تفاعلي للجلسات (بألوان حسب النوع) والمواعيد العامة.
class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});
  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  DateTime _focused = DateTime.now();
  DateTime _selected = dayStart(DateTime.now());
  CalendarFormat _format = CalendarFormat.month;

  Future<void> _chooseCaseAndAddSession() async {
    final cases = await Db.i.cases();
    if (!mounted) return;
    if (cases.isEmpty) {
      toast(context, 'أضف قضية أولًا');
      return;
    }
    final chosen = await showModalBottomSheet<LegalCase>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: .6,
        builder: (_, sc) => Column(children: [
          const Padding(
              padding: EdgeInsets.all(16),
              child: Text('اختر القضية', style: TextStyle(fontWeight: FontWeight.bold))),
          Expanded(
            child: ListView.builder(
              controller: sc,
              itemCount: cases.length,
              itemBuilder: (_, i) => ListTile(
                title: Text(caseLabel(cases[i].number, cases[i].year)),
                subtitle: Text([cases[i].clientName, cases[i].court].where((e) => e.isNotEmpty).join(' • ')),
                onTap: () => Navigator.pop(ctx, cases[i]),
              ),
            ),
          ),
        ]),
      ),
    );
    if (chosen != null && mounted) {
      Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => SessionFormScreen(caseId: chosen.id!, initialDate: _selected)));
    }
  }

  void _add() {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.gavel),
            title: const Text('جلسة لقضية'),
            onTap: () {
              Navigator.pop(ctx);
              _chooseCaseAndAddSession();
            },
          ),
          ListTile(
            leading: const Icon(Icons.event_note, color: appointmentColor),
            title: const Text('موعد / ميعاد قانوني (شهادة، معارضة، استئناف...)'),
            onTap: () {
              Navigator.pop(ctx);
              Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => AppointmentFormScreen(initialDate: _selected)));
            },
          ),
        ]),
      ),
    );
  }

  Color _markerColor(Object e) => e is CaseSession ? sessionColor(e.type) : (e is Appointment ? apptKind(e.kind).color : appointmentColor);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('الأجندة'),
        actions: [
          IconButton(
            tooltip: 'تصدير أجندة الشهر',
            icon: const Icon(Icons.ios_share),
            onPressed: () => Export.menu(
              context,
              () => Export.agenda(DateTime(_focused.year, _focused.month, 1),
                  DateTime(_focused.year, _focused.month + 1, 1), 'أجندة شهر ${_focused.month}/${_focused.year}'),
            ),
          ),
          IconButton(
            tooltip: 'اليوم',
            icon: const Icon(Icons.today),
            onPressed: () => setState(() {
              _focused = DateTime.now();
              _selected = dayStart(DateTime.now());
            }),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _add,
        icon: const Icon(Icons.add),
        label: const Text('إضافة'),
      ),
      body: Live<_CalData>(
        load: () async => _CalData(await Db.i.sessions(), await Db.i.appointments()),
        builder: (c, data) {
          final sBy = <DateTime, List<CaseSession>>{};
          for (final s in data.sessions) {
            sBy.putIfAbsent(dayStart(s.date), () => []).add(s);
          }
          final aBy = <DateTime, List<Appointment>>{};
          for (final a in data.appts) {
            aBy.putIfAbsent(dayStart(a.date), () => []).add(a);
          }
          final daySessions = sBy[_selected] ?? const <CaseSession>[];
          final dayAppts = aBy[_selected] ?? const <Appointment>[];
          return ListView(padding: const EdgeInsets.only(bottom: 96), children: [
            Card(
              margin: const EdgeInsets.all(12),
              child: TableCalendar<Object>(
                locale: 'ar',
                firstDay: DateTime(2000),
                lastDay: DateTime(2100),
                focusedDay: _focused,
                calendarFormat: _format,
                availableCalendarFormats: const {CalendarFormat.month: 'شهر', CalendarFormat.week: 'أسبوع'},
                startingDayOfWeek: StartingDayOfWeek.saturday,
                selectedDayPredicate: (d) => isSameDay(d, _selected),
                eventLoader: (d) => <Object>[...(sBy[dayStart(d)] ?? const []), ...(aBy[dayStart(d)] ?? const [])],
                onDaySelected: (sel, foc) => setState(() {
                  _selected = dayStart(sel);
                  _focused = foc;
                }),
                onFormatChanged: (f) => setState(() => _format = f),
                onPageChanged: (f) => setState(() => _focused = f),
                calendarBuilders: CalendarBuilders<Object>(
                  markerBuilder: (ctx, day, events) {
                    if (events.isEmpty) return null;
                    return Positioned(
                      bottom: 3,
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        for (final e in events.take(4))
                          Container(
                            width: 7,
                            height: 7,
                            margin: const EdgeInsets.symmetric(horizontal: 1),
                            decoration: BoxDecoration(color: _markerColor(e), shape: BoxShape.circle),
                          ),
                      ]),
                    );
                  },
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Wrap(spacing: 12, runSpacing: 4, children: [
                for (final e in sessionTypes.entries)
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    CircleAvatar(radius: 5, backgroundColor: sessionColor(e.key)),
                    const SizedBox(width: 4),
                    Text(e.value, style: const TextStyle(fontSize: 12)),
                  ]),
                const Row(mainAxisSize: MainAxisSize.min, children: [
                  CircleAvatar(radius: 5, backgroundColor: appointmentColor),
                  SizedBox(width: 4),
                  Text('موعد', style: TextStyle(fontSize: 12)),
                ]),
                for (final k in appointmentKinds.values.where((k) => k.legal))
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    CircleAvatar(radius: 5, backgroundColor: k.color),
                    const SizedBox(width: 4),
                    Text(k.label, style: const TextStyle(fontSize: 12)),
                  ]),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Text(fmtDate(_selected),
                  style: Theme.of(c).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            ),
            if (daySessions.isEmpty && dayAppts.isEmpty)
              const Padding(padding: EdgeInsets.all(24), child: Center(child: Text('لا توجد جلسات أو مواعيد في هذا اليوم')))
            else
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Column(children: [
                  for (final s in daySessions)
                    SessionTile(
                      s: s,
                      showDate: false,
                      onTap: () => Navigator.push(c,
                          MaterialPageRoute(builder: (_) => SessionFormScreen(caseId: s.caseId, sessionId: s.id))),
                      onOpenCase: () => Navigator.push(
                          c, MaterialPageRoute(builder: (_) => CaseDetailScreen(caseId: s.caseId))),
                    ),
                  for (final a in dayAppts)
                    AppointmentTile(
                      a: a,
                      showDate: false,
                      onTap: () => Navigator.push(c,
                          MaterialPageRoute(builder: (_) => AppointmentFormScreen(appointmentId: a.id))),
                    ),
                ]),
              ),
          ]);
        },
      ),
    );
  }
}
