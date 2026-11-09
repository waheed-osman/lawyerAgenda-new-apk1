# هيكلة المشروع (Architecture)

التطبيق مبني بنمط "طبقات" بسيط. أسماء المجلدات الفعلية تختلف قليلًا عن المقترح، وهذا جدول المطابقة:

| الطبقة المطلوبة | المجلد الفعلي | المحتوى |
|---|---|---|
| models | `lib/data/models.dart` | `Client` `LegalCase` `CaseSession` `CaseDocument` `Appointment` `Payment` `Attachment` `HistoryEntry` `LegalTemplate` |
| controllers / providers | `lib/data/db.dart` + `Live` في `lib/core/widgets.dart` | `Db` (قاعدة SQLite + `ChangeNotifier`): أي تعديل يستدعي `notifyListeners()` فتُعاد قراءة كل الشاشات المفتوحة تلقائيًا عبر `Live`. لا حاجة لحزمة provider. |
| views | `lib/screens/` | شاشة لكل وظيفة (الرئيسية، القضايا، الأجندة، الموكلون، المكتبة، الإعدادات...) |
| services | `lib/services/` | `notifications.dart` (التنبيهات) • `export.dart` (PDF/نص) • `security.dart` (PIN/كلمة المرور/البصمة/الحماية من التخمين) • `gemini.dart` (المساعد الذكي + حجب البيانات) • `doc_text.dart` (استخراج نص docx) |
| widgets | `lib/core/widgets.dart` | مكونات مشتركة: `SessionTile` `AppointmentTile` `CaseCard` `FinanceStats` `Live` `EmptyState`... |
| utils | `lib/core/utils.dart` + `theme.dart` | الثوابت (أنواع القضايا، حالات الجلسات، أنواع الحركات المالية) وتنسيق التواريخ والمبالغ والثيم |

> لم تُنقل الملفات لمجلدات بأسماء جديدة عمدًا: النقل يغيّر مسارات الملفات على GitHub، ورفع المشروع من المتصفح لا يحذف الملفات القديمة، فتتكرر الملفات ويفشل البناء.

## تدفق البيانات

```
شاشة (view) ──يستدعي──▶ Db.i.xxx()  ──▶ SQLite (محلي)
      ▲                      │
      └──── Live ◀── notifyListeners()
                             └──▶ Notifier.rescheduleAll()  (بعد ثانية من آخر تعديل)
```

## خريطة المميزات (الطلب السبعة)

| # | الميزة | الملفات |
|---|---|---|
| 1 | الهيكلة والـ Git | هذا الملف • `.gitignore` • `.github/workflows/build_apk.yml` |
| 2 | لوحة التحكم | `screens/home_screen.dart` (ملخص اليوم، تنبيه داخلي، عدادات، الموقف المالي، مواعيد قريبة؛ عرض أقصى 820 للتابلت والوضع الأفقي) |
| 3 | الموكلون والقضايا | `client_form_screen` `client_detail_screen` `clients_screen` `case_form_screen` `case_detail_screen` `cases_screen` |
| 4 | الأجندة والتنبيهات | `calendar_screen` (جلسات + مواعيد) • `appointment_form_screen` • `session_form_screen` • `services/notifications.dart` |
| 5 | المذكرات والدفاع | `documents_tab` (تبويب "المذكرات" داخل القضية: تصنيف + بحث) • `document_form_screen` • `attachments_view` (صور المستندات) |
| 6 | الحسابات والماليات | `finance_dialog` • تبويب "الحسابات" في الموكل • "الموقف المالي" في القضية • `FinanceStats` |
| 7 | التصدير | `services/export.dart` (PDF / نص): تقرير قضية، كشف حساب موكل، أجندة فترة، قائمة قضايا |

## الإصدار 3: المكتبة والمساعد

| الميزة | الملفات |
|---|---|
| ملفات PDF/Word | `screens/library_screen.dart` (تبويب الملفات والرفع) • `screens/library_file_screen.dart` (العارض) • جدول `library_files` • `Backup._fileTables` |
| المساعد الذكي | `screens/ai_screen.dart` • `services/gemini.dart` • صلاحية INTERNET في `tool/setup_android.py` |
| القفل | `services/security.dart` • `screens/lock_screen.dart` • `screens/settings_screen.dart` |

## الإصدار 4: الميزات في `lib/features/`

