#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# أداة الإعداد التلقائي لمدرسة قرآنية جديدة على Google Cloud & Firebase
# تقوم بالخطوات التالية بالكامل باستخدام حساب Google الخاص بالمشرف:
#   1. إنشاء مشروع Google Cloud جديد
#   2. تفعيل واجهات Firebase و Firestore و Identity Toolkit و Firebase Rules
#   3. ربط Firebase بالمشروع وإنشاء تطبيق Android بالحزمة com.aistudio.ahlalquran.quranicm
#   4. استخراج ملف google-services.json الحقيقي
#   5. إنشاء قاعدة بيانات Cloud Firestore ((default))
#   6. نشر قواعد الأمان (firestore.rules) الخاصة بالتطبيق
#   7. تفعيل تسجيل الدخول بالبريد/كلمة المرور وإنشاء حساب المشرف
#   8. تنزيل google-services.json إلى الهاتف وتوليد رابط فتح التطبيق تلقائياً
# ==============================================================================

PACKAGE_NAME="com.aistudio.ahlalquran.quranicm"
DEFAULT_FIRESTORE_LOCATIONS=("eur3" "nam5" "europe-west1" "us-central1")
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
RAW_RULES_URL="https://raw.githubusercontent.com/arbi-jridi/ahlelquran-setup/main/firestore.rules"
OUT_FILE="${HOME}/google-services.json"

echo "============================================================"
echo "   مرحباً بك في أداة إعداد مدرسة قرآنية جديدة (أهل القرآن)"
echo "============================================================"

if ! command -v gcloud >/dev/null 2>&1; then
  echo "[خطأ] أداة gcloud غير متوفرة. يرجى تشغيل السكريبت داخل Google Cloud Shell."
  exit 1
fi

ACTIVE_ACCOUNT="$(gcloud auth list --filter=status:ACTIVE --format='value(account)' | head -n1 || true)"
if [[ -z "${ACTIVE_ACCOUNT}" ]]; then
  echo "[تنبيه] لم يتم العثور على جلسة Google مفعلة. جاري فتح تسجيل الدخول..."
  gcloud auth login --no-launch-browser || gcloud auth login
  ACTIVE_ACCOUNT="$(gcloud auth list --filter=status:ACTIVE --format='value(account)' | head -n1 || true)"
else
  echo "الحساب النشط حالياً: ${ACTIVE_ACCOUNT}"
  read -r -p "هل تريد المتابعة بهذا الحساب (y) أم اختيار/تسجيل حساب Gmail آخر للمدرسة (n)؟ [y/n]: " KEEP_ACC
  if [[ "${KEEP_ACC}" =~ ^[Nn]$ ]]; then
    gcloud auth login --no-launch-browser || gcloud auth login
    ACTIVE_ACCOUNT="$(gcloud auth list --filter=status:ACTIVE --format='value(account)' | head -n1 || true)"
  fi
fi
echo "[✓] الحساب المستخدم: ${ACTIVE_ACCOUNT}"

read -r -p "أدخل اسم المدرسة (مثال: مدرسة الفرقان): " SCHOOL_NAME
while [[ -z "${SCHOOL_NAME// }" ]]; do
  read -r -p "اسم المدرسة مطلوب، يرجى إدخاله: " SCHOOL_NAME
done

read -r -p "أدخل البريد الإلكتروني للمشرف: " ADMIN_EMAIL
while [[ ! "${ADMIN_EMAIL}" =~ ^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$ ]]; do
  read -r -p "يرجى إدخال بريد إلكتروني صحيح: " ADMIN_EMAIL
done

