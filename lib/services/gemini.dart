import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../data/db.dart';

/// جزء من رسالة: نص، أو ملف (PDF) يُرسل كما هو.
class AiPart {
  final String? text;
  final String? mime;
  final Uint8List? bytes;
  const AiPart.text(String t)
      : text = t,
        mime = null,
        bytes = null;
  const AiPart.file(Uint8List b, String m)
      : text = null,
        mime = m,
        bytes = b;

  int get fileBytes => bytes?.length ?? 0;

  Map<String, Object?> toJson() => text != null
      ? {'text': text}
      : {
          'inline_data': {'mime_type': mime, 'data': base64Encode(bytes!)}
        };
}

class AiMsg {
  final bool fromUser;
  final List<AiPart> parts;
  AiMsg(this.fromUser, this.parts);
  int get fileBytes => parts.fold(0, (a, p) => a + p.fileBytes);
}

class AiException implements Exception {
  final String message;
  const AiException(this.message);
  @override
  String toString() => message;
}

/// حجب البيانات الشخصية محليًا قبل إرسال أي نص إلى الإنترنت.
class Redactor {
  static const _d = '0-9٠-٩';
  static final _nid = RegExp('(?<![$_d])[$_d]{14}(?![$_d])');
  static final _phone = RegExp('(?<![$_d])(?:(?:\\+|00)?20|0)?1[0125][$_d]{8}(?![$_d])');
  static final _email = RegExp(r'[\w.+-]+@[\w-]+\.[\w.-]+');

  static Future<String> apply(String text) async {
    var t = text;
    t = t.replaceAll(_email, '[بريد]');
    t = t.replaceAll(_nid, '[رقم قومي]');
    t = t.replaceAll(_phone, '[هاتف]');
    try {
      const letters = ['أ', 'ب', 'ج', 'د', 'هـ', 'و', 'ز', 'ح', 'ط', 'ي'];
      final clients = (await Db.i.clients()).map((c) => c.name.trim()).where((n) => n.length >= 3).toSet().toList()
        ..sort((a, b) => b.length.compareTo(a.length));
      for (var i = 0; i < clients.length; i++) {
        final tag = i < letters.length ? 'الموكل (${letters[i]})' : 'الموكل ($i)';
        t = t.replaceAll(clients[i], tag);
      }
      final cases = await Db.i.cases();
      final opp = cases.map((c) => c.opponent.trim()).where((n) => n.length >= 3).toSet().toList()
        ..sort((a, b) => b.length.compareTo(a.length));
      for (var i = 0; i < opp.length; i++) {
        t = t.replaceAll(opp[i], 'الخصم (${i + 1})');
      }
    } catch (_) {}
    return t;
  }
}

/// عميل Gemini API (REST). المفتاح يُدخله المستخدم ويُحفظ على الجهاز فقط.
class Gemini {
  static const defaultModel = 'gemini-flash-latest';
  static const _base = 'https://generativelanguage.googleapis.com/v1beta';
  static const maxInlineBytes = 18 * 1024 * 1024; // حد الطلب 20MB تقريبًا

  static const systemPrompt = '''أنت مساعد قانوني ذكي يعمل مع محامٍ في مصر.
- أجب بالعربية الفصحى المهنية الواضحة، وبإيجاز منظّم (عناوين قصيرة ونقاط).
- الأصل أن القانون المطبّق هو القانون المصري، ما لم يُطلب غير ذلك.
- لا تختلق أرقام مواد أو أحكام نقض أو مبادئ. إن لم تكن متأكدًا فقل ذلك صراحة، واطلب من المحامي مراجعة النص الرسمي.
- عند تلخيص مستند اذكر: الوقائع، الطلبات، الدفوع، المواعيد والمدد، ثم النقاط التي تحتاج انتباهًا.
- عند الصياغة قدّم مسودة قابلة للتعديل، وضع بين أقواس ما يحتاج المحامي لاستكماله.
- عبارات مثل [هاتف] و[رقم قومي] و«الموكل (أ)» و«الخصم (1)» هي حجب مقصود للخصوصية؛ لا تحاول تخمين أصحابها.
- أنت أداة مساعدة للمحامي ولا تغني عن تقديره المهني.''';

