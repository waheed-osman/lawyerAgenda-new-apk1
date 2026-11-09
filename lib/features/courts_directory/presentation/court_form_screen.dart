import 'package:flutter/material.dart';

import '../../../core/widgets.dart';
import '../data/court.dart';
import '../data/courts_repo.dart';

/// إضافة / تعديل جهة في دليل المحاكم.
class CourtFormScreen extends StatefulWidget {
  final Court? court;
  const CourtFormScreen({super.key, this.court});
  @override
  State<CourtFormScreen> createState() => _CourtFormScreenState();
}

class _CourtFormScreenState extends State<CourtFormScreen> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.court?.name ?? '');
  late final _address = TextEditingController(text: widget.court?.address ?? '');
  late final _phone = TextEditingController(text: widget.court?.phone ?? '');
  late final _map = TextEditingController(text: widget.court?.mapUrl ?? '');
  late final _jur = TextEditingController(text: widget.court?.jurisdiction ?? '');
  late final _notes = TextEditingController(text: widget.court?.notes ?? '');
  late String? _kind = courtKinds.contains(widget.court?.kind) ? widget.court!.kind : null;
  late String? _gov = governorates.contains(widget.court?.governorate) ? widget.court!.governorate : null;

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final x = widget.court ?? Court();
    x
      ..name = _name.text.trim()
      ..kind = _kind ?? ''
      ..governorate = _gov ?? ''
      ..address = _address.text.trim()
      ..phone = _phone.text.trim()
      ..mapUrl = _map.text.trim()
      ..jurisdiction = _jur.text.trim()
      ..notes = _notes.text.trim();
    await CourtsRepo.save(x);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.court == null ? 'جهة جديدة' : 'تعديل الجهة'),
        actions: [IconButton(onPressed: _save, icon: const Icon(Icons.check), tooltip: 'حفظ')],
      ),
      body: Form(
        key: _form,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          tf(_name, 'اسم المحكمة / الجهة', icon: Icons.account_balance, required: true),
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: DropdownButtonFormField<String>(
              value: _kind,
              decoration: dec('النوع'),
              items: [for (final k in courtKinds) DropdownMenuItem(value: k, child: Text(k))],
              onChanged: (v) => setState(() => _kind = v),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: DropdownButtonFormField<String>(
              value: _gov,
              decoration: dec('المحافظة'),
              items: [for (final g in governorates) DropdownMenuItem(value: g, child: Text(g))],
              onChanged: (v) => setState(() => _gov = v),
            ),
          ),
          tf(_address, 'العنوان', icon: Icons.place_outlined, maxLines: 2),
          tf(_phone, 'الهاتف', icon: Icons.call, type: TextInputType.phone),
          tf(_map, 'رابط الموقع على خرائط جوجل (اختياري)', icon: Icons.link, type: TextInputType.url),
          const Padding(
            padding: EdgeInsets.fromLTRB(4, 0, 4, 12),
            child: Text(
                'للحصول على الرابط: افتح المكان في خرائط جوجل ← مشاركة ← نسخ الرابط، ثم الصقه هنا. '
                'إن تركته فارغًا يبحث التطبيق بالاسم والعنوان.',
                style: TextStyle(fontSize: 12)),
          ),
          tf(_jur, 'الاختصاص (مكاني / نوعي) ودوائرها', icon: Icons.rule, maxLines: 4),
          tf(_notes, 'ملاحظات', icon: Icons.notes, maxLines: 3),
          const SizedBox(height: 8),
          FilledButton.icon(onPressed: _save, icon: const Icon(Icons.save), label: const Text('حفظ')),
        ]),
      ),
    );
  }
}
