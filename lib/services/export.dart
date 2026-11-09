import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../core/utils.dart';
import '../data/db.dart';
import '../data/models.dart';
import 'security.dart';

/// تقرير جاهز: HTML للطباعة/PDF + نسخة نصية للمشاركة.
class ReportData {
  final String title;
  final String html;
  final String text;
  ReportData(this.title, this.html, this.text);
}

class _Row {
  final DateTime date;
  final List<String> cells;
  _Row(this.date, this.cells);
}

/// التصدير: يُنتج PDF عبر محرك الطباعة في أندرويد (يدعم العربية RTL بشكل سليم
/// بدون الحاجة لخطوط إضافية) أو نصًا قابلًا للمشاركة.
class Export {
  static String esc(String s) => const HtmlEscape().convert(s);

  static String _page(String title, String body) => '''<!doctype html>
<html dir="rtl" lang="ar"><head><meta charset="utf-8">
<style>
body{font-family:sans-serif;direction:rtl;text-align:right;color:#111;font-size:14px}
h1{font-size:20px;color:#1F3A5F;border-bottom:2px solid #1F3A5F;padding-bottom:6px}
h2{font-size:16px;margin-top:22px;color:#1F3A5F}
table{width:100%;border-collapse:collapse;margin-top:6px}
th,td{border:1px solid #bbb;padding:5px 7px;text-align:right;vertical-align:top}
th{background:#e8edf3}
td.k{background:#f4f6f9;width:30%}
.small{font-size:11px;color:#666;margin-top:28px}
</style></head><body><h1>${esc(title)}</h1>$body
<p class="small">أجندة المحامي القانونية • ${esc(fmtDate(DateTime.now()))}</p></body></html>''';

  /// تقرير حر (مثل نموذج الإنابة): جسم HTML + نص للمشاركة.
  static ReportData custom(String title, String bodyHtml, String text) =>
      ReportData(title, _page(title, bodyHtml), text);

  static String _table(List<String> head, List<List<String>> rows) {
    final b = StringBuffer('<table><tr>');
    for (final h in head) {
      b.write('<th>${esc(h)}</th>');
    }
    b.write('</tr>');
    for (final r in rows) {
      b.write('<tr>');
      for (final c in r) {
        b.write('<td>${esc(c)}</td>');
      }
      b.write('</tr>');
    }
    b.write('</table>');
    return b.toString();
  }

  static String _kv(List<List<String>> pairs) {
    final b = StringBuffer('<table>');
    for (final p in pairs) {
      b.write('<tr><td class="k">${esc(p[0])}</td><td>${esc(p[1])}</td></tr>');
    }
    b.write('</table>');
    return b.toString();
  }

  static List<List<String>> _financePairs(Map<String, double> t) {
    final fee = t['fee'] ?? 0, paid = t['payment'] ?? 0, dep = t['deposit'] ?? 0, exp = t['expense'] ?? 0;
    return [
      ['إجمالي الأتعاب', fmtMoney(fee)],
      ['المدفوع من الأتعاب', fmtMoney(paid)],
      ['المتبقي من الأتعاب', fmtMoney(fee - paid)],
      ['الأمانات المستلمة', fmtMoney(dep)],
      ['المصروفات القضائية', fmtMoney(exp)],
      ['رصيد الأمانات', fmtMoney(dep - exp)],
    ];
  }

  static List<String> _payRow(Payment p) => [
        fmtShort(p.date),
        moneyKinds[p.kind] ?? p.kind,
        fmtMoney(p.amount),
        p.caseLabelText,
        p.note,
      ];

  static const _payHead = ['التاريخ', 'النوع', 'المبلغ', 'القضية', 'ملاحظة'];

