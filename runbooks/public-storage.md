# RB-001. Публичное раскрытие bucket / изменение политик Cloud Storage

**Триггер:** `SEC | Cloud Storage bucket policy/config changed` (D-02). **Severity:** ERROR/CRITICAL. Общий процесс: [incident-response.md](incident-response.md).

## 1. Triage

1. Найди событие: `resource.type="gcs_bucket" protoPayload.methodName=~"(?i)setiampermissions|buckets.(update|patch|delete)"`.
2. Определи: кто (`principalEmail`), откуда (`callerIp`), что (`policyDelta`/`request`), успешно ли (`status.code`; 9 = отклонено Public Access Prevention).
3. Запланированное изменение? Сверь с Git/тикетом.

## 2. Проверка текущего состояния

```bash
gcloud storage buckets describe "gs://${BUCKET}" --format='value(public_access_prevention,uniform_bucket_level_access)'
gcloud storage buckets get-iam-policy "gs://${BUCKET}" --format=json | grep -E 'allUsers|allAuthenticatedUsers'
curl -s -o /dev/null -w '%{http_code}\n' "https://storage.googleapis.com/${BUCKET}/internal/employee-directory-SYNTHETIC.csv"   # ожидается 401/403
```

## 3. Containment

- Если bucket публичен: `gcloud storage buckets update "gs://${BUCKET}" --public-access-prevention`, затем убрать публичные привязки (`remove-iam-policy-binding ... --member=allUsers ...`).
- Если действовал неизвестный principal: отозвать его роли, при компрометации отключить аккаунт/SA.

## 4. Оценка ущерба

Data Access логи по bucket за период экспозиции: чтения от `allUsers`/внешних identity. Нет логов — считать доступ неизвестным и фиксировать как риск.

## 5. Eradication / Recovery / Проверка

Убрать причину (лишние права у principal, у которого есть `setIamPolicy`). `terraform plan` без дрейфа, `scripts/verify.sh` — `FAIL=0`.

## 6. После инцидента

Заполнить `incidents/incident-02.md`, обновить модель угроз (T-02) и отчёт.