  // ---------- الإعدادات ----------
  static Future<String> apiKey() async => (await SharedPreferences.getInstance()).getString('ai_key') ?? '';
  static Future<void> setApiKey(String k) async =>
      (await SharedPreferences.getInstance()).setString('ai_key', k.trim());

  static Future<String> model() async {
    final m = (await SharedPreferences.getInstance()).getString('ai_model') ?? '';
    return m.trim().isEmpty ? defaultModel : m.trim();
  }

  static Future<void> setModel(String m) async =>
      (await SharedPreferences.getInstance()).setString('ai_model', m.trim());

  static Future<bool> redactEnabled() async => (await SharedPreferences.getInstance()).getBool('ai_redact') ?? true;
  static Future<void> setRedact(bool v) async => (await SharedPreferences.getInstance()).setBool('ai_redact', v);

  static Future<bool> consented() async => (await SharedPreferences.getInstance()).getBool('ai_consent') ?? false;
  static Future<void> setConsented(bool v) async => (await SharedPreferences.getInstance()).setBool('ai_consent', v);

  // ---------- الطلبات ----------
  static Future<http.Response> _send(Future<http.Response> Function() f) async {
    try {
      return await f().timeout(const Duration(seconds: 120));
    } on TimeoutException {
      throw const AiException('انتهت مهلة الاتصال. تأكد من الإنترنت وحاول مرة أخرى.');
    } on SocketException {
      throw const AiException('لا يوجد اتصال بالإنترنت.');
    } on http.ClientException {
      throw const AiException('تعذّر الاتصال بالخادم. تأكد من الإنترنت.');
    }
  }

