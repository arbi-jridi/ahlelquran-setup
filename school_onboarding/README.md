# بوابة الإعداد الذاتي للمدارس (`school_onboarding`)

## لماذا ظهر الخطأ في Cloud Shell؟
لأن مستودع `arbi-jridi/ahlelquran` **خاص (Private)** لحماية ملف `schools.json`، ولذلك لا يمكن لـ Cloud Shell أو GitHub Pages استنساخه بدون مصادقة. بالإضافة إلى أن واجهة Cloud Shell تعرض سطر أوامر قد يُربك المستخدم غير التقني ولا تتيح اختيار حساب Gmail مستقل تلقائياً.

## الحل المعتمد: صفحة ويب عربية نظيفة (`index.html`) بدون إظهار أي سكريبت أو طرفية
1. أنشئ مستودعاً **عاماً (Public)** جديداً على GitHub باسم:
   `arbi-jridi/ahlelquran-setup`
   (مع الإبقاء على `arbi-jridi/ahlelquran` خاصاً كما هو).
2. ارفع إلى جذر المستودع العام `ahlelquran-setup`:
   - `index.html` (من مجلد `school_onboarding/index.html`)
   - `firestore.rules` (نسخة من `firestore.rules` الموجودة في جذر مشروعك)
   - (اختياري) `setup_school.sh` و`CLOUD_SHELL_GUIDE.md`
3. من **Settings ← Pages** في مستودع `ahlelquran-setup` فعّل النشر من فرع `main` ليصبح الرابط:
   `https://arbi-jridi.github.io/ahlelquran-setup/`
4. من **Google Cloud Console ← APIs & Services ← Credentials** في مشروعك الرئيسي:
   - أنشئ **OAuth 2.0 Client ID** من نوع **Web application**.
   - أضف في **Authorized JavaScript origins**: `https://arbi-jridi.github.io`
   - أضف في **Authorized redirect URIs**: `https://arbi-jridi.github.io/ahlelquran-setup/`
   - انسخ الـ **Client ID** وضعه في السطر `DEFAULT_GOOGLE_OAUTH_CLIENT_ID = "..."` داخل `index.html`.
   - في **OAuth consent screen**: أضف نطاق `https://www.googleapis.com/auth/cloud-platform`، وأثناء التجربة أضف إيميلات المختبرين (أو انشر التطبيق عبر زر **Publish App** ليعمل مع أي بريد Gmail).
