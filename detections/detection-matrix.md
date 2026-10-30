# Матрица обнаружений

Цепочка проверки каждого детекта: **событие → журнал → запрос/условие → alert или ручная процедура SOC**.
Все алерты реализованы в `terraform/monitoring.tf` как log-based alert policies (`condition_matched_log`) с отправкой на email; ссылки на запросы: [queries.md](queries.md).

## Сводка

| ID | Событие | Источник | Реализация | Severity | Runbook | Инцидент |
| --- | --- | --- | --- | --- | --- | --- |
| D-01 | Изменение IAM policy | Cloud Audit Logs (Admin Activity) | Alert `iam_policy_change` | ERROR | RB-003 | IR-01, IR-05 |
| D-02 | Изменение политики/конфигурации Cloud Storage | Admin Activity | Alert `gcs_policy_change` | ERROR | RB-001 | IR-02 |
| D-03 | Управление service accounts | Admin Activity (IAM API) | Alert `sa_management` | ERROR | RB-004 | IR-05 |
| D-04 | Изменение настроек аудита | Admin Activity (Resource Manager) | Alert `audit_config_change` | CRITICAL | RB-005 | IR-04 |
| D-05 | Отказ доступа к объектам | Data Access | Alert `gcs_denied_access` | WARNING | RB-002 | IR-03 |
| D-06 | Выпуск токена service account (impersonation) | Data Access (через `iam.googleapis.com`) | Alert `sa_impersonation` | WARNING | RB-002 | IR-03 |
| D-07 | Изменение сети/compute-ресурсов (firewall, VM, IP) | Admin Activity (Compute) | Alert `unexpected_compute_change` | ERROR | RB-006 | IR-06 |
| D-08 | Необычный **успешный** доступ к объектам | Data Access | Ручная процедура (Log Analytics), алерта нет | n/a | RB-002 | IR-03 |

D-08 сознательно оставлен без алерта: успешное чтение разрешённой identity выглядит как штатная работа, нужна корреляция (объём, время, объект). Это ограничение вынесено в итоговый отчёт.

## D-01. Изменение IAM policy

- **Запрос:** `logName:"cloudaudit.googleapis.com%2Factivity" AND protoPayload.methodName=~"(?i)setiampolic|setiampermissions"`
- **Поля:** `authenticationInfo.principalEmail` (кто), `resourceName` (на чём), `serviceData.policyDelta.bindingDeltas` (что изменено: ADD/REMOVE, member, role), `requestMetadata.callerIp`.
- **Ожидаемый результат:** одна запись `SetIamPolicy`/`storage.setIamPermissions` на каждое изменение; письмо в течение 1–3 минут.
- **False positives:** штатные `terraform apply`, выдача экстренного доступа ([emergency-access](../runbooks/emergency-access.md)).
- **Severity:** ERROR (CRITICAL, если роль `owner`/`editor`/`*.admin` или субъект внешний).
- **Triage:** кто, что добавлено, есть ли тикет/PR, использовались ли новые права (Data Access логи принципала после изменения).
- **Ограничения:** алерт срабатывает на любое изменение и не оценивает «опасность» роли; запись о неудавшемся изменении тоже попадает под фильтр; лимит уведомлений 5 минут (серия изменений = одно письмо, детали в логах).

## D-02. Изменение политики/конфигурации Cloud Storage

- **Запрос:** `resource.type="gcs_bucket" AND logName:"cloudaudit.googleapis.com%2Factivity" AND protoPayload.methodName=~"(?i)setiampermissions|buckets.(update|patch|delete)"`
- **Поля:** `methodName`, `status` (код 0 = успех; 9 = отклонено Public Access Prevention), `serviceData.policyDelta`.
- **Ожидаемый результат:** при попытке выдать `allUsers` — запись со статусом ошибки и текстом про public access prevention.
- **False positives:** смена lifecycle/labels через Terraform.
- **Severity:** ERROR.
- **Triage:** успешно ли изменение (`status.code`), затрагивает ли публичность/IAM, объекты под угрозой (`internal/` и `confidential/`).
- **Ограничения:** не видит изменения на уровне проекта, влияющие на bucket (наследование); не сообщает о *фактическом* чтении анонимом — для этого Data Access.

## D-03. Управление service accounts

