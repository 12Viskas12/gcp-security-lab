# RB-002. Необычный доступ к данным: отказы, impersonation, чтение CONFIDENTIAL

**Триггеры:** `SEC | Cloud Storage PERMISSION_DENIED` (D-05), `SEC | Service account token generated (impersonation)` (D-06), ручная процедура D-08. **Severity:** WARNING (ERROR при успешном чтении CONFIDENTIAL неожиданной identity).

## 1. Triage

1. Кто получает отказы / кто выпускает токены (`principalEmail`, `serviceAccountDelegationInfo`)?
2. Объём и паттерн: единичная ошибка (шум) или серия по разным объектам (разведка)?
3. Источник (`callerIp`, user agent): известен ли?
4. Были ли успешные обращения (`status.code = 0`) этой identity, в первую очередь к `confidential/`?

## 2. Запросы

```bash
gcloud logging read 'resource.type="gcs_bucket" AND protoPayload.status.code=7' --project="$PROJECT_ID" --freshness=1h \
  --format='table(timestamp, protoPayload.authenticationInfo.principalEmail, protoPayload.resourceName, protoPayload.requestMetadata.callerIp)'
gcloud logging read 'protoPayload.serviceName="iamcredentials.googleapis.com" AND protoPayload.methodName="GenerateAccessToken"' \
  --project="$PROJECT_ID" --freshness=1h
```

## 3. Решение

Лабораторное действие — закрыть с записью. Подозрительное — Containment.

## 4. Containment

- Отозвать `serviceAccountTokenCreator` у принципала, который выпускает токены.
- Отключить SA: `gcloud iam service-accounts disable SA_EMAIL`.
- Проверить, кто может impersonate: `gcloud iam service-accounts get-iam-policy SA_EMAIL`.

## 5. Recovery и проверка

Включить SA (`enable`), подтвердить права по `docs/iam-review.md`, `scripts/verify.sh`, записать в `incidents/incident-03.md`.
