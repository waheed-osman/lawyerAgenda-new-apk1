import 'dart:io';

import 'package:flutter/material.dart';

import '../data/db.dart';
import '../data/models.dart';
import 'utils.dart';

/// Loads data asynchronously and reloads whenever the database changes.
class Live<T> extends StatefulWidget {
  final Future<T> Function() load;
  final Widget Function(BuildContext, T) builder;
  const Live({super.key, required this.load, required this.builder});
  @override
  State<Live<T>> createState() => _LiveState<T>();
}

class _LiveState<T> extends State<Live<T>> {
  late Future<T> _f;

  @override
  void initState() {
    super.initState();
    _f = widget.load();
    Db.i.addListener(_reload);
  }

  void _reload() {
    if (mounted) setState(() => _f = widget.load());
  }

  @override
  void didUpdateWidget(covariant Live<T> old) {
    super.didUpdateWidget(old);
    _f = widget.load();
  }

  @override
  void dispose() {
    Db.i.removeListener(_reload);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<T>(
        future: _f,
        builder: (c, s) {
          if (s.hasError) return Center(child: Text('خطأ: ${s.error}'));
          if (!s.hasData) return const Center(child: CircularProgressIndicator());
          return widget.builder(c, s.data as T);
        },
      );
}

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String text;
  const EmptyState({super.key, required this.icon, required this.text});
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 56, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 12),
            Text(text,
                textAlign: TextAlign.center,
                style: TextStyle(color: Theme.of(context).colorScheme.outline)),
          ]),
        ),
      );
}

class StatusChip extends StatelessWidget {
  final String label;
  final Color color;
  const StatusChip(this.label, this.color, {super.key});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        decoration: BoxDecoration(color: color.withOpacity(.15), borderRadius: BorderRadius.circular(12)),
        child: Text(label, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
      );
}

class SectionTitle extends StatelessWidget {
  final String text;
  final Widget? trailing;
  const SectionTitle(this.text, {super.key, this.trailing});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 16, 4, 6),
        child: Row(children: [
          Expanded(child: Text(text, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold))),
          if (trailing != null) trailing!,
        ]),
      );
}

class InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback? onTap;
  const InfoRow(this.label, this.value, {super.key, this.onTap});
  @override
  Widget build(BuildContext context) {
    if (value.trim().isEmpty) return const SizedBox.shrink();
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
              width: 110,
              child: Text(label, style: TextStyle(color: Theme.of(context).colorScheme.outline))),
          Expanded(
              child: Text(value,
                  style: TextStyle(
                      fontWeight: FontWeight.w500,
                      color: onTap != null ? Theme.of(context).colorScheme.primary : null))),
        ]),
      ),
    );
  }
}

InputDecoration dec(String label, {IconData? icon}) =>
    InputDecoration(labelText: label, prefixIcon: icon == null ? null : Icon(icon));

Widget tf(TextEditingController c, String label,
        {IconData? icon, TextInputType? type, int maxLines = 1, bool required = false}) =>
    Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: c,
        keyboardType: type,
        maxLines: maxLines,
        minLines: maxLines > 1 ? 3 : 1,
        decoration: dec(label, icon: icon),
        validator: required ? (v) => (v == null || v.trim().isEmpty) ? 'مطلوب' : null : null,
      ),
    );

Future<DateTime?> pickDate(BuildContext c, DateTime initial) => showDatePicker(
      context: c,
      initialDate: initial,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );

class SessionTile extends StatelessWidget {
  final CaseSession s;
  final bool showDate;
  final VoidCallback onTap;
  final VoidCallback? onOpenCase;
  const SessionTile({super.key, required this.s, required this.onTap, this.showDate = true, this.onOpenCase});

  @override
  Widget build(BuildContext context) {
    final col = sessionColor(s.type);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: IntrinsicHeight(
          child: Row(children: [
            Container(width: 6, color: col),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    StatusChip(sessionTypes[s.type] ?? s.type, col),
                    const Spacer(),
                    if (showDate)
                      Text('${relText(s.date)} • ${fmtShort(s.date)}',
                          style: Theme.of(context).textTheme.bodySmall),
                  ]),
                  const SizedBox(height: 6),
                  Text(caseLabel(s.caseNumber, s.caseYear),
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  if (s.clientName.isNotEmpty) Text('الموكل: ${s.clientName}'),
                  if (s.roll.isNotEmpty) Text('الرول: ${s.roll}'),
                  if (s.court.isNotEmpty)
                    Text(s.court, style: TextStyle(color: Theme.of(context).colorScheme.outline)),
                  if (s.decision.trim().isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text('القرار: ${s.decision}', maxLines: 2, overflow: TextOverflow.ellipsis),
                    ),
                ]),
              ),
            ),
            if (onOpenCase != null)
              IconButton(
                tooltip: 'فتح القضية',
                icon: const Icon(Icons.folder_open),
                onPressed: onOpenCase,
              ),
          ]),
        ),
      ),
    );
  }
}

