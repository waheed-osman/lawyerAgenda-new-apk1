import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum BioStatus { ready, notEnrolled, unsupported }

enum UnlockResult { ok, wrong, locked }

/// قفل التطبيق: رمز PIN رقمي أو كلمة مرور (مخزَّنة كـ SHA-256 مملّح)، وبصمة اختيارية،
/// وحماية من التخمين (تأخير متصاعد بعد 5 محاولات خاطئة، محفوظ حتى لو أُغلق التطبيق).
class Security {
  /// Set while a system dialog (camera, file picker, share sheet, biometric prompt)
  /// is open so the app does not re-lock when it returns to the foreground.
  static bool suspend = false;

  /// Increment to lock the app immediately.
  static final ValueNotifier<int> lockSignal = ValueNotifier(0);

  /// سبب آخر فشل للبصمة بالعربية (للعرض للمستخدم)، أو null.
  static String? lastBioError;

  static final _auth = LocalAuthentication();
  static const _freeAttempts = 5;

  static Future<SharedPreferences> get _p => SharedPreferences.getInstance();

  static Future<T> guard<T>(Future<T> Function() f) async {
    suspend = true;
    try {
      return await f();
    } finally {
      suspend = false;
    }
  }

  static String _hash(String salt, String pw) => sha256.convert(utf8.encode('$salt:$pw')).toString();

  // ---------- الرمز ----------
  static Future<bool> hasPassword() async => ((await _p).getString('pw_hash') ?? '').isNotEmpty;

  /// يحفظ رمز القفل. [numeric] = PIN رقمي (4–8 أرقام) وإلا كلمة مرور.
  static Future<void> setSecret(String secret, {required bool numeric}) async {
    final p = await _p;
    final r = Random.secure();
    final salt = base64Url.encode(List<int>.generate(16, (_) => r.nextInt(256)));
    await p.setString('pw_salt', salt);
    await p.setString('pw_hash', _hash(salt, secret));
    await p.setBool('pw_numeric', numeric);
    await p.setInt('pin_len', numeric ? secret.length : 0);
    await clearFails();
  }

  static Future<bool> isNumeric() async => (await _p).getBool('pw_numeric') ?? false;
  static Future<int> pinLength() async => (await _p).getInt('pin_len') ?? 0;

  /// تحقق بسيط (للتأكيد داخل الإعدادات بعد فتح التطبيق).
  static Future<bool> verify(String pw) async {
    final p = await _p;
    final salt = p.getString('pw_salt') ?? '';
    return _hash(salt, pw) == (p.getString('pw_hash') ?? '');
  }

  static Future<void> removePassword() async {
    final p = await _p;
    for (final k in ['pw_hash', 'pw_salt', 'pw_numeric', 'pin_len', 'fails', 'lock_until']) {
      await p.remove(k);
    }
    await p.setBool('bio', false);
  }

  // ---------- الحماية من التخمين ----------
  static Future<void> clearFails() async {
    final p = await _p;
    await p.remove('fails');
    await p.remove('lock_until');
  }

  /// الثواني المتبقية على انتهاء الإيقاف المؤقت (0 = غير موقوف).
  static Future<int> lockoutSeconds() async {
    final until = (await _p).getInt('lock_until') ?? 0;
    final left = until - DateTime.now().millisecondsSinceEpoch;
    return left > 0 ? (left / 1000).ceil() : 0;
  }

  static Future<int> attemptsLeft() async {
    final fails = (await _p).getInt('fails') ?? 0;
    return fails >= _freeAttempts ? 1 : _freeAttempts - fails;
  }

  /// يحاول فتح القفل بالرمز مع احتساب المحاولات الخاطئة.
  static Future<UnlockResult> tryUnlock(String secret) async {
    final p = await _p;
    if (await lockoutSeconds() > 0) return UnlockResult.locked;
    if (await verify(secret)) {
      await clearFails();
      return UnlockResult.ok;
    }
    final fails = (p.getInt('fails') ?? 0) + 1;
    await p.setInt('fails', fails);
    if (fails >= _freeAttempts) {
      final secs = min(30 * pow(2, fails - _freeAttempts).toInt(), 3600); // 30ث، 60ث، 2د ... حتى ساعة
      await p.setInt('lock_until', DateTime.now().millisecondsSinceEpoch + secs * 1000);
    }
    return UnlockResult.wrong;
  }

  // ---------- القفل التلقائي ----------
  static Future<int> graceSeconds() async => (await _p).getInt('lock_grace') ?? 30;
  static Future<void> setGrace(int s) async => (await _p).setInt('lock_grace', s);

  // ---------- البصمة ----------
  static Future<bool> biometricEnabled() async => (await _p).getBool('bio') ?? false;
  static Future<void> setBiometric(bool v) async => (await _p).setBool('bio', v);

  static Future<BioStatus> biometricStatus() async {
    try {
      if ((await _auth.getAvailableBiometrics()).isNotEmpty) return BioStatus.ready;
      return await _auth.canCheckBiometrics ? BioStatus.notEnrolled : BioStatus.unsupported;
    } catch (_) {
      return BioStatus.unsupported;
    }
  }

  static Future<bool> biometricAvailable() async => (await biometricStatus()) == BioStatus.ready;

  static String _bioMsg(String code) {
    switch (code) {
      case 'NotEnrolled':
        return 'لا توجد بصمة مسجلة على الهاتف. سجّل بصمتك من إعدادات الهاتف ثم أعد المحاولة.';
      case 'NotAvailable':
        return 'البصمة غير متاحة على هذا الهاتف حاليًا.';
      case 'LockedOut':
        return 'تم إيقاف البصمة مؤقتًا بعد محاولات خاطئة. انتظر قليلًا أو استخدم الرمز.';
      case 'PermanentlyLockedOut':
        return 'تم قفل البصمة. افتح قفل الهاتف بالرمز ثم أعد المحاولة.';
      case 'PasscodeNotSet':
        return 'يجب تعيين قفل شاشة للهاتف أولًا من إعدادات الهاتف.';
      case 'no_fragment_activity':
        return 'إعداد التطبيق غير مكتمل للبصمة (FragmentActivity). أعد بناء النسخة.';
    }
    return 'تعذّر تشغيل البصمة ($code).';
  }

  static Future<bool> authenticate() async {
    lastBioError = null;
    return guard(() async {
      try {
        final ok = await _auth.authenticate(
          localizedReason: 'أكّد هويتك لفتح أجندة المحامي',
          options: const AuthenticationOptions(biometricOnly: true, stickyAuth: true),
        );
        if (ok) await clearFails();
        return ok;
      } on PlatformException catch (e) {
        lastBioError = _bioMsg(e.code);
        return false;
      } catch (_) {
        lastBioError = 'تعذّر تشغيل البصمة.';
        return false;
      }
    });
  }
}
