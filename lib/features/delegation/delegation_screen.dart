import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/utils.dart';
import '../../core/widgets.dart';
import '../../data/db.dart';
import '../../services/export.dart';

/// نموذج إنابة (محامٍ ينيب زميلًا لحضور جلسة): يُملأ من بيانات القضية والجلسة،
/// ثم يُطبع PDF أو يُرسل واتساب/نصًا. الصياغة نموذج عام يراجعه المحامي قبل الاستخدام.
class DelegationScreen extends StatefulWidget {
  final int caseId;
  final int? sessionId;
  const DelegationScreen({super.key, required this.caseId, this.sessionId});
  @override
  State<DelegationScreen> createState() => _DelegationScreenState();
}

class _DelegationScreenState extends State<DelegationScreen> {
  static const _prefKey = 'delegation_my_name';
  static const _scopes = {
    'الحضور وإثبات الحضور': true,
    'طلب التأجيل': true,
    'الاطلاع وطلب صور المستندات': false,
    'تقديم المذكرات والمستندات': false,
    'المرافعة الشفوية': false,
    'استلام الشهادات والصور': false,
  };

  final _me = TextEditingController();
  final _deputy = TextEditingController();
  final _phone = TextEditingController();
  final _client = TextEditingController();
  final _opponent = TextEditingController();
  final _number = TextEditingController();
  final _year = TextEditingController();
  final _court = TextEditingController();
  final _circuit = TextEditingController();
  final _roll = TextEditingController();
  final _extra = TextEditingController();
  DateTime _date = dayStart(DateTime.now());
  late final Map<String, bool> _chosen = Map.of(_scopes);
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final sp = await SharedPreferences.getInstance();
      _me.text = sp.getString(_prefKey) ?? '';
    } catch (_) {}
    final c = await Db.i.legalCase(widget.caseId);
    if (c != null) {
      _client.text = c.clientName;
      _opponent.text = c.opponent;
      _number.text = c.number;
      _year.text = c.year;
      _court.text = c.court;
      _circuit.text = c.circuit;
    }
    final s = widget.sessionId != null
        ? await Db.i.session(widget.sessionId!)
        : (await Db.i.sessions(caseId: widget.caseId, from: dayStart(DateTime.now()), limit: 1)).firstOrNull;
    if (s != null) {
      _date = s.date;
      _roll.text = s.roll;
    }
    if (mounted) setState(() => _loading = false);
  }

  String _scopeText() {
    final l = [for (final e in _chosen.entries) if (e.value) e.key];
    if (_extra.text.trim().isNotEmpty) l.add(_extra.text.trim());
    return l.isEmpty ? 'الحضور نيابةً عني' : l.join('، ');
  }

  /// الأسطر الأساسية لنص الإنابة (تُستخدم في النص وفي PDF).
  List<String> _paras() {
    final cn = _number.text.trim().isEmpty ? '........' : _number.text.trim();
    final yr = _year.text.trim().isEmpty ? '....' : _year.text.trim();
    final b = StringBuffer('أنا الأستاذ/ ${_v(_me)} المحامي، أُنيب عني الأستاذ/ ${_v(_deputy)} المحامي');
    b.write(' في الحضور أمام ${_v(_court)}');
    if (_circuit.text.trim().isNotEmpty) b.write(' - الدائرة ${_circuit.text.trim()}');
    b.write(' في القضية رقم $cn لسنة $yr');
    b.write('، المحدد لنظرها جلسة ${fmtDate(_date)}');
    if (_roll.text.trim().isNotEmpty) b.write(' (رول ${_roll.text.trim()})');
    b.write('، بصفتي وكيلًا عن ${_v(_client)}');
    if (_opponent.text.trim().isNotEmpty) b.write(' ضد ${_opponent.text.trim()}');
    b.write('.');
    return [
      b.toString(),
      'وذلك في: ${_scopeText()}.',
      'وهذه الإنابة خاصة بهذه الجلسة فقط، وفي حدود الوكالة الصادرة لي من الموكل، ولا تتضمن التنازل عن أي حق أو الإقرار بأي أمر دون الرجوع إليّ.',
    ];
  }

  String _v(TextEditingController c) => c.text.trim().isEmpty ? '........' : c.text.trim();

  String _text() => 'إنابة قانونية\n\n${_paras().join('\n\n')}\n\nالمحامي المُنيب: ${_v(_me)}\nالتوقيع: ..........\nالتاريخ: ${fmtDate(DateTime.now())}';

  ReportData _report() {
    final body = StringBuffer();
    for (final p in _paras()) {
      body.write('<p style="font-size:16px;line-height:2">${Export.esc(p)}</p>');
    }
    body.write('<br><table><tr><td class="k">المحامي المُنيب</td><td>${Export.esc(_v(_me))}</td></tr>'
        '<tr><td class="k">التوقيع</td><td style="height:50px"></td></tr>'
        '<tr><td class="k">المحامي المناب (استلمت الإنابة)</td><td>${Export.esc(_v(_deputy))}</td></tr>'
        '<tr><td class="k">توقيع المناب</td><td style="height:50px"></td></tr></table>');
    return Export.custom('إنابة قانونية', body.toString(), _text());
  }

  Future<void> _saveName() async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setString(_prefKey, _me.text.trim());
    } catch (_) {}
  }

  String _wa(String raw) {
    var d = raw.replaceAll(RegExp(r'[^0-9]'), '');
    if (d.startsWith('00')) d = d.substring(2);
    if (d.startsWith('0')) d = '20${d.substring(1)}';
    return d;
  }

  Future<void> _whatsapp() async {
    await _saveName();
    final text = Uri.encodeComponent(_text());
    final num = _phone.text.trim().isEmpty ? '' : _wa(_phone.text);
    final uri = Uri.parse(num.isEmpty ? 'https://wa.me/?text=$text' : 'https://wa.me/$num?text=$text');
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && mounted) toast(context, 'تعذّر فتح واتساب');
    } catch (_) {
      if (mounted) toast(context, 'تعذّر فتح واتساب');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('نموذج إنابة')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(padding: const EdgeInsets.all(16), children: [
              tf(_me, 'اسم المحامي المُنيب (اسمك)', icon: Icons.person),
              tf(_deputy, 'اسم المحامي المناب (الزميل)', icon: Icons.person_outline),
              tf(_phone, 'واتساب الزميل (اختياري)', icon: Icons.chat, type: TextInputType.phone),
              const Divider(),
              tf(_client, 'الموكل', icon: Icons.badge_outlined),
              tf(_opponent, 'الخصم (اختياري)'),
              Row(children: [
                Expanded(child: tf(_number, 'رقم القضية', type: TextInputType.number)),
                const SizedBox(width: 8),
                Expanded(child: tf(_year, 'السنة', type: TextInputType.number)),
              ]),
              tf(_court, 'المحكمة', icon: Icons.account_balance),
              Row(children: [
                Expanded(child: tf(_circuit, 'الدائرة')),
                const SizedBox(width: 8),
                Expanded(child: tf(_roll, 'الرول')),
              ]),
              ListTile(
                shape: RoundedRectangleBorder(
                    side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
                    borderRadius: BorderRadius.circular(12)),
                leading: const Icon(Icons.event),
                title: const Text('تاريخ الجلسة'),
                subtitle: Text(fmtDate(_date)),
                onTap: () async {
                  final d = await pickDate(context, _date);
                  if (d != null) setState(() => _date = dayStart(d));
                },
              ),
              const SizedBox(height: 12),
              const Text('حدود الإنابة', style: TextStyle(fontWeight: FontWeight.w600)),
              for (final k in _chosen.keys)
                CheckboxListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(k),
                  value: _chosen[k],
                  onChanged: (v) => setState(() => _chosen[k] = v ?? false),
                ),
              tf(_extra, 'بند إضافي (اختياري)', maxLines: 2),
              Text('النموذج صياغة عامة، راجعها وعدّلها بما يناسب الوكالة وتعليمات المحكمة قبل الاستخدام.',
                  style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.outline)),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: () async {
                  await _saveName();
                  if (context.mounted) await Export.menu(context, () async => _report());
                },
                icon: const Icon(Icons.print),
                label: const Text('طباعة / PDF / مشاركة نص'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _whatsapp,
                icon: const Icon(Icons.chat),
                label: const Text('إرسال واتساب'),
              ),
            ]),
    );
  }
}
