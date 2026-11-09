import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../core/theme.dart';
import '../core/utils.dart';
import '../core/widgets.dart';
import '../data/backup.dart';
import '../services/notifications.dart';
import '../services/security.dart';
import 'ai_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _hasPw = false;
  bool _numeric = false;
  bool _bio = false;
  BioStatus _bioStatus = BioStatus.unsupported;
  int _grace = 30;
  bool _busy = false;

  static const _graceOptions = <int, String>{
    15: '15 ثانية',
    30: '30 ثانية',
    60: 'دقيقة',
    300: '5 دقائق',
    900: '15 دقيقة',
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final h = await Security.hasPassword();
    final n = await Security.isNumeric();
    final b = await Security.biometricEnabled();
    final st = await Security.biometricStatus();
    final g = await Security.graceSeconds();
    if (mounted) {
      setState(() {
        _hasPw = h;
        _numeric = n;
        _bio = b;
        _bioStatus = st;
        _grace = g;
      });
    }
  }

  /// يسأل عن الرمز الحالي (لوحة أرقام إن كان PIN).
  Future<String?> _askCurrent(String title) async {
    final c = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: c,
          obscureText: true,
          autofocus: true,
          keyboardType: _numeric ? TextInputType.number : TextInputType.visiblePassword,
          decoration: dec(_numeric ? 'رمز PIN' : 'كلمة المرور'),
          onSubmitted: (_) => Navigator.pop(ctx, c.text),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(ctx, c.text), child: const Text('موافق')),
        ],
      ),
    );
  }

  /// يسأل عن رمز جديد: PIN رقمي (4–8 أرقام) أو كلمة مرور (6 أحرف فأكثر) مع التأكيد.
  Future<({String value, bool numeric})?> _askNew(String title) async {
    final a = TextEditingController();
    final b = TextEditingController();
    String? err;
    var numeric = true;
    return showDialog<({String value, bool numeric})>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: Text(title),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              SizedBox(
                width: double.infinity,
                child: SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(value: true, icon: Icon(Icons.pin_outlined), label: Text('PIN رقمي')),
                    ButtonSegment(value: false, icon: Icon(Icons.password), label: Text('كلمة مرور')),
                  ],
                  selected: {numeric},
                  onSelectionChanged: (v) => setS(() {
                    numeric = v.first;
                    a.clear();
                    b.clear();
                    err = null;
                  }),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: a,
                obscureText: true,
                autofocus: true,
                keyboardType: numeric ? TextInputType.number : TextInputType.visiblePassword,
                inputFormatters: numeric
                    ? [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(8)]
                    : null,
                decoration: InputDecoration(
                    labelText: numeric ? 'رمز PIN (4 إلى 8 أرقام)' : 'كلمة المرور (6 أحرف على الأقل)', errorText: err),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: b,
                obscureText: true,
                keyboardType: numeric ? TextInputType.number : TextInputType.visiblePassword,
                inputFormatters: numeric
                    ? [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(8)]
                    : null,
                decoration: const InputDecoration(labelText: 'تأكيد الرمز'),
              ),
              const Padding(
                padding: EdgeInsets.only(top: 10),
                child: Text('تنبيه: لا يمكن استرجاع الرمز إذا نُسي. احتفظ بنسخة احتياطية خارج الهاتف.',
                    style: TextStyle(fontSize: 12)),
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
            FilledButton(
              onPressed: () {
                if (numeric && (a.text.length < 4 || a.text.length > 8)) {
                  setS(() => err = 'من 4 إلى 8 أرقام');
                } else if (!numeric && a.text.length < 6) {
                  setS(() => err = '6 أحرف على الأقل');
                } else if (a.text != b.text) {
                  setS(() => err = 'غير متطابقين');
                } else {
                  Navigator.pop(ctx, (value: a.text, numeric: numeric));
                }
              },
              child: const Text('موافق'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _setPassword() async {
    if (_hasPw) {
      final cur = await _askCurrent('أدخل الرمز الحالي');
      if (cur == null) return;
      if (!await Security.verify(cur)) {
        if (mounted) toast(context, 'الرمز الحالي غير صحيح');
        return;
      }
    }
    final n = await _askNew(_hasPw ? 'الرمز الجديد' : 'تعيين رمز القفل');
    if (n == null) return;
    await Security.setSecret(n.value, numeric: n.numeric);
    await _load();
    if (mounted) toast(context, 'تم حفظ رمز القفل');
  }

  Future<void> _removePassword() async {
    final cur = await _askCurrent('أدخل الرمز لإلغاء القفل');
    if (cur == null) return;
    if (!await Security.verify(cur)) {
      if (mounted) toast(context, 'الرمز غير صحيح');
      return;
    }
    await Security.removePassword();
    await _load();
  }

  Future<void> _toggleBio(bool v) async {
    if (v && !await Security.authenticate()) {
      if (mounted) toast(context, Security.lastBioError ?? 'لم يتم التحقق من البصمة');
      return;
    }
    await Security.setBiometric(v);
    await _load();
  }

  Future<void> _pickGrace() async {
    final g = await showDialog<int>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('القفل التلقائي بعد مغادرة التطبيق'),
        children: [
          for (final e in _graceOptions.entries)
            RadioListTile<int>(
              value: e.key,
              groupValue: _grace,
              title: Text(e.value),
              onChanged: (v) => Navigator.pop(ctx, v),
            ),
        ],
      ),
    );
    if (g == null) return;
    await Security.setGrace(g);
    await _load();
  }

  String get _bioSubtitle {
    switch (_bioStatus) {
      case BioStatus.ready:
        return 'استخدم بصمة الإصبع بدل كتابة الرمز';
      case BioStatus.notEnrolled:
        return 'لا توجد بصمة مسجلة. سجّلها أولًا من إعدادات الهاتف';
      case BioStatus.unsupported:
        return 'غير متاحة على هذا الهاتف';
    }
  }

  Future<void> _backup() async {
    setState(() => _busy = true);
    try {
      final f = await Backup.export();
      await Security.guard(() => Share.shareXFiles([XFile(f.path)], subject: 'نسخة احتياطية - أجندة المحامي'));
    } catch (e) {
      if (mounted) toast(context, 'تعذّر إنشاء النسخة: $e');
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _restore() async {
    if (!await confirm(context, 'سيتم استبدال كل البيانات الحالية ببيانات ملف النسخة الاحتياطية. هل أنت متأكد؟',
        ok: 'استعادة')) {
      return;
    }
    final res = await Security.guard(
        () => FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['json']));
    final path = res?.files.single.path;
    if (path == null) return;
    setState(() => _busy = true);
    try {
      await Backup.restore(File(path));
      if (mounted) toast(context, 'تمت استعادة البيانات بنجاح');
    } catch (e) {
      if (mounted) toast(context, 'فشلت الاستعادة: $e');
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('الإعدادات')),
      body: Stack(children: [
        ListView(padding: const EdgeInsets.all(12), children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('المظهر', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 10),
                ValueListenableBuilder<ThemeMode>(
                  valueListenable: AppSettings.themeMode,
                  builder: (_, m, __) => SizedBox(
                    width: double.infinity,
                    child: SegmentedButton<ThemeMode>(
                      segments: const [
                        ButtonSegment(value: ThemeMode.light, icon: Icon(Icons.light_mode), label: Text('فاتح')),
                        ButtonSegment(value: ThemeMode.dark, icon: Icon(Icons.dark_mode), label: Text('داكن')),
                        ButtonSegment(value: ThemeMode.system, icon: Icon(Icons.phone_android), label: Text('النظام')),
                      ],
                      selected: {m},
                      onSelectionChanged: (s) => AppSettings.setTheme(s.first),
                    ),
                  ),
                ),
              ]),
            ),
          ),
          Card(
            child: Column(children: [
              ListTile(
                leading: const Icon(Icons.lock_outline),
                title: Text(_hasPw ? 'تغيير رمز القفل' : 'تعيين رمز قفل للتطبيق (PIN أو كلمة مرور)'),
                subtitle: Text(_hasPw ? (_numeric ? 'القفل مفعّل — PIN رقمي' : 'القفل مفعّل — كلمة مرور') : 'التطبيق غير محمي حاليًا'),
                onTap: _setPassword,
              ),
              if (_hasPw)
                SwitchListTile(
                  secondary: const Icon(Icons.fingerprint),
                  title: const Text('الفتح بالبصمة'),
                  subtitle: Text(_bioSubtitle),
                  value: _bio && _bioStatus == BioStatus.ready,
                  onChanged: _bioStatus == BioStatus.ready ? _toggleBio : null,
                ),
              if (_hasPw)
                ListTile(
                  leading: const Icon(Icons.timer_outlined),
                  title: const Text('القفل التلقائي'),
                  subtitle: Text('بعد ${_graceOptions[_grace] ?? '$_grace ثانية'} من مغادرة التطبيق'),
                  onTap: _pickGrace,
                ),
              if (_hasPw)
                ListTile(
                  leading: const Icon(Icons.lock_clock),
                  title: const Text('قفل التطبيق الآن'),
                  onTap: () => Security.lockSignal.value++,
                ),
              if (_hasPw)
                ListTile(
                  leading: const Icon(Icons.lock_open),
                  title: const Text('إلغاء القفل'),
                  onTap: _removePassword,
                ),
            ]),
          ),
          Card(
            child: Column(children: [
              ListTile(
                leading: const Icon(Icons.auto_awesome),
                title: const Text('المساعد القانوني الذكي'),
                subtitle: const Text('فتح المحادثة (Gemini): تلخيص وتحليل المستندات والمذكرات'),
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AiScreen())),
              ),
              ListTile(
                leading: const Icon(Icons.key),
                title: const Text('مفتاح المساعد الذكي والخصوصية'),
                subtitle: const Text('مفتاح Gemini، اسم الموديل، حجب البيانات الشخصية'),
                onTap: () => showAiSettings(context),
              ),
            ]),
          ),
          Card(
            child: Column(children: [
              ListTile(
                leading: const Icon(Icons.backup_outlined),
                title: const Text('نسخ احتياطي'),
                subtitle: const Text('تصدير كل البيانات والصور وملفات المكتبة في ملف JSON واحد للحفظ أو المشاركة'),
                onTap: _busy ? null : _backup,
              ),
              ListTile(
                leading: const Icon(Icons.restore),
                title: const Text('استعادة نسخة احتياطية'),
                subtitle: const Text('استيراد ملف JSON (يستبدل البيانات الحالية)'),
                onTap: _busy ? null : _restore,
              ),
            ]),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.notifications_active_outlined),
              title: const Text('اختبار التنبيهات'),
              subtitle: const Text('تنبيه قبل الجلسة بيوم (6 مساءً) وصباح يوم الجلسة (7:30)'),
              onTap: () async {
                await Notifier.testNow();
                await Notifier.rescheduleAll();
              },
            ),
          ),
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'أجندة المحامي القانونية • الإصدار 5.0\nجميع البيانات محفوظة على جهازك فقط. لا يتصل التطبيق بالإنترنت إلا عند استخدام المساعد الذكي أو تنزيل ملف من رابط.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12),
            ),
          ),
        ]),
        if (_busy) const Positioned.fill(child: ColoredBox(color: Color(0x66000000), child: Center(child: CircularProgressIndicator()))),
      ]),
    );
  }
}
