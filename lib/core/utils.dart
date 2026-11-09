import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

const caseTypes = [
  'مدني', 'جنائي', 'أسرة', 'تجاري', 'إداري', 'عمالي', 'جنح', 'جنح توريد', 'جنايات',
  'إيجارات', 'ضرائب', 'أحوال شخصية', 'أخرى'
];

/// تصنيفات المذكرات والمستندات النصية داخل القضية.
const docCategories = ['مذكرة دفاع', 'طعن', 'صحيفة / عريضة', 'مستند', 'ملاحظات عمل', 'أخرى'];

/// أنواع الحركات المالية.
/// fee = أتعاب متفق عليها • payment = دفعة أتعاب مستلمة
/// deposit = أمانة مستلمة من الموكل • expense = مصروفات قضائية (تُخصم من الأمانة)
const moneyKinds = <String, String>{
  'fee': 'أتعاب متفق عليها',
  'payment': 'دفعة أتعاب',
  'deposit': 'أمانة مستلمة',
  'expense': 'مصروفات قضائية',
};

const appointmentColor = Color(0xFF00838F);

/// أنواع المواعيد والمواعيد القانونية (لا ترتبط بقضية بالضرورة).
/// legal = ميعاد قانوني/إجرائي يُنبَّه له قبلها بأيام.
class ApptKind {
  final String label;
  final Color color;
  final bool legal;
  const ApptKind(this.label, this.color, {this.legal = false});
}

const appointmentKinds = <String, ApptKind>{
  'certificate': ApptKind('تقديم على شهادة', Color(0xFF6D4C41), legal: true),
  'opposition': ApptKind('معارضة', Color(0xFFD84315), legal: true),
  'appeal': ApptKind('استئناف', Color(0xFFC62828), legal: true),
  'cassation': ApptKind('نقض', Color(0xFF6A1B9A), legal: true),
  'fees': ApptKind('سداد رسوم', Color(0xFFEF6C00)),
  'copy': ApptKind('استلام صورة', Color(0xFF2E7D32)),
  'meeting': ApptKind('اجتماع', Color(0xFF00838F)),
  'other': ApptKind('أخرى', Color(0xFF546E7A)),
};

ApptKind apptKind(String k) => appointmentKinds[k] ?? appointmentKinds['other']!;

String fmtTime(int minutes) =>
    '${(minutes ~/ 60).toString().padLeft(2, '0')}:${(minutes % 60).toString().padLeft(2, '0')}';

/// يقبل الأرقام العربية (٠-٩) والإنجليزية، ويتجاهل فواصل الآلاف.
double? parseAmount(String s) {
  const ar = '٠١٢٣٤٥٦٧٨٩';
  final b = StringBuffer();
  for (final ch in s.trim().runes.map(String.fromCharCode)) {
    final i = ar.indexOf(ch);
    if (i >= 0) {
      b.write(i);
    } else if (ch == ',' || ch == '،') {
      continue;
    } else if (ch == '٫') {
      b.write('.');
    } else {
      b.write(ch);
    }
  }
  return double.tryParse(b.toString());
}

const caseStatuses = <String, String>{
  'active': 'جارية',
  'postponed': 'مؤجلة',
  'won': 'مكتسبة',
  'lost': 'خاسرة',
};

const sessionTypes = <String, String>{
  'pleading': 'مرافعة',
  'verdict': 'حكم',
  'announce': 'تأجيل لإعلان',
  'experts': 'خبراء',
  'investigation': 'تحقيق',
  'other': 'أخرى',
};

const clientRoles = ['مدعي', 'مدعى عليه', 'متهم', 'مجني عليه', 'طالب', 'مطلوب ضده'];

const templateCategories = [
  'أحكام نقض', 'صحف دعاوى', 'مذكرات', 'طعون', 'إنذارات', 'عقود', 'طلبات', 'أخرى'
];

Color statusColor(String s) {
  switch (s) {
    case 'active':
      return const Color(0xFF1E88E5);
    case 'postponed':
      return const Color(0xFFF59E0B);
    case 'won':
      return const Color(0xFF2E9E5B);
    case 'lost':
      return const Color(0xFFD64545);
  }
  return Colors.grey;
}

Color sessionColor(String t) {
  switch (t) {
    case 'pleading':
      return const Color(0xFF1E88E5);
    case 'verdict':
      return const Color(0xFFD64545);
    case 'announce':
      return const Color(0xFFF59E0B);
    case 'experts':
      return const Color(0xFF8E44AD);
    case 'investigation':
      return const Color(0xFF00897B);
  }
  return const Color(0xFF78909C);
}

DateTime dayStart(DateTime d) => DateTime(d.year, d.month, d.day);
DateTime addDays(DateTime d, int n) => DateTime(d.year, d.month, d.day + n);

String fmtDate(DateTime d) => DateFormat('EEEE d MMMM y', 'ar').format(d);
String fmtShort(DateTime d) => DateFormat('y/MM/dd', 'en').format(d);
String fmtMoney(num v) => NumberFormat('#,##0.##', 'en').format(v);

String caseLabel(String number, String year) =>
    year.trim().isEmpty ? 'قضية رقم $number' : 'قضية رقم $number لسنة $year';

String relText(DateTime d) {
  final n = dayStart(d).difference(dayStart(DateTime.now())).inDays;
  if (n == 0) return 'اليوم';
  if (n == 1) return 'غدًا';
  if (n == 2) return 'بعد يومين';
  if (n > 2 && n <= 10) return 'بعد $n أيام';
  if (n > 10) return 'بعد $n يومًا';
  if (n == -1) return 'أمس';
  if (n == -2) return 'منذ يومين';
  if (n < -2 && n >= -10) return 'منذ ${-n} أيام';
  return 'منذ ${-n} يومًا';
}

void toast(BuildContext c, String m) {
  ScaffoldMessenger.of(c)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(m)));
}

Future<bool> confirm(BuildContext c, String msg, {String ok = 'تأكيد'}) async {
  final r = await showDialog<bool>(
    context: c,
    builder: (ctx) => AlertDialog(
      content: Text(msg),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(ok)),
      ],
    ),
  );
  return r ?? false;
}

String fmtBytes(int b) {
  if (b < 1024) return '$b B';
  if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(0)} KB';
  return '${(b / 1024 / 1024).toStringAsFixed(1)} MB';
}