while true; do
  read -r -s -p "أدخل كلمة مرور المشرف (6 أحرف على الأقل): " ADMIN_PASSWORD
  echo ""
  if [[ ${#ADMIN_PASSWORD} -ge 6 ]]; then
    break
  fi
  echo "[تنبيه] كلمة المرور قصيرة جداً (الحد الأدنى 6 أحرف)."
done

SUGGESTED_ID="ahl-alquran-$(date +%y%m%d%H%M)"
read -r -p "معرف المشروع Project ID [${SUGGESTED_ID}]: " INPUT_PROJECT_ID
PROJECT_ID="${INPUT_PROJECT_ID:-$SUGGESTED_ID}"
PROJECT_ID="$(echo "${PROJECT_ID}" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9-' | sed 's/^-*//;s/-*$//')"

if [[ ${#PROJECT_ID} -lt 6 ]]; then
  PROJECT_ID="ahl-alquran-$(date +%s)"
fi

echo ""
echo "[1/7] جاري إنشاء مشروع Google Cloud: ${PROJECT_ID} ..."
if gcloud projects describe "${PROJECT_ID}" >/dev/null 2>&1; then
  echo "  -> المشروع موجود مسبقاً، سيتم المتابعة عليه."
else
  gcloud projects create "${PROJECT_ID}" --name="Ahl AlQuran School"
fi
gcloud config set project "${PROJECT_ID}" >/dev/null

echo "[2/7] جاري تفعيل خدمات Firebase و Firestore و Authentication ..."
gcloud services enable \
  firebase.googleapis.com \
  firestore.googleapis.com \
  identitytoolkit.googleapis.com \
  firebaserules.googleapis.com \
  serviceusage.googleapis.com \
  cloudresourcemanager.googleapis.com \
  --project="${PROJECT_ID}"

ACCESS_TOKEN="$(gcloud auth print-access-token)"

poll_operation() {
  local op_name="$1"
  local url="https://firebase.googleapis.com/v1beta1/${op_name}"
  for _ in $(seq 1 30); do
    local resp
    resp="$(curl -sS -H "Authorization: Bearer ${ACCESS_TOKEN}" "${url}")"
    if python3 -c "import sys,json; d=json.loads(sys.argv[1]); sys.exit(0 if d.get('done') else 1)" "${resp}"; then
      echo "${resp}"
      return 0
    fi
    sleep 2
  done
  return 1
}

echo "[3/7] جاري ربط المشروع بـ Firebase ..."
ADD_FB_RESP="$(curl -sS -X POST \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{}' \
  "https://firebase.googleapis.com/v1beta1/projects/${PROJECT_ID}:addFirebase")"

OP_NAME="$(python3 -c "import sys,json; d=json.loads(sys.argv[1]); print(d.get('name',''))" "${ADD_FB_RESP}" || true)"
if [[ -n "${OP_NAME}" && "${OP_NAME}" == operations/* ]]; then
  poll_operation "${OP_NAME}" >/dev/null
fi

echo "[4/7] جاري تسجيل تطبيق الأندرويد (${PACKAGE_NAME}) واستخراج google-services.json ..."
LIST_APPS_RESP="$(curl -sS -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  "https://firebase.googleapis.com/v1beta1/projects/${PROJECT_ID}/androidApps")"

ANDROID_APP_ID="$(python3 -c "
import sys, json
d = json.loads(sys.argv[1])
for app in d.get('apps', []):
    if app.get('packageName') == sys.argv[2]:
        print(app.get('appId', ''))
        break
" "${LIST_APPS_RESP}" "${PACKAGE_NAME}" || true)"

if [[ -z "${ANDROID_APP_ID}" ]]; then
  CREATE_APP_RESP="$(curl -sS -X POST \
    -H "Authorization: Bearer ${ACCESS_TOKEN}" \
    -H "Content-Type: application/json" \
    -d "{\"packageName\":\"${PACKAGE_NAME}\",\"displayName\":\"Ahl AlQuran\"}" \
    "https://firebase.googleapis.com/v1beta1/projects/${PROJECT_ID}/androidApps")"
  APP_OP_NAME="$(python3 -c "import sys,json; d=json.loads(sys.argv[1]); print(d.get('name',''))" "${CREATE_APP_RESP}" || true)"
  if [[ -n "${APP_OP_NAME}" && "${APP_OP_NAME}" == operations/* ]]; then
    APP_DONE_RESP="$(poll_operation "${APP_OP_NAME}")"
    ANDROID_APP_ID="$(python3 -c "import sys,json; d=json.loads(sys.argv[1]); print(d.get('response',{}).get('appId',''))" "${APP_DONE_RESP}" || true)"
  fi
fi

if [[ -z "${ANDROID_APP_ID}" ]]; then
  echo "[خطأ] تعذر العثور على appId لتطبيق الأندرويد."
  exit 1
fi

sleep 2
CONFIG_RESP="$(curl -sS -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  "https://firebase.googleapis.com/v1beta1/projects/${PROJECT_ID}/androidApps/${ANDROID_APP_ID}/config")"

python3 -c "
import sys, json, base64
d = json.loads(sys.argv[1])
b64 = d.get('configFileContents', '')
if not b64:
    raise SystemExit('Missing configFileContents')
with open(sys.argv[2], 'wb') as f:
    f.write(base64.b64decode(b64))
" "${CONFIG_RESP}" "${OUT_FILE}"

echo "  -> تم حفظ الملف في: ${OUT_FILE}"

echo "[5/7] جاري إنشاء قاعدة بيانات Cloud Firestore ..."
if gcloud firestore databases describe --database="(default)" --project="${PROJECT_ID}" >/dev/null 2>&1; then
  echo "  -> قاعدة Firestore ((default)) موجودة مسبقاً."
else
  DB_CREATED=false
  for loc in "${DEFAULT_FIRESTORE_LOCATIONS[@]}"; do
    if gcloud firestore databases create --database="(default)" --location="${loc}" --type=firestore-native --project="${PROJECT_ID}" >/dev/null 2>&1; then
      echo "  -> تم إنشاء قاعدة Firestore في المنطقة ${loc}."
      DB_CREATED=true
      break
    fi
  done
  if [[ "${DB_CREATED}" != true ]]; then
    echo "[تحذير] تعذر إنشاء Firestore تلقائياً. يرجى إنشاؤها من لوحة Firebase Console."
  fi
fi

echo "[6/7] جاري نشر قواعد الأمان (firestore.rules) ..."
RULES_PATH="${REPO_ROOT}/firestore.rules"
if [[ ! -f "${RULES_PATH}" && -f "${SCRIPT_DIR}/firestore.rules" ]]; then
  RULES_PATH="${SCRIPT_DIR}/firestore.rules"
fi
if [[ ! -f "${RULES_PATH}" ]]; then
  RULES_PATH="/tmp/ahlalquran_firestore.rules"
  curl -fsSL "${RAW_RULES_URL}" -o "${RULES_PATH}"
fi

RULESET_PAYLOAD="$(python3 -c "
import sys, json
with open(sys.argv[1], 'r', encoding='utf-8') as f:
    content = f.read()
print(json.dumps({'source': {'files': [{'name': 'firestore.rules', 'content': content}]}}))
" "${RULES_PATH}")"

RULESET_RESP="$(curl -sS -X POST \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  -H "Content-Type: application/json" \
  -d "${RULESET_PAYLOAD}" \
  "https://firebaserules.googleapis.com/v1/projects/${PROJECT_ID}/rulesets")"

RULESET_NAME="$(python3 -c "import sys,json; print(json.loads(sys.argv[1]).get('name',''))" "${RULESET_RESP}" || true)"
if [[ -n "${RULESET_NAME}" ]]; then
  RELEASE_NAME="projects/${PROJECT_ID}/releases/cloud.firestore"
  curl -fsS -X PATCH \
    -H "Authorization: Bearer ${ACCESS_TOKEN}" \
    -H "Content-Type: application/json" \
    -d "{\"release\":{\"name\":\"${RELEASE_NAME}\",\"rulesetName\":\"${RULESET_NAME}\"}}" \
    "https://firebaserules.googleapis.com/v1/${RELEASE_NAME}" >/dev/null || \
  curl -fsS -X POST \
    -H "Authorization: Bearer ${ACCESS_TOKEN}" \
    -H "Content-Type: application/json" \
    -d "{\"name\":\"${RELEASE_NAME}\",\"rulesetName\":\"${RULESET_NAME}\"}" \
    "https://firebaserules.googleapis.com/v1/projects/${PROJECT_ID}/releases" >/dev/null
  echo "  -> تم نشر firestore.rules بنجاح!"
else
  echo "[تحذير] لم يُنشر ملف القواعد تلقائياً، يمكنك نشر firestore.rules لاحقاً من لوحة Firebase."
fi

echo "[7/7] جاري تفعيل Email/Password Auth وإنشاء حساب المشرف ..."
curl -sS -X POST \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  -H "x-goog-user-project: ${PROJECT_ID}" \
  -H "Content-Type: application/json" \
  -d '{}' \
  "https://identitytoolkit.googleapis.com/v2/projects/${PROJECT_ID}/identityPlatform:initializeAuth" >/dev/null || true

curl -sS -X PATCH \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  -H "x-goog-user-project: ${PROJECT_ID}" \
  -H "Content-Type: application/json" \
  -d '{"signIn":{"email":{"enabled":true,"passwordRequired":true}}}' \
  "https://identitytoolkit.googleapis.com/admin/v2/projects/${PROJECT_ID}/config?updateMask=signIn.email" >/dev/null || true

WEB_API_KEY="$(python3 -c "
import sys, json
with open(sys.argv[1], 'r', encoding='utf-8') as f:
    d = json.load(f)
clients = d.get('client', [])
match = next((c for c in clients if c.get('client_info', {}).get('android_client_info', {}).get('package_name') == sys.argv[2]), None)
target = match or (clients[0] if clients else {})
print(target.get('api_key', [{}])[0].get('current_key', ''))
" "${OUT_FILE}" "${PACKAGE_NAME}")"

SIGNUP_RESP="$(curl -sS -X POST \
  -H "Content-Type: application/json" \
  -d "{\"email\":\"${ADMIN_EMAIL}\",\"password\":\"${ADMIN_PASSWORD}\",\"returnSecureToken\":true}" \
  "https://identitytoolkit.googleapis.com/v1/accounts:signUp?key=${WEB_API_KEY}")"

echo "  -> استجابة إنشاء حساب المشرف:"
python3 -c "
import sys, json
d = json.loads(sys.argv[1])
if 'localId' in d:
    print('  [✓] تم إنشاء حساب المشرف في Firebase Auth:', d.get('email'))
else:
    print('  [تنبيه]', d.get('error', {}).get('message', d))
" "${SIGNUP_RESP}"

DEEP_LINK_PAYLOAD="$(python3 -c "
import sys, json, base64
with open(sys.argv[1], 'r', encoding='utf-8') as f:
    gs = json.load(f)
payload = {
    'schoolName': sys.argv[2],
    'adminEmail': sys.argv[3].strip().lower(),
    'googleServices': gs
}
raw = json.dumps(payload, ensure_ascii=False, separators=(',', ':')).encode('utf-8')
print(base64.urlsafe_b64encode(raw).decode('ascii').rstrip('='))
" "${OUT_FILE}" "${SCHOOL_NAME}" "${ADMIN_EMAIL}")"

DEEP_LINK_URL="ahlalquran://import-school?payload=${DEEP_LINK_PAYLOAD}"

if command -v cloudshell >/dev/null 2>&1; then
  echo ""
  echo "جاري تنزيل ملف google-services.json إلى جهازك..."
  cloudshell download "${OUT_FILE}" || true
fi

echo ""
echo "============================================================"
echo " اكتمل إعداد المشروع بنجاح!"
echo "============================================================"
echo " 1. ملف الإعدادات: ${OUT_FILE}"
echo " 2. ارجع إلى تطبيق «نظام مدارس القرآن» واضغط:"
echo "    (اختيار ملف google-services.json من الهاتف) وأدخل اسم المدرسة والبريد."
echo ""
echo " أو افتح الرابط المباشر التالي لاستيراد البيانات تلقائياً إلى التطبيق:"
echo "${DEEP_LINK_URL}"
echo "============================================================"
