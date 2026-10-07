# الخادم وإدارة المحتوى (Supabase)

الخادم اختياري: بدونه يعمل التطبيق بالمحتوى المرفق. معه تحصل على:
1. **تحديث المحتوى دون إصدار جديد** – تعدّل الدروس والأسئلة في قاعدة البيانات ثم تنشر حزمة الصف، فتصل للطلاب عند اتصالهم.
2. **مزامنة النتائج** – تحت معرّف مجهول لكل جهاز (Anonymous Sign-in)، جاهزة لربطها لاحقًا بولي الأمر والمعلم.
3. **المعلم الذكي** – عبر Claude، مقيد بمحتوى المنهج المرسل من الجهاز.

## 1) إنشاء المشروع
1. أنشئ مشروعًا في [supabase.com](https://supabase.com) (المنطقة الأقرب: Frankfurt).
2. **Authentication ← Sign In / Providers ← Anonymous sign-ins: فعّلها.**
3. ثبّت [Supabase CLI](https://supabase.com/docs/guides/cli) ثم من مجلد المشروع:
   ```bash
   supabase link --project-ref <ref>
   supabase db push                      # ينشئ الجداول والصلاحيات من supabase/migrations
   psql "<connection string>" -f supabase/seed.sql   # يضيف الصفوف والمواد والمحتوى التجريبي
   ```
4. انشر الحزم الأولى من **SQL Editor**:
   ```sql
   select publish_pack('g4');
   select publish_pack('g9');
   ```

## 2) الدوال (Edge Functions)
```bash
supabase secrets set ANTHROPIC_API_KEY=sk-ant-...      # من console.anthropic.com
supabase functions deploy content
supabase functions deploy ai-tutor
```
اختياري: `TUTOR_DAILY_LIMIT` (الافتراضي 40 سؤالًا لكل طالب يوميًا)، `TUTOR_MODEL` (الافتراضي `claude-opus-5-5` بجهد منخفض لإجابات سريعة وأقل تكلفة).

## 3) ربط التطبيق
من **Project Settings ← API** انسخ `Project URL` و`anon public key`:
```bash
flutter run --dart-define=SUPABASE_URL=https://<ref>.supabase.co --dart-define=SUPABASE_ANON_KEY=<anon key>
```
وفي Codemagic: مجموعة `madrasati_backend` بالمتغيرين نفسيهما (راجع RELEASE_GUIDE).

## 4) إضافة أو تعديل المحتوى
التسلسل: `grades` ← `subjects` ← `units` ← `lessons` ← `questions`، ومع كل مادة `books` + `book_pages` و`exams`.
1. أضف/عدّل الصفوف من **Table Editor** (أو من لوحة الإدارة في المرحلة الثانية).
2. الدرس لا يظهر للطلاب إلا إذا كان `published = true`.
3. انشر: `select publish_pack('g5');` ← يرتفع رقم الإصدار، وتسحبه التطبيقات تلقائيًا عند الاتصال.

### صيغة الأسئلة
| النوع `type` | الحقول المطلوبة |
|---|---|
| `mcq` | `options` (مصفوفة)، `answer` = رقم الخيار الصحيح بدءًا من 0 |
| `trueFalse` | `answer` = `true` أو `false` |
| `fill` / `short` | `accepted` = كل الإجابات المقبولة (يتجاهل التصحيح التشكيل والهمزات والمسافات) |
| `numeric` | `answer` = رقم، `tolerance` (اختياري)، `unit` (اختياري). يقبل الأرقام العربية والكسور مثل 3/4 |
| `match` | `pairs` = `[["يسار","يمين"], …]` بقيم يمين مختلفة |
| `essay` | `model_answer` – لا يُصحّح آليًا ويُعرض للطالب للمقارنة |

`difficulty`: 1 سهل، 2 متوسط، 3 صعب، 4 متقدم. `image`: رابط https أو مسار صورة مرفقة.

> اختبار `test/data/content_test.dart` يفحص كل حزمة مرفقة (الإجابات ضمن الخيارات، عدم تكرار المعرّفات، كفاية الأسئلة للامتحانات…). يُنصح بتشغيله على أي حزمة جديدة قبل نشرها.

## 5) الأمان
- صلاحيات RLS: المحتوى للقراءة فقط للجميع، والكتابة للمشرفين (`profiles.role = 'admin'`) فقط.
- نتائج الطالب لا يراها إلا هو، ووليّ أمره المرتبط، ومعلّم صفه.
- `publish_pack` ممنوعة على غير المشرفين.
- لجعل حساب مشرفًا: `update profiles set role = 'admin' where id = '<user id>';`
- النسخ الاحتياطي: مفعّل يوميًا تلقائيًا في خطط Supabase المدفوعة (Pro)، ويُنصح به قبل الإطلاق العام.
