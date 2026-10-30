#!/usr/bin/env bash
# Проверка конфигурации лаборатории. Запускать с учётными данными владельца тестового проекта.
# Использование: PROJECT_ID=my-project bash scripts/verify.sh
set -uo pipefail

: "${PROJECT_ID:?Задай PROJECT_ID}"
BUCKET="${BUCKET:-${PROJECT_ID}-lab-data}"
SA_READER="sa-app-reader@${PROJECT_ID}.iam.gserviceaccount.com"
SA_NONE="sa-no-access@${PROJECT_ID}.iam.gserviceaccount.com"
INTERNAL_OBJ="gs://${BUCKET}/internal/employee-directory-SYNTHETIC.csv"
CONF_OBJ="gs://${BUCKET}/confidential/finance-report-SYNTHETIC.csv"

pass=0
fail=0

ok()   { echo "[PASS] $1"; pass=$((pass + 1)); }
bad()  { echo "[FAIL] $1"; fail=$((fail + 1)); }
skip() { echo "[SKIP] $1"; }

expect_eq() { # описание, ожидаемое, фактическое
  if [[ "$3" == "$2" ]]; then ok "$1"; else bad "$1 (ожидалось '$2', получено '$3')"; fi
}
expect_success() { # описание, команда...
  local d="$1"; shift
  if "$@" >/dev/null 2>&1; then ok "$d"; else bad "$d"; fi
}
# Отказ засчитывается, только если команда упала именно с ошибкой доступа (а не по другой причине).
expect_denied() { # описание, команда...
  local d="$1"; shift
  local out
  if out=$("$@" 2>&1); then bad "$d (команда выполнилась, а должна быть отказана)"; return; fi
  if echo "$out" | grep -qiE '403|does not have|denied|forbidden|AccessDenied'; then
    ok "$d"
  else
    bad "$d (ошибка не похожа на отказ доступа: $(echo "$out" | head -1))"
  fi
}
can_impersonate() { gcloud auth print-access-token --impersonate-service-account="$1" >/dev/null 2>&1; }

echo "== Cloud Storage: конфигурация bucket =="
ubla=$(gcloud storage buckets describe "gs://${BUCKET}" --project="$PROJECT_ID" --format='value(uniform_bucket_level_access)' 2>/dev/null)
pap=$(gcloud storage buckets describe "gs://${BUCKET}" --project="$PROJECT_ID" --format='value(public_access_prevention)' 2>/dev/null)
ver=$(gcloud storage buckets describe "gs://${BUCKET}" --project="$PROJECT_ID" --format='value(versioning_enabled)' 2>/dev/null)
expect_eq "Uniform bucket-level access включён" "True" "$ubla"
expect_eq "Public Access Prevention = enforced" "enforced" "$pap"
expect_eq "Versioning включён" "True" "$ver"

echo "== Cloud Storage: анонимный доступ =="
code=$(curl -s -o /dev/null -w '%{http_code}' "https://storage.googleapis.com/${BUCKET}/internal/employee-directory-SYNTHETIC.csv")
if [[ "$code" == "401" || "$code" == "403" ]]; then ok "Анонимный доступ запрещён (HTTP $code)"; else bad "Анонимный доступ вернул HTTP $code"; fi

public=$(gcloud storage buckets get-iam-policy "gs://${BUCKET}" --project="$PROJECT_ID" --format=json 2>/dev/null | grep -c -E 'allUsers|allAuthenticatedUsers')
expect_eq "В IAM bucket нет allUsers/allAuthenticatedUsers" "0" "$public"

echo "== Impersonation (нужна роль serviceAccountTokenCreator, см. tester_members) =="
imp_reader=0
imp_none=0
if can_impersonate "$SA_READER"; then ok "Impersonation sa-app-reader работает"; imp_reader=1; else bad "Impersonation sa-app-reader недоступен"; fi
if can_impersonate "$SA_NONE";   then ok "Impersonation sa-no-access работает";  imp_none=1;   else bad "Impersonation sa-no-access недоступен"; fi

echo "== Cloud Storage: права тестовых identity =="
if [[ $imp_reader -eq 1 ]]; then
  expect_success "sa-app-reader читает INTERNAL" gcloud storage cat "$INTERNAL_OBJ" --impersonate-service-account="$SA_READER"
  expect_success "sa-app-reader читает CONFIDENTIAL" gcloud storage cat "$CONF_OBJ" --impersonate-service-account="$SA_READER"
  expect_denied  "sa-app-reader НЕ может записывать" bash -c "echo test | gcloud storage cp - 'gs://${BUCKET}/verify-write-test.txt' --impersonate-service-account='$SA_READER'"
else
  skip "Тесты sa-app-reader пропущены: impersonation недоступен"
fi
if [[ $imp_none -eq 1 ]]; then
  expect_denied "sa-no-access НЕ читает CONFIDENTIAL" gcloud storage cat "$CONF_OBJ" --impersonate-service-account="$SA_NONE"
else
  skip "Тест sa-no-access пропущен: impersonation недоступен"
fi

echo "== Разделение ролей (testIamPermissions от имени SA, ничего не изменяет) =="
SA_SECADM="lab-security-admin@${PROJECT_ID}.iam.gserviceaccount.com"
SA_OPER="lab-operator@${PROJECT_ID}.iam.gserviceaccount.com"
SA_AUD="lab-auditor@${PROJECT_ID}.iam.gserviceaccount.com"