- **Запрос:** `protoPayload.serviceName="iam.googleapis.com" AND protoPayload.methodName=~"(?i)(create|delete|disable|enable|undelete|upload|patch|update)serviceaccount"`
- **Поля:** `methodName`, `resourceName` (SA), `principalEmail`. Создание ключа — `CreateServiceAccountKey` (в лабе ключи не создаются, см. IR-05).
- **Ожидаемый результат:** событие при создании/изменении/отключении SA.
- **False positives:** штатное создание SA через Terraform.
- **Severity:** ERROR.
- **Triage:** кто создал, зачем, какие роли у нового SA, есть ли ключи (`keys list --managed-by=user`).
- **Ограничения:** выдача роли существующему SA — это D-01, а не D-03.

## D-04. Изменение настроек аудита

- **Запрос:** `protoPayload.serviceName="cloudresourcemanager.googleapis.com" AND protoPayload.methodName="SetIamPolicy" AND protoPayload.serviceData.policyDelta.auditConfigDeltas:*`
- **Поля:** `auditConfigDeltas` (сервис, logType, exempted member, действие).
- **Ожидаемый результат:** запись с дельтой audit config; письмо уровня CRITICAL.
- **False positives:** `terraform apply` с изменением `logging.tf`.
- **Severity:** CRITICAL (риск потери видимости).
- **Triage:** кто, какой сервис/logType, какое окно «слепоты» (от изменения до отката), что делала exempted identity в окне.
- **Ограничения:** сам алерт приходит из тех же логов; кто может отключить аудит целиком, тот может заглушить и алерт. Защита: отдельный log project, organization-level sink, ограничение `setIamPolicy`. Вторичный источник — Cloud Asset Inventory history и `terraform plan` (дрейф).

## D-05. Отказ доступа к объектам

- **Запрос:** `resource.type="gcs_bucket" AND protoPayload.status.code=7`
- **Поля:** `principalEmail`, `serviceAccountDelegationInfo` (кто стоит за impersonation), `resourceName` (объект), `callerIp`.
- **Ожидаемый результат:** запись `PERMISSION_DENIED` на каждое обращение; одно письмо на серию.
- **False positives:** разовые ошибки автоматики, неверный путь объекта.
- **Severity:** WARNING (повышать при серии по разным объектам и разведке `list`).
- **Triage:** единичный отказ или серия, затронут ли CONFIDENTIAL, были ли успешные операции у той же identity.
- **Ограничения:** анонимные отказы могут не попадать в Data Access; порог «>0 за 5 минут» шумный и не учитывает частоту.

## D-06. Выпуск токена service account (impersonation)

- **Запрос:** `protoPayload.serviceName="iamcredentials.googleapis.com" AND protoPayload.methodName=~"GenerateAccessToken|GenerateIdToken|SignBlob|SignJwt"`
- **Поля:** `principalEmail` (кто выпускает), `resourceName` (чей токен).
- **Ожидаемый результат:** событие на каждый выпуск; письмо WARNING.
- **False positives:** любая работа через `--impersonate-service-account`, `verify.sh`.
- **Triage:** ожидаем ли принципал в списке TokenCreator, соответствует ли время рабочему окну.
- **Ограничения:** событие приходит только при включённом Data Access аудите `iam.googleapis.com` (включён в `logging.tf`); высокий объём в реальной среде.

## D-07. Изменение сети и compute-ресурсов

- **Запрос:** `protoPayload.serviceName="compute.googleapis.com" AND logName:"cloudaudit.googleapis.com%2Factivity" AND protoPayload.methodName=~"(?i)compute.(firewalls|networks|subnetworks|routes|addresses|instances).(insert|patch|update|delete)"`
- **Поля:** `methodName`, `resourceName`, `request` (правило/источники), `principalEmail`.
- **Ожидаемый результат:** событие на создание firewall-правила, внешнего IP, VM и т.п.
- **False positives:** изменения сети через Terraform (штатные).
- **Severity:** ERROR.
- **Triage:** владелец и назначение ресурса, наличие в коде/реестре, сетевая экспозиция (источники `0.0.0.0/0`, порты, есть ли VM в сети).
- **Ограничения:** не оценивает опасность правила; не видит ресурсы, созданные вне проекта.

## D-08. Необычный успешный доступ к объектам (ручная процедура)

- **Источник:** Data Access логи Cloud Storage (`storage.objects.get`/`list`), `security-audit` log bucket.
- **Запрос (Log Analytics):** см. [queries.md](queries.md), раздел «Профиль доступа к объектам».
- **Что искать:** новая identity, чтение CONFIDENTIAL, всплеск числа обращений, время вне окна, `callerIp` вне ожидаемых.
- **Ограничения:** нет алерта; логи содержат объект, identity и IP, но **не** содержимое и не объём скачанного по каждому запросу в удобном виде; Data Access логи включены только для Storage и IAM.