class CaseCard extends StatelessWidget {
  final LegalCase c;
  final VoidCallback onTap;
  const CaseCard({super.key, required this.c, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(
                  child: Text(caseLabel(c.number, c.year),
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),
              StatusChip(caseStatuses[c.status] ?? c.status, statusColor(c.status)),
            ]),
            const SizedBox(height: 6),
            if (c.clientName.isNotEmpty || c.opponent.isNotEmpty)
              Text('${c.clientName.isEmpty ? '—' : c.clientName} (${c.clientRole})  ضد  ${c.opponent.isEmpty ? '—' : c.opponent}'),
            const SizedBox(height: 2),
            Text([c.type, c.court, c.circuit].where((e) => e.isNotEmpty).join(' • '),
                style: TextStyle(color: Theme.of(context).colorScheme.outline)),
            if (c.nextDate != null) ...[
              const SizedBox(height: 6),
              Row(children: [
                const Icon(Icons.event, size: 16),
                const SizedBox(width: 4),
                Text('الجلسة القادمة: ${fmtShort(c.nextDate!)} (${relText(c.nextDate!)})',
                    style: const TextStyle(fontSize: 13)),
              ]),
            ],
          ]),
        ),
      ),
    );
  }
}

class ImageViewScreen extends StatelessWidget {
  final String file;
  const ImageViewScreen({super.key, required this.file});
  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(backgroundColor: Colors.black, foregroundColor: Colors.white),
        body: Center(
          child: InteractiveViewer(
            maxScale: 6,
            child: Image.file(File(AppFiles.resolve(file).path)),
          ),
        ),
      );
}

/// بطاقة موعد عام (غير جلسة).
class AppointmentTile extends StatelessWidget {
  final Appointment a;
  final bool showDate;
  final VoidCallback onTap;
  const AppointmentTile({super.key, required this.a, required this.onTap, this.showDate = true});

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: IntrinsicHeight(
          child: Row(children: [
            Container(width: 6, color: apptKind(a.kind).color),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    StatusChip(a.kind == 'other' ? 'موعد' : apptKind(a.kind).label, apptKind(a.kind).color),
                    const SizedBox(width: 8),
                    if (a.minutes != null) Text(fmtTime(a.minutes!), style: const TextStyle(fontWeight: FontWeight.w600)),
                    const Spacer(),
                    if (showDate)
                      Text('${relText(a.date)} • ${fmtShort(a.date)}',
                          style: Theme.of(context).textTheme.bodySmall),
                  ]),
                  const SizedBox(height: 6),
                  Text(a.title, style: const TextStyle(fontWeight: FontWeight.bold)),
                  if (a.caseLabelText.isNotEmpty)
                    Text(a.caseLabelText, style: TextStyle(color: Theme.of(context).colorScheme.outline)),
                  if (a.notes.trim().isNotEmpty)
                    Text(a.notes, maxLines: 2, overflow: TextOverflow.ellipsis),
                ]),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

/// ست بطاقات مالية: أتعاب / مدفوع / متبقي، ثم أمانات / مصروفات / رصيد الأمانات.
/// [t] هي خريطة المجاميع القادمة من Db.clientTotals / caseTotals / overallTotals.
class FinanceStats extends StatelessWidget {
  final Map<String, double> t;
  const FinanceStats(this.t, {super.key});

  Widget _stat(BuildContext c, String label, double v, Color col) => Expanded(
        child: Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
            child: Column(children: [
              FittedBox(
                child: Text(fmtMoney(v),
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: col)),
              ),
              const SizedBox(height: 2),
              Text(label, style: const TextStyle(fontSize: 11), textAlign: TextAlign.center),
            ]),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final fee = t['fee'] ?? 0, paid = t['payment'] ?? 0, dep = t['deposit'] ?? 0, exp = t['expense'] ?? 0;
    final rest = fee - paid;
    const red = Color(0xFFD64545), green = Color(0xFF2E9E5B);
    final primary = Theme.of(context).colorScheme.primary;
    return Column(children: [
      Row(children: [
        _stat(context, 'إجمالي الأتعاب', fee, primary),
        _stat(context, 'المدفوع', paid, green),
        _stat(context, 'المتبقي', rest, rest > 0 ? red : green),
      ]),
      Row(children: [
        _stat(context, 'أمانات مستلمة', dep, primary),
        _stat(context, 'مصروفات قضائية', exp, const Color(0xFFF59E0B)),
        _stat(context, 'رصيد الأمانات', dep - exp, dep - exp < 0 ? red : green),
      ]),
    ]);
  }
}