الميزات الجديدة تُضاف كمجلدات مستقلة تحت `lib/features/<الميزة>/` (`data/` للنموذج والمستودع، `presentation/` للشاشات)، ولا تُنقل الملفات القديمة (انظر الملاحظة أعلاه عن الرفع من المتصفح).

| الميزة | الملفات |
|---|---|
| دليل المحاكم | `features/courts_directory/data/court.dart` (النموذج + المحافظات + رابط الخريطة) • `data/courts_repo.dart` (جدول `courts`) • `presentation/courts_screen.dart` (بحث + تصفية + وضع اختيار) • `court_detail_screen.dart` • `court_form_screen.dart` |
| الربط | أيقونة الدليل في `library_screen.dart` • زر الاختيار في `case_form_screen.dart` |
| إعادة المحاولة | `services/gemini.dart`: `_fallbacks` و`_retryable` و`generate` |

## الإصدار 5

| الميزة | الملفات |
|---|---|
| أنواع المواعيد/الميعاد القانوني | `core/utils.dart` (`appointmentKinds`, `apptKind`) • `appointment_form_screen.dart` (اختيار النوع + الحاسبة) • `widgets.dart` (`AppointmentTile`) • `calendar_screen.dart` |
| تنبيهات مبكرة | `services/notifications.dart` (7 و3 أيام للأنواع القانونية) |
| رفع من رابط | `services/downloader.dart` • `library_screen.dart` (`_addFileMenu`, `_fromUrl`) |
| الرول | عمود `roll` في `sessions` • `session_form_screen` • `SessionTile` |
| نموذج الإنابة | `features/delegation/delegation_screen.dart` • `Export.custom` • أيقونة في `case_detail_screen` |
| تجميع القضايا بالموكل | `clients_screen.dart` (ExpansionTile) • `core/grouped_cases.dart` • زر في `cases_screen.dart` |
| الروابط | `features/links/links_screen.dart` (نموذج + مستودع + شاشة) • جدول `links` |
| رقم الطعن والمبدأ | أعمدة `ref` و`principle` في `library_files` + البحث في `Db.libraryFiles` |

## قاعدة البيانات (الإصدار 5)

المضاف في الإصدار 5: عمود `kind` في `appointments`، وعمودا `ref` و`principle` في `library_files` (`Db._v5`).

## قاعدة البيانات (الإصدار 4)

المضاف في الإصدار 4: جدول `courts` (الاسم، النوع، المحافظة، العنوان، الهاتف، رابط الخريطة، الاختصاص، ملاحظات) ويدخل في `Backup._tables`.

المضاف في الإصدار 3: جدول `library_files` (العنوان، التصنيف، الملف، النوع، الحجم). الملفات نفسها في مجلد التطبيق الخاص وتُضمَّن في النسخة الاحتياطية base64.

جداول الإصدار 1: `clients cases sessions history attachments payments templates`.
المضاف في الإصدار 2: `documents` `appointments` + عمود `email` في `clients`.
الترقية تلقائية (`onUpgrade`) وتحافظ على بيانات الإصدار 1، والنسخ الاحتياطية القديمة تُستعاد بدون مشاكل.

أنواع الحركات المالية (`payments.kind`):
`fee` أتعاب متفق عليها • `payment` دفعة أتعاب • `deposit` أمانة مستلمة • `expense` مصروفات قضائية.
- المتبقي = أتعاب − دفعات
- رصيد الأمانات = أمانات − مصروفات

## كيف تضيف ميزة جديدة

1. جدول/عمود جديد: عدّل `_v2` أو أضف `_v3` في `db.dart` وارفع رقم `version`، ثم أضف الدوال في `Db`.
2. نموذج بيانات: صنف جديد في `models.dart` مع `fromMap` و`toMap`.
3. شاشة: ملف في `screens/` تستخدم `Live<T>(load: ..., builder: ...)`.
4. أضف الجدول الجديد للقائمة `_tables` في `data/backup.dart` ليدخل في النسخ الاحتياطي.

## Git

```bash
git init
git add .
git commit -m "Lawyer Agenda v2"
git branch -M main
git remote add origin https://github.com/<حسابك>/Lawyer-agenda.git
git push -u origin main
```
الملف `.gitignore` يستبعد مجلد `android/` (يُولَّد وقت البناء) ومفاتيح التوقيع وملفات النسخ الاحتياطي.
