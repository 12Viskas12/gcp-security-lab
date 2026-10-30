#!/usr/bin/env bash
# Восстановление terraform.tfstate, если файл потерян (например, смена компьютера).
# Импортирует в state ресурсы, которые УЖЕ созданы в проекте. Запуск из папки terraform/:
#   cd terraform && bash ../scripts/import-existing.sh
# Нужны: terraform init выполнен, terraform.tfvars на месте, python3, curl, gcloud auth.
# Ошибки отдельных импортов не фатальны (ресурса может не быть): итог проверяется через terraform plan.
set -uo pipefail

get() { # имя переменной из terraform.tfvars (строковое значение)
  sed -n "s/^$1[[:space:]]*=[[:space:]]*\"\(.*\)\"/\1/p" terraform.tfvars | head -1
}
P=$(get project_id); R=$(get region); R=${R:-europe-central2}
MEMBER=${MEMBER:-user:$(get alert_email)}
B="${P}-lab-data"
SA_R="sa-app-reader@${P}.iam.gserviceaccount.com"
SA_N="sa-no-access@${P}.iam.gserviceaccount.com"
SA_R_N="projects/${P}/serviceAccounts/${SA_R}"
SA_N_N="projects/${P}/serviceAccounts/${SA_N}"
[[ -n "$P" ]] || { echo "Не найден project_id в terraform.tfvars"; exit 1; }
echo "Проект: $P  регион: $R  member: $MEMBER"

imp() { # адрес, id
  local out
  if out=$(terraform import -input=false "$1" "$2" 2>&1); then echo "[OK]   $1"; else
    echo "[FAIL] $1"; echo "$out" | grep -E 'Error|error|already' | head -3 | sed 's/^/         /'
  fi
}

for api in compute iam iamcredentials cloudresourcemanager serviceusage logging monitoring storage billingbudgets cloudbilling; do
  imp "google_project_service.apis[\"${api}.googleapis.com\"]" "${P}/${api}.googleapis.com"
done

imp google_service_account.app_reader "$SA_R_N"
imp google_service_account.no_access  "$SA_N_N"
imp google_storage_bucket.data "${P}/${B}"
imp google_storage_bucket_iam_member.app_reader_objects "${B} roles/storage.objectViewer serviceAccount:${SA_R}"
imp google_project_iam_custom_role.lab_operator "projects/${P}/roles/labOperator"

for p in storage iam; do imp "google_project_iam_audit_config.services[\"${p}.googleapis.com\"]" "${P} ${p}.googleapis.com"; done
imp google_logging_project_bucket_config.security "projects/${P}/locations/global/buckets/security-audit"
imp google_logging_project_sink.audit "projects/${P}/sinks/audit-to-security-bucket"

imp google_compute_network.lab "projects/${P}/global/networks/lab-vpc"
imp google_compute_subnetwork.private "projects/${P}/regions/${R}/subnetworks/lab-private-${R}"
imp google_compute_firewall.deny_all_ingress "projects/${P}/global/firewalls/lab-deny-all-ingress"

imp google_storage_bucket_object.internal_sample "${B}/internal/employee-directory-SYNTHETIC.csv"
imp google_storage_bucket_object.confidential_sample "${B}/confidential/finance-report-SYNTHETIC.csv"

# IAM-привязки. Ключи как в iam.tf: группа|member|роль. Если в tfvars у тебя другие члены, поправь MEMBER.
proj_sa="security_admin:roles/iam.securityReviewer roles/logging.configWriter roles/logging.viewer roles/monitoring.alertPolicyEditor roles/monitoring.viewer"
proj_op="operator:roles/monitoring.viewer"
proj_au="auditor:roles/iam.securityReviewer roles/logging.privateLogViewer roles/monitoring.viewer roles/compute.networkViewer"
for spec in "$proj_sa" "$proj_op" "$proj_au"; do
  g=${spec%%:*}; for role in ${spec#*:}; do
    imp "google_project_iam_member.role_bindings[\"${g}|${MEMBER}|${role}\"]" "${P} ${role} ${MEMBER}"
  done
done
imp "google_storage_bucket_iam_member.role_bindings[\"security_admin|${MEMBER}|roles/storage.admin\"]" "${B} roles/storage.admin ${MEMBER}"
imp "google_storage_bucket_iam_member.role_bindings[\"operator|${MEMBER}|projects/${P}/roles/labOperator\"]" "${B} projects/${P}/roles/labOperator ${MEMBER}"
imp "google_service_account_iam_member.operator_impersonates_reader[\"${MEMBER}\"]" "${SA_R_N} roles/iam.serviceAccountTokenCreator ${MEMBER}"
imp "google_service_account_iam_member.tester_token_creator[\"app_reader|${MEMBER}\"]" "${SA_R_N} roles/iam.serviceAccountTokenCreator ${MEMBER}"
imp "google_service_account_iam_member.tester_token_creator[\"no_access|${MEMBER}\"]" "${SA_N_N} roles/iam.serviceAccountTokenCreator ${MEMBER}"

# Мониторинг: id каналов и политик берём через REST API.
TOKEN=$(gcloud auth print-access-token)
api() { curl -s -H "Authorization: Bearer ${TOKEN}" -H "x-goog-user-project: ${P}" "https://monitoring.googleapis.com/v3/projects/${P}/$1"; }
ch=$(api notificationChannels | python3 -c 'import sys,json
for c in json.load(sys.stdin).get("notificationChannels",[]):
    if c.get("displayName")=="Lab security email": print(c["name"]); break')
[[ -n "$ch" ]] && imp google_monitoring_notification_channel.email "$ch" || echo "[SKIP] канал уведомлений не найден"

declare -A titles=(
  [iam_policy_change]="IAM policy changed"
  [gcs_policy_change]="Cloud Storage bucket policy/config changed"
  [sa_management]="Service account or key management event"
  [audit_config_change]="Audit configuration changed"
  [gcs_denied_access]="Cloud Storage PERMISSION_DENIED"
  [sa_impersonation]="Service account token generated (impersonation)"
)
pols=$(api alertPolicies)
for k in "${!titles[@]}"; do
  id=$(echo "$pols" | python3 -c 'import sys,json
want="SEC | "+sys.argv[1]
for p in json.load(sys.stdin).get("alertPolicies",[]):
    if p.get("displayName")==want: print(p["name"]); break' "${titles[$k]}")
  [[ -n "$id" ]] && imp "google_monitoring_alert_policy.detections[\"$k\"]" "$id" || echo "[SKIP] алерт $k не найден"
done

echo
echo "Готово. Теперь: terraform plan. Ожидание: No changes (или небольшие отличия, которые надо разобрать)."
