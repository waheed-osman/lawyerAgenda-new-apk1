String _s(Object? v) => (v as String?) ?? '';
int? _n(Object? v) => (v as num?)?.toInt();

/// أنواع الجهات في دليل المحاكم.
const courtKinds = [
  'محكمة جزئية',
  'محكمة ابتدائية',
  'محكمة استئناف',
  'محكمة جنايات',
  'محكمة الأسرة',
  'محكمة اقتصادية',
  'محكمة عمالية',
  'محكمة النقض',
  'محكمة القضاء الإداري',
  'مجمع محاكم',
  'نيابة',
  'قسم / مركز شرطة',
  'أخرى',
];

/// محافظات مصر (27).
const governorates = [
  'القاهرة', 'الجيزة', 'الإسكندرية', 'القليوبية', 'الشرقية', 'الدقهلية', 'الغربية', 'المنوفية',
  'كفر الشيخ', 'البحيرة', 'دمياط', 'بورسعيد', 'الإسماعيلية', 'السويس', 'شمال سيناء', 'جنوب سيناء',
  'الفيوم', 'بني سويف', 'المنيا', 'أسيوط', 'سوهاج', 'قنا', 'الأقصر', 'أسوان', 'البحر الأحمر',
  'الوادي الجديد', 'مطروح',
];

/// جهة قضائية في الدليل (محكمة / نيابة / قسم...). البيانات يُدخلها المحامي بنفسه
/// فلا يعتمد التطبيق على معلومات اختصاص مضمّنة قد تتغير.
class Court {
  int? id;
  String name, kind, governorate, address, phone, mapUrl, jurisdiction, notes;
  int createdAt;

  Court({
    this.id,
    this.name = '',
    this.kind = '',
    this.governorate = '',
    this.address = '',
    this.phone = '',
    this.mapUrl = '',
    this.jurisdiction = '',
    this.notes = '',
    int? createdAt,
  }) : createdAt = createdAt ?? DateTime.now().millisecondsSinceEpoch;

  factory Court.fromMap(Map<String, Object?> m) => Court(
        id: _n(m['id']),
        name: _s(m['name']),
        kind: _s(m['kind']),
        governorate: _s(m['governorate']),
        address: _s(m['address']),
        phone: _s(m['phone']),
        mapUrl: _s(m['map_url']),
        jurisdiction: _s(m['jurisdiction']),
        notes: _s(m['notes']),
        createdAt: _n(m['created_at']),
      );

  Map<String, Object?> toMap() => {
        'id': id,
        'name': name,
        'kind': kind,
        'governorate': governorate,
        'address': address,
        'phone': phone,
        'map_url': mapUrl,
        'jurisdiction': jurisdiction,
        'notes': notes,
        'created_at': createdAt,
      };

  /// سطر وصف مختصر: النوع • المحافظة.
  String get subtitle => [kind, governorate].where((e) => e.trim().isNotEmpty).join(' • ');

  /// نص للمشاركة (واتساب مثلًا).
  String get shareText => [
        name,
        if (subtitle.isNotEmpty) subtitle,
        if (address.trim().isNotEmpty) 'العنوان: $address',
        if (phone.trim().isNotEmpty) 'الهاتف: $phone',
        if (mapUrl.trim().startsWith('http')) 'الموقع: ${mapUrl.trim()}',
      ].join('\n');

  /// رابط الخريطة: الرابط المحفوظ إن وُجد، وإلا بحث في خرائط جوجل بالاسم والعنوان.
  Uri get mapUri {
    final u = Uri.tryParse(mapUrl.trim());
    if (u != null && (u.scheme == 'http' || u.scheme == 'https') && u.host.isNotEmpty) return u;
    final q = [name, address, governorate].where((e) => e.trim().isNotEmpty).join(' ');
    return Uri.https('www.google.com', '/maps/search/', {'api': '1', 'query': q});
  }
}
