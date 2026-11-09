import 'package:flutter/material.dart';

import '../core/utils.dart';
import '../core/widgets.dart';
import '../data/db.dart';
import '../data/models.dart';
import 'attachments_view.dart';

class SessionFormScreen extends StatefulWidget {
  final int caseId;
  final int? sessionId;
  final DateTime? initialDate;
  const SessionFormScreen({super.key, required this.caseId, this.sessionId, this.initialDate});
  @override
  State<SessionFormScreen> createState() => _SessionFormScreenState();
}

class _SessionFormScreenState extends State<SessionFormScreen> {
  final _decision = TextEditingController();
  final _notes = TextEditingController();
  final _roll = TextEditingController();
  DateTime _date = dayStart(DateTime.now());
  String _type = 'pleading';
  DateTime? _next;
  String _nextType = 'pleading';
  CaseSession? _orig;
  LegalCase? _case;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    _case = await Db.i.legalCase(widget.caseId);
    if (widget.initialDate != null) _date = dayStart(widget.initialDate!);
    if (widget.sessionId != null) {
      final s = await Db.i.session(widget.sessionId!);
      if (s != null) {
        _orig = s;
        _date = s.date;
        _type = s.type;
        _decision.text = s.decision;
        _notes.text = s.notes;
        _roll.text = s.roll;
        if (s.nextSessionId != null) {
          final n = await Db.i.session(s.nextSessionId!);
          if (n != null) {
            _next = n.date;
            _nextType = n.type;
          }
        }
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save() async {
    final s = _orig ??
        CaseSession(caseId: widget.caseId, date: _date);
    s
      ..date = _date
      ..type = _type
      ..decision = _decision.text.trim()
      ..notes = _notes.text.trim()
      ..roll = _roll.text.trim();
    await Db.i.saveSession(s, next: _next, nextType: _nextType);
    if (mounted) Navigator.pop(context);
  }

  Future<void> _delete() async {
    if (_orig == null) return;
    if (await confirm(context, 'حذف هذه الجلسة؟', ok: 'حذف')) {
      await Db.i.deleteSession(_orig!.id!);
      if (mounted) Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.sessionId == null ? 'جلسة جديدة' : 'تفاصيل الجلسة'),
        actions: [
          if (_orig != null)
            IconButton(onPressed: _delete, icon: const Icon(Icons.delete_outline), tooltip: 'حذف'),
          IconButton(onPressed: _save, icon: const Icon(Icons.check), tooltip: 'حفظ'),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(padding: const EdgeInsets.all(16), children: [
              if (_case != null)
                Card(
                  color: cs.primaryContainer,
                  child: ListTile(
                    leading: const Icon(Icons.gavel),
                    title: Text(caseLabel(_case!.number, _case!.year)),
                    subtitle: Text([_case!.clientName, _case!.court].where((e) => e.isNotEmpty).join(' • ')),
                  ),
                ),
              const SizedBox(height: 8),
              ListTile(
                shape: RoundedRectangleBorder(
                    side: BorderSide(color: cs.outlineVariant), borderRadius: BorderRadius.circular(12)),
                leading: const Icon(Icons.event),
                title: const Text('تاريخ الجلسة'),
                subtitle: Text(fmtDate(_date)),
                onTap: () async {
                  final d = await pickDate(context, _date);
                  if (d != null) setState(() => _date = dayStart(d));
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: _type,
                decoration: dec('نوع / حالة الجلسة'),
                items: [
                  for (final e in sessionTypes.entries)
                    DropdownMenuItem(
                      value: e.key,
                      child: Row(children: [
                        CircleAvatar(radius: 6, backgroundColor: sessionColor(e.key)),
                        const SizedBox(width: 8),
                        Text(e.value),
                      ]),
                    ),
                ],
                onChanged: (v) => setState(() => _type = v!),
              ),
              const SizedBox(height: 12),
              tf(_roll, 'رقم الرول', icon: Icons.format_list_numbered, type: TextInputType.text),
              tf(_decision, 'القرار / الحكم الصادر في الجلسة', maxLines: 5),
              tf(_notes, 'ملاحظات', maxLines: 3),
              const Divider(),
              Text('الجلسة القادمة', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              ListTile(
                shape: RoundedRectangleBorder(
                    side: BorderSide(color: cs.outlineVariant), borderRadius: BorderRadius.circular(12)),
                leading: const Icon(Icons.event_repeat),
                title: Text(_next == null ? 'تحديد تاريخ الجلسة القادمة' : fmtDate(_next!)),
                subtitle: const Text('تُنشأ الجلسة القادمة تلقائيًا في الأجندة'),
                trailing: _next == null
                    ? null
                    : IconButton(icon: const Icon(Icons.close), onPressed: () => setState(() => _next = null)),
                onTap: () async {
                  final d = await pickDate(context, _next ?? addDays(_date, 14));
                  if (d != null) setState(() => _next = dayStart(d));
                },
              ),
              if (_next != null) ...[
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: _nextType,
                  decoration: dec('نوع الجلسة القادمة'),
                  items: [
                    for (final e in sessionTypes.entries) DropdownMenuItem(value: e.key, child: Text(e.value))
                  ],
                  onChanged: (v) => setState(() => _nextType = v!),
                ),
              ],
              const Divider(height: 32),
              Text('صور محضر الجلسة / المستندات', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              if (_orig == null)
                const Text('احفظ الجلسة أولًا ثم افتحها لإضافة الصور.')
              else
                AttachmentsView(caseId: widget.caseId, sessionId: _orig!.id),
              const SizedBox(height: 24),
              FilledButton.icon(onPressed: _save, icon: const Icon(Icons.save), label: const Text('حفظ')),
            ]),
    );
  }
}
