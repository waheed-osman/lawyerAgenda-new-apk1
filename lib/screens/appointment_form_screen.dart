import 'package:flutter/material.dart';

import '../core/utils.dart';
import '../core/widgets.dart';
import '../data/db.dart';
import '../data/models.dart';

/// إضافة / تعديل موعد أو ميعاد قانوني (شهادة، معارضة، استئناف، نقض، رسوم...) مرتبط بقضية أو لا.
class AppointmentFormScreen extends StatefulWidget {
  final int? appointmentId;
  final DateTime? initialDate;
  final int? caseId;
  const AppointmentFormScreen({super.key, this.appointmentId, this.initialDate, this.caseId});
  @override
  State<AppointmentFormScreen> createState() => _AppointmentFormScreenState();
}

class _AppointmentFormScreenState extends State<AppointmentFormScreen> {
  final _title = TextEditingController();
  final _notes = TextEditingController();
  DateTime _date = dayStart(DateTime.now());
  int? _minutes;
  int? _caseId;
  String _kind = 'other';
  DateTime _base = dayStart(DateTime.now()); // تاريخ الحكم/الإعلان للحاسبة
  int _days = 0;
  Appointment? _orig;
  List<LegalCase> _cases = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    _cases = await Db.i.cases();
    if (widget.initialDate != null) _date = dayStart(widget.initialDate!);
    _caseId = widget.caseId;
    if (widget.appointmentId != null) {
      final a = await Db.i.appointment(widget.appointmentId!);
      if (a != null) {
        _orig = a;
        _title.text = a.title;
        _notes.text = a.notes;
        _date = a.date;
        _minutes = a.minutes;
        _caseId = a.caseId;
        _kind = a.kind;
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save() async {
    if (_title.text.trim().isEmpty) {
      _title.text = apptKind(_kind).label;
    }
    final a = _orig ?? Appointment(date: _date);
    a
      ..title = _title.text.trim()
      ..notes = _notes.text.trim()
      ..date = _date
      ..minutes = _minutes
      ..caseId = _caseId
      ..kind = _kind;
    await Db.i.saveAppointment(a);
    if (mounted) Navigator.pop(context);
  }

  void _applyDays(int n) {
    final d = addDays(_base, n);
    setState(() {
      _days = n;
      _date = d;
    });
    // الجمعة = 5 والسبت = 6 في DateTime.weekday
    if (d.weekday == DateTime.friday || d.weekday == DateTime.saturday) {
      toast(context, 'تنبيه: آخر الميعاد يوافق ${d.weekday == DateTime.friday ? 'الجمعة' : 'السبت'} — راجع امتداد الميعاد في القانون');
    }
  }

  /// حاسبة ميعاد: تاريخ الحكم/الإعلان + عدد الأيام. الأيام المقترحة عامة، والمرجع النص القانوني.
  Widget _calculator(RoundedRectangleBorder shape) => Card(
        margin: const EdgeInsets.only(bottom: 12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('حاسبة الميعاد', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            ListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              leading: const Icon(Icons.today),
              title: const Text('تاريخ الحكم / الإعلان'),
              subtitle: Text(fmtDate(_base)),
              onTap: () async {
                final d = await pickDate(context, _base);
                if (d != null) {
                  setState(() => _base = dayStart(d));
                  if (_days > 0) _applyDays(_days);
                }
              },
            ),
            Wrap(spacing: 8, children: [
              for (final n in const [10, 15, 30, 40, 60])
                ActionChip(
                  label: Text('+$n يوم'),
                  backgroundColor: _days == n ? Theme.of(context).colorScheme.primaryContainer : null,
                  onPressed: () => _applyDays(n),
                ),
            ]),
            const SizedBox(height: 6),
            Text(
              _days == 0
                  ? 'اختر تاريخ الحكم ثم عدد الأيام، فيُضبط تاريخ الموعد تلقائيًا.'
                  : 'آخر الميعاد: ${fmtDate(_date)} (${_base == _date ? '' : '$_days يوم من ${fmtDate(_base)}'}) — الأيام اقتراح عام، تأكد من مدة الميعاد في النص القانوني.',
              style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.outline),
            ),
          ]),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final shape = RoundedRectangleBorder(
        side: BorderSide(color: cs.outlineVariant), borderRadius: BorderRadius.circular(12));
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.appointmentId == null ? 'موعد جديد' : 'تعديل الموعد'),
        actions: [
          if (_orig != null)
            IconButton(
              tooltip: 'حذف',
              icon: const Icon(Icons.delete_outline),
              onPressed: () async {
                if (await confirm(context, 'حذف هذا الموعد؟', ok: 'حذف')) {
                  await Db.i.deleteAppointment(_orig!.id!);
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
              const Text('نوع الموعد', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 4, children: [
                for (final e in appointmentKinds.entries)
                  ChoiceChip(
                    label: Text(e.value.label),
                    selected: _kind == e.key,
                    selectedColor: e.value.color.withOpacity(0.25),
                    onSelected: (_) => setState(() {
                      _kind = e.key;
                      if (_title.text.trim().isEmpty || appointmentKinds.values.any((k) => k.label == _title.text.trim())) {
                        _title.text = e.value.label;
                      }
                    }),
                  ),
              ]),
              const SizedBox(height: 12),
              if (apptKind(_kind).legal) _calculator(shape),
              tf(_title, 'عنوان الموعد', icon: Icons.event_note, required: true),
              ListTile(
                shape: shape,
                leading: const Icon(Icons.event),
                title: const Text('التاريخ'),
                subtitle: Text(fmtDate(_date)),
                onTap: () async {
                  final d = await pickDate(context, _date);
                  if (d != null) setState(() => _date = dayStart(d));
                },
              ),
              const SizedBox(height: 12),
              ListTile(
                shape: shape,
                leading: const Icon(Icons.access_time),
                title: Text(_minutes == null ? 'الوقت (اختياري)' : 'الوقت: ${fmtTime(_minutes!)}'),
                trailing: _minutes == null
                    ? null
                    : IconButton(icon: const Icon(Icons.close), onPressed: () => setState(() => _minutes = null)),
                onTap: () async {
                  final t = await showTimePicker(
                    context: context,
                    initialTime: TimeOfDay(hour: (_minutes ?? 540) ~/ 60, minute: (_minutes ?? 540) % 60),
                  );
                  if (t != null) setState(() => _minutes = t.hour * 60 + t.minute);
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<int?>(
                value: _cases.any((c) => c.id == _caseId) ? _caseId : null,
                isExpanded: true,
                decoration: dec('مرتبط بقضية (اختياري)', icon: Icons.gavel),
                items: [
                  const DropdownMenuItem<int?>(value: null, child: Text('— بدون —')),
                  for (final c in _cases)
                    DropdownMenuItem<int?>(
                        value: c.id,
                        child: Text('${caseLabel(c.number, c.year)}${c.clientName.isEmpty ? '' : ' - ${c.clientName}'}',
                            overflow: TextOverflow.ellipsis)),
                ],
                onChanged: (v) => setState(() => _caseId = v),
              ),
              const SizedBox(height: 12),
              tf(_notes, 'ملاحظات', maxLines: 4),
              FilledButton.icon(onPressed: _save, icon: const Icon(Icons.save), label: const Text('حفظ')),
            ]),
    );
  }
}
