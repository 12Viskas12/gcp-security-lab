# Запросы Logs Explorer и Log Analytics

Замени `PROJECT_ID` на свой. Временной диапазон задаётся в интерфейсе или условием `timestamp>="..."`.

## Источники

```
# Admin Activity
logName="projects/PROJECT_ID/logs/cloudaudit.googleapis.com%2Factivity"

# Data Access
logName="projects/PROJECT_ID/logs/cloudaudit.googleapis.com%2Fdata_access"
```

## Детекты (D-01 … D-07)

```
# D-01 Изменения IAM
logName:"cloudaudit.googleapis.com%2Factivity"
protoPayload.methodName=~"(?i)setiampolic|setiampermissions"

# D-02 Политики/конфигурация Cloud Storage
resource.type="gcs_bucket"
logName:"cloudaudit.googleapis.com%2Factivity"
protoPayload.methodName=~"(?i)setiampermissions|buckets.(update|patch|delete)"

# D-03 Service accounts
protoPayload.serviceName="iam.googleapis.com"
protoPayload.methodName=~"(?i)(create|delete|disable|enable|undelete|upload|patch|update)serviceaccount"

# D-04 Настройки аудита
protoPayload.serviceName="cloudresourcemanager.googleapis.com"
protoPayload.methodName="SetIamPolicy"
protoPayload.serviceData.policyDelta.auditConfigDeltas:*

# D-05 Отказы доступа к bucket
resource.type="gcs_bucket"
protoPayload.status.code=7

# D-06 Impersonation
protoPayload.serviceName="iamcredentials.googleapis.com"
protoPayload.methodName=~"GenerateAccessToken|GenerateIdToken|SignBlob|SignJwt"

# D-07 Сеть и compute
protoPayload.serviceName="compute.googleapis.com"
logName:"cloudaudit.googleapis.com%2Factivity"
protoPayload.methodName=~"(?i)compute.(firewalls|networks|subnetworks|routes|addresses|instances).(insert|patch|update|delete)"
```

## Вспомогательные запросы для расследований

```
# Все действия одного principal за период
protoPayload.authenticationInfo.principalEmail="PRINCIPAL"
timestamp>="2026-10-29T00:00:00Z"

# Чтение конкретного объекта
resource.type="gcs_bucket"
protoPayload.resourceName=~"confidential/finance-report-SYNTHETIC.csv"
protoPayload.methodName="storage.objects.get"

# Кто стоит за impersonation
protoPayload.authenticationInfo.serviceAccountDelegationInfo:*
```

## Выгрузка из CLI

```bash
gcloud logging read 'logName:"cloudaudit.googleapis.com%2Factivity" AND protoPayload.methodName=~"(?i)setiampolic"' \
  --project="$PROJECT_ID" --freshness=1h --limit=20 \
  --format='table(timestamp, protoPayload.authenticationInfo.principalEmail, protoPayload.methodName, protoPayload.status.code)'

# Для доказательств: сырой JSON в evidence/raw/ (в .gitignore), затем очистка scripts/sanitize.sh
gcloud logging read '...' --project="$PROJECT_ID" --format=json > evidence/raw/EVENT.json
bash scripts/sanitize.sh evidence/raw/EVENT.json > evidence/sanitized-logs/EVENT.txt
```

## Log Analytics (SQL по `security-audit`)

Если `log_bucket_location` не `global`, замени `global` на свой регион.

```sql
-- Изменения IAM за сутки
SELECT timestamp,
       proto_payload.audit_log.authentication_info.principal_email AS actor,
       proto_payload.audit_log.method_name AS method,
       proto_payload.audit_log.resource_name AS resource,
       proto_payload.audit_log.status.code AS status_code
FROM `PROJECT_ID.global.security-audit._AllLogs`
WHERE timestamp > TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 1 DAY)
  AND proto_payload.audit_log.method_name LIKE '%SetIamPolicy%'
ORDER BY timestamp DESC;

-- Профиль доступа к объектам (D-08): кто и сколько раз читал за сутки
SELECT proto_payload.audit_log.authentication_info.principal_email AS actor,
       proto_payload.audit_log.resource_name AS object,
       COUNT(*) AS reads,
       COUNTIF(proto_payload.audit_log.status.code != 0) AS denied
FROM `PROJECT_ID.global.security-audit._AllLogs`
WHERE timestamp > TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 1 DAY)
  AND proto_payload.audit_log.method_name = 'storage.objects.get'
GROUP BY actor, object
ORDER BY reads DESC;
```

## Чек-лист наличия событий

- [ ] Admin Activity присутствует (любой запрос из раздела «Источники»)
- [ ] Data Access Storage: чтение объекта от `sa-app-reader` (IR-03)
- [ ] Изменения IAM (IR-01, IR-05)
- [ ] Изменения политик Cloud Storage (IR-02)
- [ ] Управление service accounts (IR-05)
- [ ] Изменения настроек аудита (IR-04)
- [ ] Изменения сети/compute (IR-06)
