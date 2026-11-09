import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/utils.dart';
import '../../../core/widgets.dart';
import '../../../data/db.dart';
import '../../../data/models.dart';
import '../../../screens/case_detail_screen.dart';
import '../../../services/security.dart';
import '../data/court.dart';
import '../data/courts_repo.dart';
import 'court_form_screen.dart';

/// تفاصيل جهة: أزرار الخريطة والاتصال والنسخ، والاختصاص، والقضايا المسجلة بنفس اسم المحكمة.
class CourtDetailScreen extends StatelessWidget {
  final int id;
  const CourtDetailScreen({super.key, required this.id});

  Future<void> _open(BuildContext context, Uri uri) async {
    try {
      final ok = await Security.guard(() => launchUrl(uri, mode: LaunchMode.externalApplication));
      if (!ok && context.mounted) toast(context, 'تعذّر فتح التطبيق المناسب');
    } catch (_) {
      if (context.mounted) toast(context, 'تعذّر فتح التطبيق المناسب');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Live<Court?>(
      load: () => CourtsRepo.get(id),
      builder: (c, x) {
        if (x == null) {
          return Scaffold(appBar: AppBar(), body: const EmptyState(icon: Icons.account_balance, text: 'غير موجود'));
        }
        return Scaffold(
          appBar: AppBar(
            title: Text(x.name, style: const TextStyle(fontSize: 17)),
            actions: [
              IconButton(
                tooltip: 'مشاركة',
                icon: const Icon(Icons.share),
                onPressed: () => Security.guard(() => Share.share(x.shareText, subject: x.name)),
              ),
              IconButton(
                tooltip: 'تعديل',
                icon: const Icon(Icons.edit_outlined),
                onPressed: () =>
                    Navigator.push(c, MaterialPageRoute(builder: (_) => CourtFormScreen(court: x))),
              ),
              IconButton(
                tooltip: 'حذف',
                icon: const Icon(Icons.delete_outline),
                onPressed: () async {
                  if (await confirm(c, 'حذف هذه الجهة من الدليل؟ (القضايا المسجلة لا تتأثر)', ok: 'حذف')) {
                    await CourtsRepo.delete(x.id!);
                    if (c.mounted) Navigator.pop(c);
                  }
                },
              ),
            ],
          ),
          body: ListView(padding: const EdgeInsets.all(16), children: [
            Wrap(spacing: 8, runSpacing: 8, children: [
              FilledButton.icon(
                onPressed: () => _open(c, x.mapUri),
                icon: const Icon(Icons.map_outlined),
                label: const Text('الخريطة'),
              ),
              if (x.phone.trim().isNotEmpty)
                OutlinedButton.icon(
                  onPressed: () => _open(c, Uri(scheme: 'tel', path: x.phone.trim())),
                  icon: const Icon(Icons.call),
                  label: const Text('اتصال'),
                ),
              if (x.address.trim().isNotEmpty)
                OutlinedButton.icon(
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: x.address));
                    toast(c, 'تم نسخ العنوان');
                  },
                  icon: const Icon(Icons.copy),
                  label: const Text('نسخ العنوان'),
                ),
            ]),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(children: [
                  InfoRow('النوع', x.kind),
                  InfoRow('المحافظة', x.governorate),
                  InfoRow('العنوان', x.address),
                  InfoRow('الهاتف', x.phone, onTap: () {
                    Clipboard.setData(ClipboardData(text: x.phone));
                    toast(c, 'تم نسخ الرقم');
                  }),
                  InfoRow('الاختصاص', x.jurisdiction),
                  InfoRow('ملاحظات', x.notes),
                ]),
              ),
            ),
            Live<List<LegalCase>>(
              load: () => Db.i.cases(q: x.name),
              builder: (cc, cases) => cases.isEmpty
                  ? const SizedBox.shrink()
                  : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const SectionTitle('قضاياك المسجلة بهذه المحكمة'),
                      for (final cs in cases.take(15))
                        CaseCard(
                          c: cs,
                          onTap: () => Navigator.push(
                              cc, MaterialPageRoute(builder: (_) => CaseDetailScreen(caseId: cs.id!))),
                        ),
                    ]),
            ),
          ]),
        );
      },
    );
  }
}
