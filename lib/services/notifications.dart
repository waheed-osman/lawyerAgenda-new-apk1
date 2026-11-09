import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../core/utils.dart';
import '../data/db.dart';
import '../data/models.dart';

/// Local (offline) reminders: the evening before (18:00) and the morning of
/// the session day (07:30).
class Notifier {
  static final _plugin = FlutterLocalNotificationsPlugin();

  static const _details = NotificationDetails(
    android: AndroidNotificationDetails(
      'sessions',
      'تنبيهات الجلسات',
      channelDescription: 'تذكير بمواعيد الجلسات القادمة',
      importance: Importance.max,
      priority: Priority.high,
    ),
  );

  static Future<void> init() async {
    tzdata.initializeTimeZones();
    try {
      final name = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(name));
    } catch (_) {
      tz.setLocalLocation(tz.getLocation('Africa/Cairo'));
    }
    const init = InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher'));
    await _plugin.initialize(init);
    await _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
  }

  static String _body(CaseSession s) {
    final parts = <String>[
      sessionTypes[s.type] ?? '',
      caseLabel(s.caseNumber, s.caseYear),
      if (s.clientName.isNotEmpty) s.clientName,
      if (s.court.isNotEmpty) s.court,
      if (s.roll.isNotEmpty) 'رول ${s.roll}',
    ];
    return parts.where((e) => e.isNotEmpty).join(' - ');
  }

  static Future<void> _at(int id, DateTime when, String title, String body) async {
    final t = tz.TZDateTime(tz.local, when.year, when.month, when.day, when.hour, when.minute);
    if (!t.isAfter(tz.TZDateTime.now(tz.local))) return;
    await _plugin.zonedSchedule(
      id,
      title,
      body,
      t,
      _details,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
    );
  }

  /// Cancels everything and schedules reminders for all upcoming sessions.
  static Future<void> rescheduleAll() async {
    try {
      await _plugin.cancelAll();
      final list = await Db.i.sessions(from: dayStart(DateTime.now()), limit: 120);
      for (final s in list) {
        final d = dayStart(s.date);
        final body = _body(s);
        await _at(s.id! * 10 + 1, DateTime(d.year, d.month, d.day - 1, 18, 0), 'تذكير: جلسة غدًا', body);
        await _at(s.id! * 10 + 2, DateTime(d.year, d.month, d.day, 7, 30), 'جلسة اليوم', body);
      }
      // المواعيد العامة: تذكير قبلها بيوم 6 مساءً، وقبلها بساعة (أو 8 صباحًا لو بدون وقت).
      final appts = await Db.i.appointments(from: dayStart(DateTime.now()));
      for (final a in appts.take(120)) {
        final d = dayStart(a.date);
        final base = 500000000 + a.id! * 10;
        await _at(base + 1, DateTime(d.year, d.month, d.day - 1, 18, 0), 'تذكير: موعد غدًا', a.title);
        final dayOf = a.minutes == null
            ? DateTime(d.year, d.month, d.day, 8, 0)
            : DateTime(d.year, d.month, d.day, 0, a.minutes! - 60);
        await _at(base + 2, dayOf, a.minutes == null ? 'موعد اليوم' : 'موعد بعد ساعة', a.title);
        // الميعاد القانوني (شهادة/معارضة/استئناف/نقض): تنبيه مبكر قبله بـ7 أيام و3 أيام الساعة 9 صباحًا.
        if (apptKind(a.kind).legal) {
          final k = apptKind(a.kind).label;
          await _at(base + 3, DateTime(d.year, d.month, d.day - 7, 9, 0), 'ميعاد $k بعد 7 أيام', a.title);
          await _at(base + 4, DateTime(d.year, d.month, d.day - 3, 9, 0), 'ميعاد $k بعد 3 أيام', a.title);
        }
      }
    } catch (_) {}
  }

  static Future<void> testNow() => _plugin.show(
        999999999,
        'تنبيه تجريبي',
        'التنبيهات تعمل بشكل سليم ✔',
        _details,
      );
}
