import 'package:flutter/material.dart';

import '../data/models.dart';
import 'widgets.dart';

/// تجميع القضايا حسب الموكل: كل موكل مرة واحدة كقائمة قابلة للطي تحتها قضاياه.
/// القضايا بدون موكل تُجمَّع تحت "بدون موكل".
Widget groupedCasesList(
  List<LegalCase> list, {
  required void Function(LegalCase) onOpen,
  EdgeInsets padding = const EdgeInsets.fromLTRB(12, 4, 12, 88),
}) {
  final groups = <int?, List<LegalCase>>{};
  for (final c in list) {
    groups.putIfAbsent(c.clientId, () => []).add(c);
  }
  final keys = groups.keys.toList()
    ..sort((a, b) {
      if (a == null) return 1;
      if (b == null) return -1;
      return groups[a]!.first.clientName.compareTo(groups[b]!.first.clientName);
    });
  return ListView(padding: padding, children: [
    for (final k in keys)
      Card(
        clipBehavior: Clip.antiAlias,
        child: ExpansionTile(
          key: PageStorageKey('grp_${k ?? 'none'}'),
          shape: const Border(),
          collapsedShape: const Border(),
          leading: CircleAvatar(
              child: Text(k == null || groups[k]!.first.clientName.isEmpty
                  ? '?'
                  : groups[k]!.first.clientName.characters.first)),
          title: Text(k == null || groups[k]!.first.clientName.isEmpty ? 'بدون موكل' : groups[k]!.first.clientName,
              style: const TextStyle(fontWeight: FontWeight.bold)),
          subtitle: Text('${groups[k]!.length} قضية'),
          childrenPadding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
          children: [for (final c in groups[k]!) CaseCard(c: c, onTap: () => onOpen(c))],
        ),
      ),
  ]);
}