  // ------------------------------------------------------------------
  // تقرير قضية
  // ------------------------------------------------------------------
  static Future<ReportData> caseReport(int caseId) async {
    final c = (await Db.i.legalCase(caseId))!;
    final sessions = await Db.i.sessions(caseId: caseId);
    final pays = await Db.i.paymentsForCase(caseId);
    final totals = await Db.i.caseTotals(caseId);
    final docs = await Db.i.documents(caseId);
    final title = 'تقرير ${caseLabel(c.number, c.year)}';

    final info = <List<String>>[
      ['المحكمة', c.court],
      ['الدائرة', c.circuit],
      ['النوع', c.type],
      ['الحالة', caseStatuses[c.status] ?? c.status],
      ['الموكل', c.clientName],
      ['صفة الموكل', c.clientRole],
      ['الخصم', c.opponent],
      ['الموضوع', c.title],
    ].where((e) => e[1].isNotEmpty).toList();

    final h = StringBuffer()..write(_kv(info));
    final t = StringBuffer('$title\n\n');
    for (final e in info) {
      t.writeln('${e[0]}: ${e[1]}');
    }
    if (c.notes.trim().isNotEmpty) {
      h.write('<h2>ملاحظات</h2><p>${esc(c.notes).replaceAll('\n', '<br>')}</p>');
      t.writeln('\nملاحظات: ${c.notes}');
    }

    h.write('<h2>الجلسات</h2>');
    t.writeln('\n— الجلسات —');
    if (sessions.isEmpty) {
      h.write('<p>لا توجد جلسات.</p>');
      t.writeln('لا توجد جلسات.');
    } else {
      h.write(_table(['التاريخ', 'النوع', 'القرار / الملاحظات'], [
        for (final s in sessions)
          [fmtShort(s.date), sessionTypes[s.type] ?? s.type, [s.decision, s.notes].where((e) => e.trim().isNotEmpty).join(' - ')]
      ]));
      for (final s in sessions) {
        t.writeln('• ${fmtShort(s.date)} (${sessionTypes[s.type] ?? s.type})'
            '${s.decision.trim().isEmpty ? '' : ': ${s.decision}'}');
      }
    }

    h.write('<h2>الموقف المالي للقضية</h2>${_kv(_financePairs(totals))}');
    t.writeln('\n— الموقف المالي —');
    for (final p in _financePairs(totals)) {
      t.writeln('${p[0]}: ${p[1]}');
    }
    if (pays.isNotEmpty) {
      h.write(_table(_payHead, [for (final p in pays) _payRow(p)]));
    }

    if (docs.isNotEmpty) {
      h.write('<h2>المذكرات والمستندات</h2>');
      h.write(_table(['العنوان', 'التصنيف', 'آخر تعديل'], [
        for (final d in docs)
          [d.title, d.category, fmtShort(DateTime.fromMillisecondsSinceEpoch(d.updatedAt))]
      ]));
      t.writeln('\n— المذكرات والمستندات —');
      for (final d in docs) {
        t.writeln('• ${d.title} (${d.category})');
      }
    }
    return ReportData(title, _page(title, h.toString()), t.toString());
  }

  // ------------------------------------------------------------------
  // كشف حساب موكل
  // ------------------------------------------------------------------
  static Future<ReportData> clientReport(int clientId) async {
    final cl = (await Db.i.client(clientId))!;
    final cases = await Db.i.cases(clientId: clientId);
    final totals = await Db.i.clientTotals(clientId);
    final pays = await Db.i.payments(clientId);
    final title = 'كشف حساب الموكل: ${cl.name}';

    final info = <List<String>>[
      ['الهاتف', cl.phone],
      ['البريد', cl.email],
      ['العنوان', cl.address],
    ].where((e) => e[1].isNotEmpty).toList();

    final h = StringBuffer();
    if (info.isNotEmpty) h.write(_kv(info));
    h.write('<h2>الموقف المالي الإجمالي</h2>${_kv(_financePairs(totals))}');

    final t = StringBuffer('$title\n\n');
    for (final p in _financePairs(totals)) {
      t.writeln('${p[0]}: ${p[1]}');
    }

    if (cases.isNotEmpty) {
      final rows = <List<String>>[];
      t.writeln('\n— حسب القضية —');
      for (final c in cases) {
        final ct = await Db.i.caseTotals(c.id!);
        final fee = ct['fee'] ?? 0, paid = ct['payment'] ?? 0;
        rows.add([caseLabel(c.number, c.year), fmtMoney(fee), fmtMoney(paid), fmtMoney(fee - paid)]);
        t.writeln('• ${caseLabel(c.number, c.year)}: أتعاب ${fmtMoney(fee)} • مدفوع ${fmtMoney(paid)} • متبقي ${fmtMoney(fee - paid)}');
      }
      h.write('<h2>حسب القضية</h2>');
      h.write(_table(['القضية', 'الأتعاب', 'المدفوع', 'المتبقي'], rows));
    }
    if (pays.isNotEmpty) {
      h.write('<h2>سجل الحركات</h2>');
      h.write(_table(_payHead, [for (final p in pays) _payRow(p)]));
      t.writeln('\n— سجل الحركات —');
      for (final p in pays) {
        t.writeln('• ${fmtShort(p.date)} ${moneyKinds[p.kind] ?? p.kind}: ${fmtMoney(p.amount)}'
            '${p.caseLabelText.isEmpty ? '' : ' (${p.caseLabelText})'}${p.note.isEmpty ? '' : ' - ${p.note}'}');
      }
    }
    return ReportData(title, _page(title, h.toString()), t.toString());
  }