  static Map<String, dynamic> _json(http.Response r) {
    try {
      final d = jsonDecode(utf8.decode(r.bodyBytes));
      return d is Map<String, dynamic> ? d : <String, dynamic>{};
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  static AiException _error(http.Response r) {
    final msg = ((_json(r)['error'] as Map?)?['message'] ?? '').toString();
    switch (r.statusCode) {
      case 400:
        if (msg.contains('API key')) return const AiException('مفتاح الذكاء الاصطناعي غير صحيح. راجع الإعدادات.');
        return AiException('الطلب غير مقبول: ${_short(msg)}');
      case 401:
      case 403:
        return const AiException('المفتاح غير مسموح له بهذه الخدمة، أو الخدمة غير متاحة في بلدك.');
      case 404:
        return const AiException('اسم الموديل غير صحيح. غيّره من الإعدادات (جرّب gemini-flash-latest).');
      case 413:
        return const AiException('الملف أو النص كبير جدًا. جرّب ملفًا أصغر.');
      case 429:
        return const AiException('تجاوزت حد الاستخدام المجاني حاليًا. انتظر قليلًا ثم حاول.');
    }
    if (r.statusCode >= 500) return const AiException('خدمة Gemini مشغولة حاليًا. حاول بعد قليل.');
    return AiException('خطأ ${r.statusCode}: ${_short(msg)}');
  }

  static String _short(String s) => s.length > 160 ? '${s.substring(0, 160)}...' : s;

  /// موديلات بديلة تُجرَّب بالترتيب عند ازدحام الموديل المختار (يُتخطّى ما لا يوجد منها).
  static const _fallbacks = ['gemini-flash-lite-latest', 'gemini-2.5-flash-lite', 'gemini-2.5-flash'];

  static bool _retryable(int code) => code == 429 || code == 500 || code == 502 || code == 503 || code == 504;

  static Future<http.Response> _post(String model, String key, String body) => _send(() => http.post(
        Uri.parse('$_base/models/$model:generateContent'),
        headers: {'Content-Type': 'application/json', 'x-goog-api-key': key},
        body: body,
      ));

  /// يرسل المحادثة كاملة ويعيد نص الرد.
  static Future<String> generate(List<AiMsg> history) async {
    final key = await apiKey();
    if (key.isEmpty) throw const AiException('لم تُدخل مفتاح الذكاء الاصطناعي بعد. افتح الإعدادات من الأعلى.');
    final total = history.fold<int>(0, (a, m) => a + m.fileBytes);
    if (total > maxInlineBytes) {
      throw const AiException('حجم الملفات المرفقة في المحادثة كبير. ابدأ محادثة جديدة أو استخدم ملفًا أصغر.');
    }
    final m = await model();
    final body = jsonEncode({
      'systemInstruction': {
        'parts': [
          {'text': systemPrompt}
        ]
      },
      'contents': [
        for (final h in history) {'role': h.fromUser ? 'user' : 'model', 'parts': h.parts.map((p) => p.toJson()).toList()}
      ],
      'generationConfig': {'temperature': 0.4},
      // القضايا الجنائية تتضمن وقائع عنف قد تُحجب بالإعداد الافتراضي؛ نخفف الحجب لأغراض التحليل القانوني.
      'safetySettings': [
        for (final c in const [
          'HARM_CATEGORY_HARASSMENT',
          'HARM_CATEGORY_HATE_SPEECH',
          'HARM_CATEGORY_SEXUALLY_EXPLICIT',
          'HARM_CATEGORY_DANGEROUS_CONTENT'
        ])
          {'category': c, 'threshold': 'BLOCK_ONLY_HIGH'}
      ],
    });
    // الموديل المختار أولًا. عند الازدحام (429 / 5xx) نعيد المحاولة مرة بعد 3 ثوانٍ،
    // ثم ننتقل تلقائيًا لموديل بديل. أخطاء المفتاح أو اسم الموديل (400/401/403/404) لا تُعاد.
    final candidates = <String>[m, ..._fallbacks.where((x) => x != m)];
    http.Response? ok;
    http.Response? last;
    var used = m;
    outer:
    for (var mi = 0; mi < candidates.length; mi++) {
      for (var attempt = 0; attempt < 2; attempt++) {
        final resp = await _post(candidates[mi], key, body);
        last = resp;
        if (resp.statusCode == 200) {
          ok = resp;
          used = candidates[mi];
          break outer;
        }
        if (!_retryable(resp.statusCode)) break;
        if (attempt == 0) await Future.delayed(const Duration(seconds: 3));
      }
      // خطأ نهائي في الموديل الأساسي (مفتاح خاطئ، اسم موديل غير موجود...): لا فائدة من البدائل.
      if (mi == 0 && !_retryable(last!.statusCode)) throw _error(last!);
    }
    final r = ok ?? (throw _error(last!));
    final j = _json(r);
    final cands = j['candidates'];
    if (cands is! List || cands.isEmpty) {
      final reason = (j['promptFeedback'] as Map?)?['blockReason'];
      throw AiException(reason != null ? 'تم حجب الطلب من الخدمة ($reason). أعد صياغته.' : 'لم يصل رد من الخدمة.');
    }
    final cand = cands.first as Map;
    final parts = ((cand['content'] as Map?)?['parts'] as List?) ?? const [];
    var text = parts.map((p) => (p as Map)['text'] ?? '').join().toString().trim();
    if (text.isEmpty) {
      throw AiException('الرد فارغ (${cand['finishReason'] ?? 'غير معروف'}). أعد المحاولة بصياغة مختلفة.');
    }
    if (cand['finishReason'] == 'MAX_TOKENS') text += '\n\n(تم اقتطاع الرد لطوله)';
    if (used != m) text += '\n\n(الموديل المختار كان مشغولًا، فأجاب موديل بديل: $used)';
    return text;
  }

  /// أسماء الموديلات المتاحة لهذا المفتاح (التي تدعم generateContent).
  static Future<List<String>> listModels(String key) async {
    if (key.trim().isEmpty) throw const AiException('أدخل المفتاح أولًا.');
    final r = await _send(() => http.get(Uri.parse('$_base/models?pageSize=200'), headers: {'x-goog-api-key': key.trim()}));
    if (r.statusCode != 200) throw _error(r);
    final list = (_json(r)['models'] as List?) ?? const [];
    final out = <String>[];
    for (final m in list) {
      final mm = m as Map;
      final methods = (mm['supportedGenerationMethods'] as List?) ?? const [];
      final name = (mm['name'] ?? '').toString().replaceFirst('models/', '');
      if (!methods.contains('generateContent') || !name.startsWith('gemini')) continue;
      if (RegExp(r'image|tts|embedding|live|audio|robotics|computer|vision|learnlm').hasMatch(name)) continue;
      out.add(name);
    }
    out.sort((a, b) {
      int rank(String s) => s.endsWith('-latest') ? 0 : (s.contains('preview') || s.contains('exp') ? 2 : 1);
      final c = rank(a).compareTo(rank(b));
      return c != 0 ? c : b.compareTo(a);
    });
    return out;
  }
}