# Возвращает 0, если у SA есть разрешение; 1, если нет; 2, если токен получить не удалось.
perm_project() { # sa, permission
  local tok; tok=$(gcloud auth print-access-token --impersonate-service-account="$1" 2>/dev/null) || return 2
  curl -s -X POST -H "Authorization: Bearer ${tok}" -H "Content-Type: application/json" -H "x-goog-user-project: ${PROJECT_ID}" \
    -d "{\"permissions\":[\"$2\"]}" "https://cloudresourcemanager.googleapis.com/v1/projects/${PROJECT_ID}:testIamPermissions" | grep -q "\"$2\""
}
perm_bucket() { # sa, permission
  local tok; tok=$(gcloud auth print-access-token --impersonate-service-account="$1" 2>/dev/null) || return 2
  curl -s -H "Authorization: Bearer ${tok}" -H "x-goog-user-project: ${PROJECT_ID}" \
    "https://storage.googleapis.com/storage/v1/b/${BUCKET}/iam/testPermissions?permissions=$2" | grep -q "\"$2\""
}
role_check() { # описание, функция, sa, permission, ожидание(yes|no)
  local d="$1" fn="$2" sa="$3" perm="$4" want="$5" rc
  $fn "$sa" "$perm"; rc=$?
  if [[ $rc -eq 2 ]]; then bad "$d (нет impersonation для ${sa%%@*})"; return; fi
  if [[ "$want" == "yes" && $rc -eq 0 ]] || [[ "$want" == "no" && $rc -eq 1 ]]; then ok "$d"; else bad "$d (ожидалось: $want)"; fi
}

role_check "Security Admin: может менять политики bucket"          perm_bucket  "$SA_SECADM" storage.buckets.setIamPolicy yes
role_check "Security Admin: может менять sink логирования"         perm_project "$SA_SECADM" logging.sinks.update yes
role_check "Security Admin: НЕ может менять IAM проекта"           perm_project "$SA_SECADM" resourcemanager.projects.setIamPolicy no
role_check "Operator: может создавать объекты"                     perm_bucket  "$SA_OPER"   storage.objects.create yes
role_check "Operator: НЕ может удалять объекты"                    perm_bucket  "$SA_OPER"   storage.objects.delete no
role_check "Operator: НЕ может менять IAM bucket"                  perm_bucket  "$SA_OPER"   storage.buckets.setIamPolicy no
role_check "Operator: НЕ может менять sink логирования"            perm_project "$SA_OPER"   logging.sinks.update no
role_check "Auditor: может читать приватные логи (Data Access)"    perm_project "$SA_AUD"    logging.privateLogEntries.list yes
role_check "Auditor: НЕ читает объекты (CONFIDENTIAL)"             perm_bucket  "$SA_AUD"    storage.objects.get no
role_check "Auditor: НЕ может создавать объекты"                   perm_bucket  "$SA_AUD"    storage.objects.create no
role_check "Auditor: НЕ может менять IAM проекта"                  perm_project "$SA_AUD"    resourcemanager.projects.setIamPolicy no

echo "== Сеть =="
nets=$(gcloud compute networks list --project="$PROJECT_ID" --format='value(name)' 2>/dev/null)
if echo "$nets" | grep -qx "default"; then bad "Есть default VPC"; else ok "Default VPC отсутствует"; fi
mode=$(gcloud compute networks describe lab-vpc --project="$PROJECT_ID" --format='value(autoCreateSubnetworks)' 2>/dev/null)
if [[ -z "$mode" || "$mode" == "False" ]]; then ok "lab-vpc в custom mode"; else bad "lab-vpc в auto mode ($mode)"; fi
addrs=$(gcloud compute addresses list --project="$PROJECT_ID" --format='value(name)' 2>/dev/null | wc -l)
expect_eq "Нет зарезервированных IP-адресов" "0" "$(echo "$addrs" | tr -d ' ')"
instances=$(gcloud compute instances list --project="$PROJECT_ID" --format='value(name)' 2>/dev/null | wc -l)
expect_eq "Нет VM (нет внешних IP)" "0" "$(echo "$instances" | tr -d ' ')"

echo "== IAM =="
for sa in "$SA_READER" "$SA_NONE"; do
  keys=$(gcloud iam service-accounts keys list --iam-account="$sa" --managed-by=user --format='value(name)' 2>/dev/null | wc -l)
  expect_eq "У $sa нет пользовательских ключей" "0" "$(echo "$keys" | tr -d ' ')"
done
basic=$(gcloud projects get-iam-policy "$PROJECT_ID" --format=json 2>/dev/null \
  | grep -c -E '"role": "roles/(owner|editor)"')
echo "[INFO] Basic-роли owner/editor в политике проекта: $basic привязок (должен быть только ты как владелец лабы; сверь вручную)"

echo "== Аудит =="
audit=$(gcloud projects get-iam-policy "$PROJECT_ID" --format=json 2>/dev/null)
for svc in storage.googleapis.com iam.googleapis.com; do
  if echo "$audit" | grep -q "\"service\": \"$svc\""; then ok "auditConfig для $svc настроен"; else bad "auditConfig для $svc не найден"; fi
done
sink=$(gcloud logging sinks list --project="$PROJECT_ID" --format='value(name)' 2>/dev/null | grep -c '^audit-to-security-bucket$')
expect_eq "Log sink audit-to-security-bucket существует" "1" "$sink"
alerts=$(gcloud alpha monitoring policies list --project="$PROJECT_ID" --format='value(displayName)' 2>/dev/null | grep -c '^SEC |')
echo "[INFO] Alert policies 'SEC |': $alerts (ожидается 7; если 0, проверь вручную в консоли, команда alpha может быть недоступна)"

echo
echo "Итого: PASS=$pass FAIL=$fail"
[[ $fail -eq 0 ]]
