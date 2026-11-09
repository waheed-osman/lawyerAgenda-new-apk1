import 'package:flutter/material.dart';

import '../core/widgets.dart';
import 'case_detail_screen.dart';
import 'case_form_screen.dart';
import '../data/db.dart';
import '../data/models.dart';
import 'client_detail_screen.dart';
import 'client_form_screen.dart';

class ClientsScreen extends StatefulWidget {
  const ClientsScreen({super.key});
  @override
  State<ClientsScreen> createState() => _ClientsScreenState();
}

class _ClientsScreenState extends State<ClientsScreen> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('الموكلون')),
      floatingActionButton: FloatingActionButton(
        tooltip: 'موكل جديد',
        onPressed: () =>
            Navigator.push(context, MaterialPageRoute(builder: (_) => const ClientFormScreen())),
        child: const Icon(Icons.person_add_alt_1),
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: TextField(
            decoration: const InputDecoration(
                hintText: 'بحث بالاسم أو الهاتف أو الرقم القومي', prefixIcon: Icon(Icons.search), isDense: true),
            onChanged: (v) => setState(() => _q = v),
          ),
        ),
        Expanded(
          child: Live<(List<Client>, List<LegalCase>)>(
            load: () async => (await Db.i.clients(q: _q), await Db.i.cases()),
            builder: (c, data) {
              final list = data.$1;
              final byClient = <int, List<LegalCase>>{};
              for (final x in data.$2) {
                if (x.clientId != null) byClient.putIfAbsent(x.clientId!, () => []).add(x);
              }
              if (list.isEmpty) return const EmptyState(icon: Icons.people_outline, text: 'لا يوجد موكلون');
              return ListView.builder(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 88),
                itemCount: list.length,
                itemBuilder: (_, i) {
                  final cl = list[i];
                  final cases = byClient[cl.id] ?? const <LegalCase>[];
                  return Card(
                    clipBehavior: Clip.antiAlias,
                    child: ExpansionTile(
                      key: PageStorageKey('client_${cl.id}'),
                      shape: const Border(),
                      collapsedShape: const Border(),
                      leading: CircleAvatar(child: Text(cl.name.isEmpty ? '?' : cl.name.characters.first)),
                      title: Text(cl.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text([cl.phone, '${cases.length} قضية'].where((e) => e.isNotEmpty).join(' • ')),
                      childrenPadding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                      children: [
                        for (final k in cases)
                          CaseCard(
                            c: k,
                            onTap: () => Navigator.push(
                                c, MaterialPageRoute(builder: (_) => CaseDetailScreen(caseId: k.id!))),
                          ),
                        Row(children: [
                          TextButton.icon(
                            onPressed: () => Navigator.push(
                                c, MaterialPageRoute(builder: (_) => CaseFormScreen(clientId: cl.id))),
                            icon: const Icon(Icons.add),
                            label: const Text('قضية جديدة لهذا الموكل'),
                          ),
                          const Spacer(),
                          TextButton.icon(
                            onPressed: () => Navigator.push(
                                c, MaterialPageRoute(builder: (_) => ClientDetailScreen(clientId: cl.id!))),
                            icon: const Icon(Icons.person_outline),
                            label: const Text('ملف الموكل'),
                          ),
                        ]),
                      ],
                    ),
                  );
                },
              );
            },
          ),
        ),
      ]),
    );
  }
}
