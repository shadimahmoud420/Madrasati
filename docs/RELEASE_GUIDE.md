# دليل نشر «مدرستي» على TestFlight و Google Play

التطبيق مستقل عن تطبيقاتنا الأخرى، لكنه يستخدم **حساب Apple Developer نفسه** و**مفتاح App Store Connect نفسه** في Codemagic (مفتاح الفريق يعمل لكل التطبيقات).

| المعرّف | القيمة |
|---|---|
| iOS Bundle ID | `com.madrasatigaza.madrasati` |
| Android applicationId | `com.madrasatigaza.madrasati` |
| اسم التطبيق على الشاشة | مدرستي |

> لا يمكن تغيير المعرّف بعد أول رفع. إن أردت معرّفًا آخر فغيّره الآن في Xcode (`PRODUCT_BUNDLE_IDENTIFIER`)، و`android/app/build.gradle.kts`، و`BUNDLE_ID` في `codemagic.yaml`.

---

## 1) قبل البدء
```bash
bash tool/setup.sh
flutter run            # جرّب على محاكي أو جهاز
```

## 2) إنشاء التطبيق في App Store Connect (مرة واحدة)
1. ادخل [App Store Connect](https://appstoreconnect.apple.com) ← **Apps** ← **+** ← **New App**.
2. Platform: **iOS** — Name: **مدرستي** (إن كان الاسم محجوزًا جرّب «مدرستي – غزة») — Primary language: **Arabic**.
3. Bundle ID: اختر `com.madrasatigaza.madrasati`.
   - إن لم يظهر في القائمة: سجّله أولًا من [developer.apple.com](https://developer.apple.com/account/resources/identifiers/list) ← Identifiers ← **+** ← App IDs ← App، بالمعرّف نفسه (بدون أي Capabilities إضافية).
4. SKU: `madrasati-ios`.
5. بعد الإنشاء: **App Information** ← انسخ **Apple ID** (رقم من 10 خانات) وضعه في `APP_STORE_APPLE_ID` داخل `codemagic.yaml` (اختياري، لترقيم البناءات تلقائيًا).

## 3) ربط المستودع في Codemagic (مرة واحدة)
1. [codemagic.io](https://codemagic.io) ← **Add application** ← GitHub ← اختر المستودع **Madrasati** ← Flutter App ← **codemagic.yaml**.
2. التكاملات والمجموعات مشتركة على مستوى الفريق، فهي موجودة مسبقًا من StoryCraft:
   - Integration: **StoryCraft ASC** (مفتاح App Store Connect).
   - Environment group: **ios_signing** (يحتوي `CERTIFICATE_PRIVATE_KEY`).
   إن كانت المجموعة على مستوى التطبيق السابق فقط، أنشئها هنا بالقيمة نفسها: App settings ← Environment variables ← Group `ios_signing`.
3. شغّل workflow **iOS → TestFlight**. سيقوم بـ: الفحص والاختبارات ← إنشاء ملف التوقيع لهذا المعرّف تلقائيًا ← بناء IPA ← رفعه إلى App Store Connect.

## 4) TestFlight
1. بعد 10–30 دقيقة من الرفع يظهر البناء في **TestFlight** بحالة Processing ثم Ready.
2. سؤال التشفير لن يظهر (مضبوط `ITSAppUsesNonExemptEncryption = NO`).
3. **المختبرون الداخليون** (حتى 100 من فريقك): TestFlight ← Internal Testing ← **+** ← أضف المجموعة والأشخاص. يصلهم البناء فورًا دون مراجعة.
4. **المختبرون الخارجيون** (حتى 10,000 برابط عام): املأ **Test Information** (وصف، بريد للملاحظات، رابط سياسة الخصوصية)، ثم أنشئ مجموعة خارجية وأرسل أول بناء لمراجعة Beta (عادة يوم واحد). بعدها يمكنك تفعيل `submit_to_testflight: true` في `codemagic.yaml`.
5. يثبّت المختبر تطبيق **TestFlight** من App Store ثم يفتح الدعوة.

> **ملاحظة للمراجعة:** التطبيق لا يتطلب تسجيل دخول، فلا حاجة لحساب تجريبي. اكتب في ملاحظات المراجعة: «اختر المرحلة الأساسية الدنيا ← الصف الرابع، أو العليا ← الصف التاسع لرؤية المحتوى التجريبي».

### نصوص جاهزة لـ TestFlight
- **Beta App Description:** مدرستي: مدرسة رقمية متكاملة لطلاب غزة من الصف الأول حتى الثاني عشر. دروس وكتب وبنك أسئلة واختبارات تكيفية وامتحانات تجريبية ولوحة تقدم، وكلها تعمل بدون إنترنت.
- **What to Test:** اختر الصف الرابع أو التاسع. جرّب: فتح درس، الأسئلة التدريبية، «اختبرني»، امتحان تجريبي، الكتاب والبحث فيه، البحث العام، لوحة «تقدّمي»، وتشغيل التطبيق في وضع الطيران.

## 5) Google Play (الاختبار الداخلي)
1. أنشئ مفتاح الرفع:
   ```bash
   keytool -genkey -v -keystore ~/madrasati-upload.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
   ```
   احفظه في مكان آمن (لا ترفعه إلى GitHub).
2. Codemagic ← Team settings ← Code signing identities ← Android keystores ← ارفعه باسم **madrasati_upload_key**.
3. Play Console ← Create app «مدرستي» ← ارفع أول ملف AAB يدويًا مرة واحدة (Internal testing) من Artifacts في Codemagic، فهذا شرط Google قبل الرفع الآلي.
4. بعدها شغّل workflow **Android → Google Play (internal testing)** (مجموعة `google_play` موجودة من التطبيقات السابقة).
5. **مهم:** التطبيق موجّه للأطفال، لذا في Play Console ← **Target audience and content** اختر الفئات العمرية الصحيحة والتزم بسياسة **Families**. وفي App Store اختر فئة **Education** ولا تفعّل «Made for Kids» إلا بعد مراجعة متطلباتها.

## 6) ربط الخادم (اختياري للتجربة الأولى)
بدون خادم يعمل التطبيق كاملًا بالمحتوى المرفق، والمعلم الذكي يظهر كـ«غير مفعّل بعد». لتفعيل الخادم والمعلم الذكي اتبع [BACKEND_GUIDE.md](BACKEND_GUIDE.md)، ثم في Codemagic أنشئ مجموعة **madrasati_backend** فيها `SUPABASE_URL` و`SUPABASE_ANON_KEY` وأزل علامة التعليق عن سطرها في `codemagic.yaml`.

## 7) قائمة فحص قبل كل بناء
- [ ] `flutter analyze` و `flutter test` بلا أخطاء (Codemagic يشغلهما تلقائيًا).
- [ ] جرّب على شاشة صغيرة (iPhone SE) وكبيرة، وفي الوضع الداكن.
- [ ] شغّل وضع الطيران: الدروس والكتاب والاختبارات تعمل، والمعلم الذكي يوضح أنه يحتاج إنترنت.
- [ ] امتحان تجريبي حتى انتهاء الوقت: يُسلَّم تلقائيًا.
- [ ] فعّل التذكير اليومي ثم ارفض الإذن: رسالة واضحة دون تعطل.
- [ ] بعد أي تعديل على المحتوى المرفق: ارفع `PACK_VERSION` في `tool/build_content.py` وشغّله.
