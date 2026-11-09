import '../../../data/db.dart';
import 'court.dart';

/// الوصول لجدول courts (يستخدم نفس قاعدة البيانات ويُبلّغ Live بالتحديث عبر Db.i.changed()).
class CourtsRepo {
  static Future<List<Court>> list({String? q, String? governorate}) async {
    final d = await Db.i.db;
    final where = <String>[];
    final args = <Object?>[];
    if (governorate != null) {
      where.add('governorate=?');
      args.add(governorate);
    }
    if (q != null && q.trim().isNotEmpty) {
      where.add('(name LIKE ? OR address LIKE ? OR jurisdiction LIKE ? OR notes LIKE ? OR kind LIKE ?)');
      final l = '%${q.trim()}%';
      args.addAll([l, l, l, l, l]);
    }
    final r = await d.query('courts',
        where: where.isEmpty ? null : where.join(' AND '),
        whereArgs: args,
        orderBy: 'governorate COLLATE NOCASE, name COLLATE NOCASE');
    return r.map(Court.fromMap).toList();
  }

  static Future<Court?> get(int id) async {
    final d = await Db.i.db;
    final r = await d.query('courts', where: 'id=?', whereArgs: [id]);
    return r.isEmpty ? null : Court.fromMap(r.first);
  }

  /// المحافظات التي فيها جهات مسجلة (لأزرار التصفية).
  static Future<List<String>> governoratesInUse() async {
    final d = await Db.i.db;
    final r = await d.rawQuery(
        "SELECT DISTINCT governorate FROM courts WHERE TRIM(IFNULL(governorate,''))<>'' ORDER BY governorate COLLATE NOCASE");
    return r.map((e) => e['governorate'] as String).toList();
  }

  static Future<int> save(Court c) async {
    final d = await Db.i.db;
    final m = c.toMap();
    int id;
    if (c.id == null) {
      m.remove('id');
      id = await d.insert('courts', m);
    } else {
      await d.update('courts', m, where: 'id=?', whereArgs: [c.id]);
      id = c.id!;
    }
    Db.i.changed();
    return id;
  }

  static Future<void> delete(int id) async {
    final d = await Db.i.db;
    await d.delete('courts', where: 'id=?', whereArgs: [id]);
    Db.i.changed();
  }
}
