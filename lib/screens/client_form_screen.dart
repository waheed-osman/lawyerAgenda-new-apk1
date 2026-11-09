import 'package:flutter/material.dart';

import '../core/utils.dart';
import '../core/widgets.dart';
import '../data/db.dart';
import '../data/models.dart';

/// Pops with the saved client's id.
class ClientFormScreen extends StatefulWidget {
  final int? clientId;
  const ClientFormScreen({super.key, this.clientId});
  @override
  State<ClientFormScreen> createState() => _ClientFormScreenState();
}

class _ClientFormScreenState extends State<ClientFormScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _address = TextEditingController();
  final _nid = TextEditingController();
  final _notes = TextEditingController();
  Client? _orig;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    if (widget.clientId != null) {
      final c = await Db.i.client(widget.clientId!);
      if (c != null) {
        _orig = c;
        _name.text = c.name;
        _phone.text = c.phone;
        _email.text = c.email;
        _address.text = c.address;
        _nid.text = c.nationalId;
        _notes.text = c.notes;
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    if (_orig == null) {
      // منع تكرار الموكل: لو الاسم موجود، اعرض الموكل الحالي بدل إنشاء نسخة ثانية.
      final same = (await Db.i.clients(q: _name.text.trim()))
          .where((x) => x.name.trim() == _name.text.trim())
          .toList();
      if (same.isNotEmpty && mounted) {
        final ok = await confirm(context,
            'يوجد موكل بنفس الاسم (${same.first.casesCount} قضية). الأفضل إضافة القضية الجديدة له بدل تكراره. هل تريد إنشاء موكل جديد بنفس الاسم؟',
            ok: 'إنشاء جديد');
        if (!ok) return;
      }
    }
    final c = _orig ?? Client();
    c
      ..name = _name.text.trim()
      ..phone = _phone.text.trim()
      ..email = _email.text.trim()
      ..address = _address.text.trim()
      ..nationalId = _nid.text.trim()
      ..notes = _notes.text.trim();
    final id = await Db.i.saveClient(c);
    if (mounted) Navigator.pop(context, id);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.clientId == null ? 'موكل جديد' : 'تعديل الموكل'),
        actions: [IconButton(onPressed: _save, icon: const Icon(Icons.check), tooltip: 'حفظ')],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _form,
              child: ListView(padding: const EdgeInsets.all(16), children: [
                tf(_name, 'الاسم', icon: Icons.person_outline, required: true),
                tf(_phone, 'رقم الهاتف', icon: Icons.phone_outlined, type: TextInputType.phone),
                tf(_email, 'البريد الإلكتروني', icon: Icons.email_outlined, type: TextInputType.emailAddress),
                tf(_address, 'العنوان', icon: Icons.location_on_outlined),
                tf(_nid, 'الرقم القومي / الهوية', icon: Icons.badge_outlined, type: TextInputType.number),
                tf(_notes, 'ملاحظات خاصة', maxLines: 4),
                const SizedBox(height: 8),
                FilledButton.icon(onPressed: _save, icon: const Icon(Icons.save), label: const Text('حفظ')),
              ]),
            ),
    );
  }
}