  // ------------------------------------------------------------------
  // أجندة فترة (جلسات + مواعيد)
  // ------------------------------------------------------------------
  static Future<ReportData> agenda(DateTime from, DateTime to, String title) async {
    final sessions = await Db.i.sessions(from: from, to: to);
    final appts = await Db.i.appointments(from: from, to: to);
    final rows = <_Row>[
      for (final s in sessions)
        _Row(s.date, [
          fmtShort(s.date),
          'جلسة - ${sessionTypes[s.type] ?? s.type}',
          '${caseLabel(s.caseNumber, s.caseYear)}${s.clientName.isEmpty ? '' : ' - ${s.clientName}'}',
          s.court,
        ]),
      for (final a in appts)
        _Row(a.date, [
          fmtShort(a.date),
          'موعد${a.minutes == null ? '' : ' ${fmtTime(a.minutes!)}'}',
          a.title,
          a.caseLabelText,
        ]),
    ]..sort((x, y) => x.date.compareTo(y.date));

    final body = rows.isEmpty
        ? '<p>لا توجد جلسات أو مواعيد في هذه الفترة.</p>'
        : _table(['التاريخ', 'النوع', 'التفاصيل', 'المحكمة / القضية'], [for (final r in rows) r.cells]);
    final t = StringBuffer('$title\n\n');
    if (rows.isEmpty) t.writeln('لا توجد جلسات أو مواعيد في هذه الفترة.');
    for (final r in rows) {
      t.writeln('• ${r.cells.where((e) => e.isNotEmpty).join(' | ')}');
    }
    return ReportData(title, _page(title, body), t.toString());
  }

  // ------------------------------------------------------------------
  // قائمة قضايا
  // ------------------------------------------------------------------
  static Future<ReportData> casesList(List<LegalCase> list, String title) async {
    final body = list.isEmpty
        ? '<p>لا توجد قضايا.</p>'
        : _table(['القضية', 'الموكل', 'الخصم', 'المحكمة', 'النوع', 'الحالة', 'الجلسة القادمة'], [
            for (final c in list)
              [
                caseLabel(c.number, c.year),
                c.clientName,
                c.opponent,
                c.court,
                c.type,
                caseStatuses[c.status] ?? c.status,
                c.nextDate == null ? '' : fmtShort(c.nextDate!),
              ]
          ]);
    final t = StringBuffer('$title\n\n');
    for (final c in list) {
      t.writeln('• ${caseLabel(c.number, c.year)} | ${c.clientName} ضد ${c.opponent} | ${c.court} | '
          '${caseStatuses[c.status] ?? c.status}${c.nextDate == null ? '' : ' | جلسة ${fmtShort(c.nextDate!)}'}');
    }
    return ReportData(title, _page(title, body), t.toString());
  }

  // ------------------------------------------------------------------
  // واجهة الاستخدام: قائمة اختيار (PDF أو نص)
  // ------------------------------------------------------------------
  static Future<void> menu(BuildContext context, Future<ReportData> Function() build) {
    return showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.picture_as_pdf_outlined),
            title: const Text('PDF: عرض / طباعة / حفظ'),
            onTap: () async {
              Navigator.pop(ctx);
              try {
                final r = await build();
                await Security.guard(() => Printing.layoutPdf(
                      name: 'agenda_report',
                      onLayout: (format) => Printing.convertHtml(format: format, html: r.html),
                    ));
              } catch (e) {
                if (context.mounted) toast(context, 'تعذّر إنشاء الملف: $e');
              }
            },
          ),
          ListTile(
            leading: const Icon(Icons.share_outlined),
            title: const Text('مشاركة كنص (واتساب وغيره)'),
            onTap: () async {
              Navigator.pop(ctx);
              try {
                final r = await build();
                await Security.guard(() => Share.share(r.text, subject: r.title));
              } catch (e) {
                if (context.mounted) toast(context, 'تعذّرت المشاركة: $e');
              }
            },
          ),
        ]),
      ),
    );
  }
}
