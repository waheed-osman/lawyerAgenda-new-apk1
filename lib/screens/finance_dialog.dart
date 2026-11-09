import 'package:flutter/material.dart';

import '../core/utils.dart';
import '../core/widgets.dart';
import '../data/db.dart';
import '../data/models.dart';

/// نافذة تسجيل حركة مالية (أتعاب / دفعة / أمانة / مصروفات) لموكل،
/// ويمكن ربطها بقضية معينة. تُستخدم من شاشة الموكل وشاشة القضية.
Future<void> showPaymentDialog(
  BuildContext context, {
  required int clientId,
  required String kind,
  List<LegalCase> cases = const [],
  int? caseId,
}) async {
  final amount = TextEditingController();
  final note = TextEditingController();
  var date = dayStart(DateTime.now());
  int? selectedCase = cases.any((c) => c.id == caseId) ? caseId : null;
  await showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) => AlertDialog(
        title: Text('تسجيل: ${moneyKinds[kind] ?? kind}'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              controller: amount,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: dec('المبلغ'),
            ),
            const SizedBox(height: 10),
            TextButton.icon(
              icon: const Icon(Icons.event),
              label: Text(fmtShort(date)),
              onPressed: () async {
                final d = await pickDate(ctx, date);
                if (d != null) setS(() => date = dayStart(d));
              },
            ),
            if (cases.isNotEmpty)
              DropdownButtonFormField<int?>(
                value: selectedCase,
                isExpanded: true,
                decoration: dec('القضية (اختياري)'),
                items: [
                  const DropdownMenuItem<int?>(value: null, child: Text('— عام —')),
                  for (final x in cases)
                    DropdownMenuItem<int?>(value: x.id, child: Text(caseLabel(x.number, x.year))),
                ],
                onChanged: (v) => setS(() => selectedCase = v),
              ),
            const SizedBox(height: 10),
            TextField(controller: note, decoration: dec('ملاحظة')),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          FilledButton(
            onPressed: () async {
              final v = parseAmount(amount.text);
              if (v == null || v <= 0) return;
              await Db.i.savePayment(Payment(
                clientId: clientId,
                caseId: selectedCase,
                kind: kind,
                amount: v,
                date: date,
                note: note.text.trim(),
              ));
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('حفظ'),
          ),
        ],
      ),
    ),
  );
}
