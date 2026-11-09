import 'package:flutter/material.dart';

import '../core/utils.dart';
import '../core/widgets.dart';
import '../data/db.dart';
import '../data/models.dart';
import '../features/courts_directory/data/court.dart';
import '../features/courts_directory/presentation/courts_screen.dart';
import 'client_form_screen.dart';

class CaseFormScreen extends StatefulWidget {
  final int? caseId;
  final int? clientId;
  const CaseFormScreen({super.key, this.caseId, this.clientId});
  @override
  State<CaseFormScreen> createState() => _CaseFormScreenState();
}

class _CaseFormScreenState extends State<CaseFormScreen> {
  final _form = GlobalKey<FormState>();
  final _number = TextEditingController();
  final _year = TextEditingController(text: DateTime.now().year.toString());
  final _circuit = TextEditingController();
  final _court = TextEditingController();
  final _opponent = TextEditingController();
  final _title = TextEditingController();
  final _notes = TextEditingController();
  String _role = clientRoles.first;
  String _type = caseTypes.first;
  String _status = 'active';
  int? _clientId;
  LegalCase? _orig;
  List<Client> _clients = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    _clients = await Db.i.clients();
    _clientId = widget.clientId;
    if (widget.caseId != null) {
      final c = await Db.i.legalCase(widget.caseId!);
      if (c != null) {
        _orig = c;
        _number.text = c.number;
        _year.text = c.year;
        _circuit.text = c.circuit;
        _court.text = c.court;
        _opponent.text = c.opponent;
        _title.text = c.title;
        _notes.text = c.notes;
        _role = clientRoles.contains(c.clientRole) ? c.clientRole : clientRoles.first;
        _type = caseTypes.contains(c.type) ? c.type : caseTypes.last;
        _status = c.status;
        _clientId = c.clientId;
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _newClient() async {
    final id = await Navigator.push<int>(
        context, MaterialPageRoute(builder: (_) => const ClientFormScreen()));
    if (id != null) {
      _clients = await Db.i.clients();
      setState(() => _clientId = id);
    }
  }

  /// يفتح دليل المحاكم لاختيار جهة وكتابة اسمها في خانة المحكمة.
  Future<void> _pickCourt() async {
    final x = await Navigator.push<Court>(
        context, MaterialPageRoute(builder: (_) => const CourtsScreen(pick: true)));
    if (x != null) setState(() => _court.text = x.name);
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final c = _orig ?? LegalCase();
    c
      ..number = _number.text.trim()
      ..year = _year.text.trim()
      ..circuit = _circuit.text.trim()
      ..court = _court.text.trim()
      ..opponent = _opponent.text.trim()
      ..title = _title.text.trim()
      ..notes = _notes.text.trim()
      ..clientRole = _role
      ..type = _type
      ..status = _status
      ..clientId = _clientId;
    final id = await Db.i.saveCase(c);
    if (mounted) Navigator.pop(context, id);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.caseId == null ? 'قضية جديدة' : 'تعديل القضية'),
        actions: [IconButton(onPressed: _save, icon: const Icon(Icons.check), tooltip: 'حفظ')],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _form,
              child: ListView(padding: const EdgeInsets.all(16), children: [
                Row(children: [
                  Expanded(flex: 2, child: tf(_number, 'رقم القضية', type: TextInputType.number, required: true)),
                  const SizedBox(width: 10),
                  Expanded(child: tf(_year, 'السنة', type: TextInputType.number)),
                ]),
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(child: tf(_court, 'المحكمة التابعة', icon: Icons.account_balance)),
                  Padding(
                    padding: const EdgeInsets.only(top: 4, right: 4),
                    child: IconButton(
                      tooltip: 'اختيار من دليل المحاكم',
                      icon: const Icon(Icons.list_alt),
                      onPressed: _pickCourt,
                    ),
                  ),
                ]),
                tf(_circuit, 'الدائرة', icon: Icons.meeting_room_outlined),
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: DropdownButtonFormField<int?>(
                        value: _clients.any((c) => c.id == _clientId) ? _clientId : null,
                        isExpanded: true,
                        decoration: dec('الموكل', icon: Icons.person_outline),
                        items: [
                          const DropdownMenuItem<int?>(value: null, child: Text('— بدون —')),
                          for (final c in _clients) DropdownMenuItem<int?>(value: c.id, child: Text(c.name)),
                        ],
                        onChanged: (v) => setState(() => _clientId = v),
                      ),
                    ),
                  ),
                  IconButton.filledTonal(
                      onPressed: _newClient, icon: const Icon(Icons.person_add_alt), tooltip: 'موكل جديد'),
                ]),
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: DropdownButtonFormField<String>(
                    value: _role,
                    decoration: dec('صفة الموكل في الدعوى'),
                    items: [for (final r in clientRoles) DropdownMenuItem(value: r, child: Text(r))],
                    onChanged: (v) => setState(() => _role = v!),
                  ),
                ),
                tf(_opponent, 'الخصم', icon: Icons.person_off_outlined),
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: DropdownButtonFormField<String>(
                    value: _type,
                    decoration: dec('نوع القضية'),
                    items: [for (final t in caseTypes) DropdownMenuItem(value: t, child: Text(t))],
                    onChanged: (v) => setState(() => _type = v!),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: DropdownButtonFormField<String>(
                    value: _status,
                    decoration: dec('حالة القضية'),
                    items: [
                      for (final e in caseStatuses.entries) DropdownMenuItem(value: e.key, child: Text(e.value))
                    ],
                    onChanged: (v) => setState(() => _status = v!),
                  ),
                ),
                tf(_title, 'موضوع الدعوى', icon: Icons.subject),
                tf(_notes, 'ملاحظات', maxLines: 5),
                const SizedBox(height: 8),
                FilledButton.icon(onPressed: _save, icon: const Icon(Icons.save), label: const Text('حفظ')),
              ]),
            ),
    );
  }
}
